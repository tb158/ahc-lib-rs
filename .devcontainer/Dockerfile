FROM rust:1.89.0-bookworm

ENV CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000
ENV PATH="/opt/ahc-optuna/bin:${PATH}"

RUN apt-get update && \
    apt-get install -y curl unzip nodejs npm python3 python3-venv util-linux && \
    npm install -g @anthropic-ai/claude-code && \
    npm install -g @openai/codex && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    rustup toolchain install 1.89.0 && \
    rustup component add rustfmt clippy && \
    # Analysis-only toolchain for rust-analyzer (see rust-analyzer.cargo.extraEnv
    # in .vscode/settings.json). The RA extension tracks the latest stable, and
    # against the 1.89.0 sysroot it fails to resolve std macros (`vec!`,
    # `println!`, `write!`) and alloc-gated methods (`Vec::push`), which surfaces
    # as bogus E0308s. Builds and submissions still use 1.89.0 (judge parity).
    # rustfmt/clippy are needed here too: rust-analyzer spawns them with the env from
    # rust-analyzer.cargo.extraEnv (RUSTUP_TOOLCHAIN=stable), so "Format Document"
    # silently fails unless the stable toolchain carries the component.
    rustup toolchain install stable --profile minimal --component rust-src --component rustfmt --component clippy && \
    # cargo install cargo-compete --locked && \
    # slow-cat's fork (Apache-2.0). Save license for compliance.
    cargo install --git https://github.com/tb158/cargo-compete --branch develop --locked && \
    cargo install cargo-snippet --features="binaries" && \
    cargo install pahcer --version 0.4.0 --locked

COPY ./requirements-ahc-optuna.txt /tmp/requirements-ahc-optuna.txt

RUN python3 -m venv /opt/ahc-optuna && \
    /opt/ahc-optuna/bin/pip install --no-cache-dir -r /tmp/requirements-ahc-optuna.txt && \
    rm -f /tmp/requirements-ahc-optuna.txt

COPY ./entrypoint.sh ./cargo_compete_new.sh ./create_gitkeep_in_testcases.sh ./run_pahcer_for_ui.sh ./cargo_snippet.sh ./ahc_optuna.sh /usr/local/bin/

# Interactive-shell helpers (ahc_cd etc.) are installed by
# install_shell_helpers.sh on every container start, sourced from the workspace.
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/cargo_compete_new.sh /usr/local/bin/create_gitkeep_in_testcases.sh /usr/local/bin/run_pahcer_for_ui.sh /usr/local/bin/cargo_snippet.sh /usr/local/bin/ahc_optuna.sh && \
    ln -s /usr/local/bin/ahc_optuna.sh /usr/local/bin/ahc_optuna
