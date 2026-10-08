#!/usr/bin/env bash
# Copy the built-in agent specs this rig uses into a rig root, so seats are not
# affected by edits the OpenRig engineer makes to packages/daemon/specs/agents.
# Usage: vendor-agents.sh <rig-root>   (e.g. /mnt/e/rigs/workbench or ~/rigs/workbench)
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
src="$repo/packages/daemon/specs/agents"
dst="${1:?usage: vendor-agents.sh <rig-root>}/agents"
mkdir -p "$dst/orchestration" "$dst/development" "$dst/review"
cp -r "$src/shared" "$dst/"
cp -r "$src/orchestration/orchestrator" "$dst/orchestration/"
cp -r "$src/development/implementer" "$dst/development/"
cp -r "$src/review/independent-reviewer" "$dst/review/"
cp "$repo/workbench/rig.yaml" "${1}/rig.yaml"
echo "Rig root ready: $1"
