#!/usr/bin/env bash
# Prepare WSL2 Ubuntu to run the workbench rig: Node 22 (nvm), Claude Code, OpenRig CLI.
set -euo pipefail
export NVM_DIR="$HOME/.nvm"
if [ ! -s "$NVM_DIR/nvm.sh" ]; then
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
fi
. "$NVM_DIR/nvm.sh"
nvm install 22
nvm alias default 22
echo "node $(node --version) at $(command -v node); npm $(npm --version) at $(command -v npm)"
npm install -g @anthropic-ai/claude-code @openrig/cli
echo "claude: $(claude --version)"
echo "rig: $(rig --version)"
echo "tmux: $(tmux -V)"
