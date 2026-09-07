#!/bin/bash

# Interactive-shell helpers for the AHC devcontainer.
# Sourced from /root/.bashrc by install_shell_helpers.sh, straight out of the
# bind-mounted workspace, so edits here take effect in the next shell without a
# container rebuild.

ahc_cd() {
    local contest_file="${WORKSPACE_FOLDER:?WORKSPACE_FOLDER is not set}/.ahc_last_contest"
    if [[ ! -f "$contest_file" ]]; then
        echo "Error: No contest directory has been recorded yet." >&2
        echo "Run cargo_compete_new.sh <contest> first." >&2
        return 1
    fi

    local contest_dir
    contest_dir=$(<"$contest_file")
    if [[ ! -d "$contest_dir" ]]; then
        echo "Error: Contest directory not found: $contest_dir" >&2
        return 1
    fi

    cd "$contest_dir"
}

# Run the setup script from the workspace (not the image copy) and land in the
# new contest directory on success.
function cargo_compete_new.sh {
    bash "${WORKSPACE_FOLDER:?WORKSPACE_FOLDER is not set}/.devcontainer/cargo_compete_new.sh" "$@" || return
    ahc_cd
}

# Same for the pahcer-UI runner: always use the workspace copy.
function run_pahcer_for_ui.sh {
    bash "${WORKSPACE_FOLDER:?WORKSPACE_FOLDER is not set}/.devcontainer/run_pahcer_for_ui.sh" "$@"
}

# git for the public mirror tb158/ahc-lib-rs, which publishes .vscode/ +
# .devcontainer/ so submitted code can cite a pre-contest URL (AtCoder's
# generative-AI rule). It shares this work tree through a second git dir, so
# every command needs --git-dir/--work-tree; this wraps that.
#
#   ahclib status
#   ahclib add .vscode .devcontainer && ahclib commit -m "..." && ahclib push
#
# What it may publish is fixed by a whitelist in .git-ahc-lib-rs/info/exclude
# (this repo's .gitignore does not apply here -- that filename belongs to
# tb158/AHC). src/ and docs/ can therefore never be staged, even with `add -A`.
ahclib() {
    local root="${WORKSPACE_FOLDER:?WORKSPACE_FOLDER is not set}"
    if [[ ! -d "$root/.git-ahc-lib-rs" ]]; then
        echo "Error: $root/.git-ahc-lib-rs not found." >&2
        return 1
    fi
    git --git-dir="$root/.git-ahc-lib-rs" --work-tree="$root" "$@"
}
