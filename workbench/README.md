# Workbench

A personal OpenRig setup: one rig that runs an orchestrator, four project
engineers and a reviewer, plus the plan for a graphical front end to drive it.

> **Status (2026-10-07): running.** All six seats are up in WSL2 and waiting
> for work. Both setup blockers are resolved; see [Blockers](#blockers).

## Goal

Build a modern, intuitive desktop GUI for OpenRig, probably in Rust, where:

- The rig is an **infinite canvas**: click and drag to pan and scroll to zoom,
  like Google Maps.
- Each seat is a **block on the canvas that shows its live terminal**. You can
  read the output and type into the terminal directly in the block.
- You **add a seat by dragging it onto the canvas** and configure it on the
  spot: runtime, model, working directory and agent role.
- Seats, factories and flows are **easy to add, edit and remove**. The edges
  between seats (delegates to, can observe and so on) are drawn and edited
  visually.
- The GUI reads and writes the same rig spec (`rig.yaml`) the CLI uses, so
  anything built in the GUI can still be run with `rig up`.

### Architecture

OpenRig's daemon is built on tmux, which does not run on native Windows.
Instead of porting the daemon, the GUI acts as a client:

```
Windows / Linux desktop: GUI (canvas, seat blocks, drag-to-configure)
      │  HTTP: daemon API on 127.0.0.1:7433       │  terminal I/O per block
      ▼                                           ▼
Linux (WSL2 on Windows, native on Arch):  rig daemon ── tmux session per seat
```

- **Topology and configuration** go through the daemon's HTTP API and the rig
  spec. On Windows, WSL2 shares localhost: `curl http://127.0.0.1:7433/healthz`
  from Windows returns `200` while the daemon runs in WSL.
- **Live terminals:** each block runs its own terminal process that attaches to
  the seat's tmux session (`wsl tmux attach -t '=<session>'` on Windows, or
  `tmux attach` on Linux). Typing in the block goes straight to the seat.
- **Options for the GUI stack:**
  - Pure Rust: egui or Iced, plus `alacritty_terminal` or `wezterm-term` and
    `portable-pty`.
  - Tauri: a Rust backend with a web front end, using xterm.js for the
    terminals and React Flow for the canvas. This is probably the fastest way
    to a polished canvas with live blocks you can type into.
- **Dropping WSL2 later** would mean replacing OpenRig's tmux session layer with
  something that works on Windows (for example ConPTY through `portable-pty`).
  That's a separate, much larger project. Don't start it until the GUI has
  proven itself.

## The rig

`rig.yaml`, rig name `workbench`:

| Seat | Session | Runtime / model | Working directory |
|---|---|---|---|
| Orchestrator (the one you talk to) | `orch-lead@workbench` | claude-code / `claude-sonnet-5-5` | rig root |
| Home Ledger engineer | `eng-ledger@workbench` | claude-code / `claude-opus-5-5` | `/mnt/e/finance-application/home-ledger-public` |
| netwatch engineer | `eng-netwatch@workbench` | claude-code / `claude-opus-5-5` | `/mnt/e/netwatch` |
| OpenRig engineer | `eng-openrig@workbench` | claude-code / `claude-opus-5-5` | `/mnt/e/openrig` |
| gym engineer | `eng-gym@workbench` | claude-code / `claude-opus-5-5` | `/mnt/e/gym` |
| Rig Workbench engineer | `eng-rig-workbench@workbench` | claude-code / `claude-opus-5-5` | `/mnt/e/rig-workbench` |
| Reviewer | `review-reviewer@workbench` | claude-code / `claude-opus-5-5` | rig root |

- **Edges:** the orchestrator `delegates_to` every engineer and the reviewer.
  The reviewer `can_observe` every engineer. The OpenRig and Rig Workbench
  engineers each have a `delegates_to` edge to the other.
- **Agent roles:** the built-in `orchestrator`, `implementer` and
  `independent-reviewer` specs. These are copied into the rig root's `agents/`
  folder (see `scripts/vendor-agents.sh`) so that edits the OpenRig engineer
  makes in this repo don't change the other seats' definitions while they run.
- **Instruction files:** `managed_blocks: claude-code: CLAUDE.local.md` makes
  OpenRig write its instructions into `CLAUDE.local.md` and never touch a
  project's `CLAUDE.md`. OpenRig creates `CLAUDE.local.md` (and `.mcp.json`) in
  each seat's working directory. Add them to each repo's `.gitignore` or
  `.git/info/exclude`.
- **Paths:** the `cwd` values are WSL paths. On the Arch laptop, change them to
  wherever the projects are cloned there.

## Setup

### Windows (WSL2 Ubuntu 24.04), as done on 2026-10-07

The live rig root is `E:\rigs\workbench` (`/mnt/e/rigs/workbench`). It sits
outside every project repo.

1. Get into WSL with `wsl -d Ubuntu`. Run everything below from there, not from
   Git Bash, where `wsl -- bash -c '...'` loses `$VARS` and rewrites
   `/mnt/...` paths. If you must call it from Git Bash, set
   `MSYS_NO_PATHCONV=1` and run a script file instead.
