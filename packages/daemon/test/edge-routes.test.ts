import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type Database from "better-sqlite3";
import { createFullTestDb, createTestApp } from "./helpers/test-app.js";

// POST /api/rigs/:rigId/edges and DELETE /api/rigs/:rigId/edges/:edgeId —
// connecting and disconnecting seats of a running rig, across pods.
describe("edge routes", () => {
  let db: Database.Database;
  let setup: ReturnType<typeof createTestApp>;

  beforeEach(() => {
    db = createFullTestDb();
    setup = createTestApp(db);
  });

  afterEach(() => { db.close(); });

  /** A rig with seats in two pods, as `orch.lead` and `dev.impl`. */
  function seedRig() {
    const rig = setup.rigRepo.createRig("edge-rig");
    const lead = setup.rigRepo.addNode(rig.id, "orch.lead", { runtime: "claude-code" });
    const impl = setup.rigRepo.addNode(rig.id, "dev.impl", { runtime: "claude-code" });
    return { rig, lead, impl };
  }

  function addEdge(rigId: string, body: Record<string, unknown>) {
    return setup.app.request(`/api/rigs/${rigId}/edges`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
  }

  it("connects two seats in different pods by logical id and emits edge.added", async () => {
    const { rig, lead, impl } = seedRig();
    const res = await addEdge(rig.id, { from: "orch.lead", to: "dev.impl", kind: "delegates_to" });

    expect(res.status).toBe(201);
    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(body.edge).toMatchObject({ sourceId: lead.id, targetId: impl.id, kind: "delegates_to" });

    const edges = setup.rigRepo.getRig(rig.id)!.edges;
    expect(edges).toHaveLength(1);
    const events = setup.eventBus.replaySince(0, rig.id).filter((e) => e.type === "edge.added");
    expect(events).toHaveLength(1);
    expect(events[0]).toMatchObject({ edgeId: body.edge.id, kind: "delegates_to" });
  });

  it("accepts node ids as endpoints", async () => {
    const { rig, lead, impl } = seedRig();
    const res = await addEdge(rig.id, { from: impl.id, to: lead.id, kind: "escalates_to" });
    expect(res.status).toBe(201);
  });

  it("refuses an unknown kind, a missing seat, a self-edge and a duplicate", async () => {
    const { rig } = seedRig();

    const badKind = await addEdge(rig.id, { from: "orch.lead", to: "dev.impl", kind: "likes" });
    expect(badKind.status).toBe(400);
    expect((await badKind.json()).message).toContain("delegates_to");

    const missing = await addEdge(rig.id, { from: "orch.lead", to: "dev.nobody", kind: "delegates_to" });
    expect(missing.status).toBe(404);
    expect((await missing.json()).code).toBe("node_not_found");

    const self = await addEdge(rig.id, { from: "orch.lead", to: "orch.lead", kind: "delegates_to" });
    expect(self.status).toBe(400);

    expect((await addEdge(rig.id, { from: "orch.lead", to: "dev.impl", kind: "delegates_to" })).status).toBe(201);
    const duplicate = await addEdge(rig.id, { from: "orch.lead", to: "dev.impl", kind: "delegates_to" });
    expect(duplicate.status).toBe(409);
    expect((await duplicate.json()).code).toBe("edge_exists");
  });

  it("returns 404 for an unknown rig", async () => {
    const res = await addEdge("nonexistent", { from: "a.b", to: "c.d", kind: "delegates_to" });
    expect(res.status).toBe(404);
  });

  it("removes an edge and emits edge.removed", async () => {
    const { rig } = seedRig();
    const created = await (await addEdge(rig.id, { from: "orch.lead", to: "dev.impl", kind: "can_observe" })).json();

    const res = await setup.app.request(`/api/rigs/${rig.id}/edges/${created.edge.id}`, { method: "DELETE" });
    expect(res.status).toBe(200);
    expect(setup.rigRepo.getRig(rig.id)!.edges).toHaveLength(0);
    const events = setup.eventBus.replaySince(0, rig.id).filter((e) => e.type === "edge.removed");
    expect(events).toHaveLength(1);

    const again = await setup.app.request(`/api/rigs/${rig.id}/edges/${created.edge.id}`, { method: "DELETE" });
    expect(again.status).toBe(404);
    expect((await again.json()).code).toBe("edge_not_found");
  });
});
