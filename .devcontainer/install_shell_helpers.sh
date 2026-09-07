#!/bin/bash

set -e

# Put the Rust toolchain back on PATH for login shells. The base image exports
# /usr/local/cargo/bin via Docker ENV, but /etc/profile resets PATH for login
# shells, so `cargo` ends up "command not found".
# /etc/profile.d/*.sh is sourced by login shells, restoring it.
cat > /etc/profile.d/cargo-path.sh <<'PROFILE_EOF'
# Ensure the Rust toolchain (cargo/rustc via rustup) is on PATH for login shells.
cargo_bin="${CARGO_HOME:-/usr/local/cargo}/bin"
case ":${PATH}:" in
    *":${cargo_bin}:"*) ;;
    *) export PATH="${cargo_bin}:${PATH}" ;;
esac
unset cargo_bin
PROFILE_EOF

# Superseded by shell_helpers.sh (which defines ahc_cd out of the workspace).
rm -f /etc/profile.d/ahc-pahcer.sh

bashrc_path="/root/.bashrc"
block_start="# >>> workspace shell helpers >>>"
block_end="# <<< workspace shell helpers <<<"

if grep -Fq "$block_start" "$bashrc_path"; then
    sed -i "/$block_start/,/$block_end/d" "$bashrc_path"
fi

cat >> "$bashrc_path" <<'EOF'

# >>> workspace shell helpers >>>
if [[ -n "${WORKSPACE_FOLDER:-}" && -f "$WORKSPACE_FOLDER/.devcontainer/shell_helpers.sh" ]]; then
    source "$WORKSPACE_FOLDER/.devcontainer/shell_helpers.sh"
fi
# <<< workspace shell helpers <<<
EOF
