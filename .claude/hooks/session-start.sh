#!/bin/bash
set -euo pipefail

# SessionStart hook: make Godot + the Godot MCP/skills available in every
# Claude Code on the web session for this repo.

# Only needed in remote (web) containers
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

GODOT_VERSION="4.4.1"
GODOT_BIN="$HOME/.local/bin/godot"

# 1. Godot editor binary (cached with the container snapshot after first run)
if [ ! -x "$GODOT_BIN" ]; then
  mkdir -p "$HOME/.local/bin"
  curl -sL --retry 3 --max-time 240 -o /tmp/godot_dl.zip \
    "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
  unzip -o -q /tmp/godot_dl.zip -d /tmp/godot_extract
  mv "/tmp/godot_extract/Godot_v${GODOT_VERSION}-stable_linux.x86_64" "$GODOT_BIN"
  chmod +x "$GODOT_BIN"
  rm -rf /tmp/godot_dl.zip /tmp/godot_extract
fi

# Expose Godot to the session shell and to godot-mcp
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  {
    echo 'export PATH="$HOME/.local/bin:$PATH"'
    echo "export GODOT_PATH=\"$GODOT_BIN\""
  } >> "$CLAUDE_ENV_FILE"
fi

# 2. Godot skills: copy the repo's project skills to the global skills dir
#    (the project copies in .claude/skills/ are already auto-loaded; the
#    global copies make them available outside this repo too)
mkdir -p "$HOME/.claude/skills"
for d in "$CLAUDE_PROJECT_DIR"/.claude/skills/godot*; do
  name="$(basename "$d")"
  if [ -d "$d" ] && [ ! -e "$HOME/.claude/skills/$name" ]; then
    cp -r "$d" "$HOME/.claude/skills/$name"
  fi
done

# 3. godot-mcp server registered in the global settings (idempotent merge)
python3 - << 'PY'
import json, os
p = os.path.expanduser("~/.claude/settings.json")
data = {}
if os.path.exists(p):
    try:
        with open(p) as f:
            data = json.load(f)
    except Exception:
        data = {}
data.setdefault("mcpServers", {})["godot"] = {"command": "npx", "args": ["-y", "godot-mcp"]}
with open(p, "w") as f:
    json.dump(data, f, indent=2)
PY

# 4. Headless display + software GL so the game can run and take screenshots
if ! command -v xvfb-run > /dev/null 2>&1; then
  (apt-get update -qq && apt-get install -y -qq xvfb mesa-utils libgl1-mesa-dri) > /dev/null 2>&1 || true
fi

echo "Godot ${GODOT_VERSION}, skills, godot-mcp and Xvfb ready"
