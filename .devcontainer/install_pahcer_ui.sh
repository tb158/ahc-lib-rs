#!/usr/bin/env bash
# Install the pahcer-ui extension from a bundled .vsix.
#
# Extensions live in ~/.cursor-server (or ~/.vscode-server) inside the container,
# which is NOT a persisted volume, so they are lost on every container rebuild.
# This script re-installs it on attach. The .vsix lives next to this script, in
# the bind-mounted workspace, so it survives rebuilds without an image rebuild.
set -uo pipefail

EXT_ID="statiolake.vscode-pahcer-ui"
VSIX="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pahcer-ui.vsix"

if ! command -v code >/dev/null 2>&1; then
    echo "[pahcer-ui] 'code' CLI not found in PATH; skipping install." >&2
    exit 0
fi

if code --list-extensions | grep -qix "$EXT_ID"; then
    echo "[pahcer-ui] $EXT_ID already installed."
    exit 0
fi

if [[ ! -f "$VSIX" ]]; then
    echo "[pahcer-ui] vsix not found at $VSIX; cannot install $EXT_ID." >&2
    exit 0
fi

echo "[pahcer-ui] installing $EXT_ID from $VSIX ..."
code --install-extension "$VSIX" --force

# `code --install-extension` exits 0 even when it fails, so verify explicitly.
if code --list-extensions | grep -qix "$EXT_ID"; then
    echo "[pahcer-ui] installed $EXT_ID. Reload the window to activate it."
else
    echo "[pahcer-ui] FAILED to install $EXT_ID from $VSIX." >&2
fi