2. Run `bash scripts/setup.sh`. It installs nvm and Node 22, then
   `@anthropic-ai/claude-code` and `@openrig/cli` globally. tmux 3.4 was
   already installed.
3. Run `bash scripts/vendor-agents.sh /mnt/e/rigs/workbench`.
4. Log in to Claude Code: `claude`, then `/login` in the WSL terminal. See
   [Blockers](#blockers).
5. Run `rig doctor`. Every check should be OK; the only warning is that cmux
   wasn't found, and cmux is optional.
6. Start the daemon: `rig daemon start --no-kernel`.
   - `--no-kernel` skips OpenRig's own kernel rig (advisor, operator and queue
     seats). The orchestrator here fills the "seat you talk to" role.
7. Launch: `cd /mnt/e/rigs/workbench && rig up ./rig.yaml --plan`, then
   `rig up ./rig.yaml --yes`.
8. Check the seats with `rig ps --nodes --rig workbench`. Attach to the
   orchestrator with `tmux attach -t '=orch-lead@workbench'`.

### Arch Linux

The same steps without the WSL parts: install `tmux` and Node 22 or 24 (nvm or
`pacman -S nodejs-lts-jod`), then follow steps 2–8 using a native rig root such
as `~/rigs/workbench`. Edit the `cwd` paths in `rig.yaml` to point at the local
clones. Native Linux is a supported OpenRig platform; WSL2 is not yet tested
upstream.

## Blockers

### 1. Claude login expired in WSL (resolved)

Resolved by logging in again, then running `rig seat continue` on every seat.
`rig seat continue` found no pending delivery for any seat. The five Opus seats
had already finished their startup on their own. The orchestrator had not: its
startup turn failed while the login was expired, so it was sent a nudge with
`rig send 'orch-lead@workbench' "<please process your startup briefing>"`.

- **Symptom:** all six seats launch Claude Code 2.1.292 but show
  `Login expired · Please run /login` or `Not logged in · Run /login`.
  `rig ps` reports `Startup requires attention: Claude is running but cannot
  continue until the user logs in.`
- **Why:** WSL's `~/.claude/.credentials.json` dates from March 2026.
  `claude auth status` still reports `loggedIn: true` from the cached file, but
  the token is rejected.
- **Fix:** an interactive browser login.
  1. In a WSL terminal, run `claude`, then `/login`. Alternatively, attach to
     any seat (`tmux attach -t '=eng-gym@workbench'`) and run `/login` there.
     All seats share `~/.claude`, so one login covers them all.
  2. Release each seat that's waiting:
     ```bash
     for s in orch-lead eng-ledger eng-netwatch eng-openrig eng-gym review-reviewer; do
       rig seat continue "$s@workbench"
     done
     ```
     If a seat still won't continue, relaunch it fresh:
     `rig up workbench --existing --fresh <logical-id>`.
- **Severity:** low. It isn't a platform problem, so there's no need to move to
  the Arch laptop for it.

### 2. A stale Claude Code shadowed the new one (resolved)

- **Symptom:** the first launch failed in every seat with
  `error: unknown option '--name'`.
- **Cause:** interactive shells put mise's Node 22.16.0 first on `PATH`. Its
  global Claude Code was 2.1.63, which predates `--name`. The nvm install
  (2.1.292) came second.
- **Fix:** upgraded the mise copy as well:
  `PATH=~/.local/share/mise/installs/node/22.16.0/bin:$PATH npm i -g @anthropic-ai/claude-code`.
  Check with `type -a claude` in a seat's shell; every copy should report the
  same version.
- **For the GUI:** it should show the resolved harness version for each seat.
  This failure was invisible from `rig ps` (it only showed a readiness timeout).

### Things to watch

- **WSL idle shutdown:** WSL can stop the distro after the last Windows
  terminal into it closes, which kills the daemon and every seat. Keep a WSL
  terminal open. For an always-on rig, consider `vmIdleTimeout=-1` under
  `[wsl2]` in `%UserProfile%\.wslconfig` (not set yet).
- **No human seat:** with `--no-kernel` there is no `human@host` session, so
  seats can't `rig send` a reply to you. Talk to the orchestrator in its own
  pane (`tmux attach -t '=orch-lead@workbench'`) and read replies there.
- **Permission posture:** no `permission_policy` is set, so seats launch at the
  cautious default (`launch_posture=floor`) and ask before risky actions. See
  the `applying-a-permission-policy` skill to loosen this deliberately.
- **Skill projection warnings:** at launch, OpenRig reports
  `plugin_skill_kept` for skills that already exist in a working directory's
  `.claude/skills/` (for example this repo's own copies). OpenRig keeps the
  existing copy. This is informational.
- **Project state at setup:** `home-ledger-public` had uncommitted changes
  (`CHANGELOG.md`, `Cargo.lock`, `crates/hl/Cargo.toml`). `E:\gym` is not a git
  repository.

## Next steps

1. Clear blocker 1, release the seats and confirm all six are ready in
   `rig ps --nodes --rig workbench`.
2. Smoke-test: ask the orchestrator to send one small task to one engineer, and
   have the reviewer review it.
3. GUI spike: a window with a pan/zoom canvas that shows `rig ps` data from the
   daemon API and one live terminal block attached to a seat's tmux session.
