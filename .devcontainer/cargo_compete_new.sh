#!/bin/bash

set -e

usage() {
  cat <<'EOF'
Usage: cargo_compete_new.sh <contest> [-o max|min] [-i] [--force-tools]

  <contest>         Contest id (e.g. ahc066)
  -o max|min        pahcer objective (default: max)
  -i                Interactive problem
  --force-tools     Re-download and extract official tools ZIP
EOF
  exit 1
}

contest=""
objective="max"
interactive=0
force_tools=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      [[ $# -ge 2 ]] || usage
      objective="$2"
      shift 2
      ;;
    -i)
      interactive=1
      shift
      ;;
    --force-tools)
      force_tools=1
      shift
      ;;
    -h|--help)
      usage
      ;;
    -*)
      echo "Error: Unknown option: $1" >&2
      usage
      ;;
    *)
      if [[ -z "$contest" ]]; then
        contest="$1"
        shift
      else
        echo "Error: Unexpected argument: $1" >&2
        usage
      fi
      ;;
  esac
done

[[ -n "$contest" ]] || usage

if [[ "$objective" != "max" && "$objective" != "min" ]]; then
  echo "Error: -o must be max or min" >&2
  exit 1
fi

if [[ -z "${WORKSPACE_FOLDER:-}" ]]; then
  echo "Error: WORKSPACE_FOLDER is not set" >&2
  exit 1
fi

cd "$WORKSPACE_FOLDER"

settings_json_path="$WORKSPACE_FOLDER/.vscode/settings.json"
contest_directory="./src/contest"
contest_dir="$WORKSPACE_FOLDER/src/contest/$contest"
cargo_toml_path="$contest_directory/$contest/Cargo.toml"
new_entry="        \"$cargo_toml_path\""

# --- Step 1: Locate where to insert the new entry in settings.json ---
mapfile -t lines < "$settings_json_path"
insert_line_index=-1
found_array_start=0

for i in "${!lines[@]}"; do
  line="${lines[$i]}"

  if [[ "$line" =~ \"rust-analyzer\.linkedProjects\" ]]; then
    found_array_start=1
    continue
  fi

  if [[ "$found_array_start" -eq 1 && "${line}" =~ ^[[:space:]]*\] ]]; then
    insert_line_index=$i
    break
  fi
done

if [ "$insert_line_index" -eq -1 ]; then
  echo "Error: Cannot find rust-analyzer.linkedProjects array in settings.json" >&2
  exit 1
fi

# --- Step 2: Generate the contest directory using cargo-compete ---
cargo compete new "$contest"

# --- Step 3: Add the new linked project path to settings.json ---
tmpfile=$(mktemp)
for i in "${!lines[@]}"; do
  if [ "$i" -eq "$insert_line_index" ]; then
    echo "$new_entry," >> "$tmpfile"
  fi
  echo "${lines[$i]}" >> "$tmpfile"
done
mv "$tmpfile" "$settings_json_path"

echo "✅ Successfully added: $cargo_toml_path to settings.json"

# --- Step 4: Create .gitkeep files in testcases ---
create_gitkeep_in_testcases.sh "$contest_directory/$contest"

# --- Step 5: Download and extract official local tools (vis/gen/in) ---
setup_tools() {
  local task_html="$contest_dir/task.html"

  if [[ -d "$contest_dir/tools" && "$force_tools" -eq 0 ]]; then
    echo "ℹ tools/ already exists (use --force-tools to re-download)"
    return 0
  fi

  if [[ ! -f "$task_html" ]]; then
    echo "Error: $task_html not found. Cannot download tools." >&2
    exit 1
  fi

  local zip_url
  zip_url=$(grep -oE "https://img\.atcoder\.jp/${contest}/[^\"]+\.zip" "$task_html" | grep -v _windows | head -1)

  if [[ -z "$zip_url" ]]; then
    echo "Error: Could not find tools ZIP URL in task.html" >&2
    exit 1
  fi

  echo "📦 Downloading tools from $zip_url"
  local tmpzip
  tmpzip=$(mktemp --suffix=.zip)
  curl -fsSL "$zip_url" -o "$tmpzip"
  unzip -o -q "$tmpzip" -d "$contest_dir"
  rm -f "$tmpzip"

  if [[ ! -f "$contest_dir/tools/src/bin/vis.rs" ]]; then
    echo "Error: tools extraction failed (vis.rs not found)" >&2
    exit 1
  fi

  echo "✅ tools/ ready"
}

# --- Step 6: pahcer init ---
setup_pahcer() {
  if [[ -f "$contest_dir/pahcer_config.toml" ]]; then
    echo "ℹ pahcer_config.toml already exists (skipping pahcer init)"
    return 0
  fi

  local pahcer_args=(init -p "$contest" -o "$objective" -l rust)
  if [[ "$interactive" -eq 1 ]]; then
    pahcer_args+=(-i)
  fi

  echo "⚙ Running pahcer ${pahcer_args[*]}"
  (cd "$contest_dir" && pahcer "${pahcer_args[@]}")
  echo "✅ pahcer_config.toml created"
}

# Contest-local Cargo target-dir. Without this, `cargo build --release` run from
# the contest dir (as pahcer and rust-analyzer do) walks up to the outer repo's
# .cargo/config.toml and writes to $WORKSPACE_FOLDER/target. Pinning it here keeps
# every build artifact inside the contest dir, so the folder is self-contained
# when opened on its own for pahcer-UI. Committed to the contest repo because
# pahcer-UI copySource needs it.
setup_cargo_config() {
  local cargo_config="$contest_dir/.cargo/config.toml"
  if [[ -f "$cargo_config" ]]; then
    echo "ℹ .cargo/config.toml already exists"
    return 0
  fi
  mkdir -p "$contest_dir/.cargo"
  cat > "$cargo_config" <<'CARGOCFG'
# Keep all build output inside this contest dir (managed by cargo_compete_new.sh).
# rust-analyzer artifacts are split into target/rust-analyzer via
# rust-analyzer.cargo.targetDir (see .devcontainer/devcontainer.json).
[build]
target-dir = "target"
CARGOCFG
  echo "✅ .cargo/config.toml written (target-dir = \"target\", contest-local)"
}

# Point pahcer's "move the compiled binary" step at the contest-local target dir
# (see setup_cargo_config). pahcer init emits the bin name without the "-a"
# suffix; the actual Cargo bin is "<contest>-a".
configure_pahcer_binary_path() {
  local config_path="$contest_dir/pahcer_config.toml"
  local desired="args = [\"./target/release/${contest}-a\", \"./${contest}\"]"
  # Older shapes we may need to migrate from (fresh pahcer init, or a contest
  # set up by a previous version of this script that used the shared target).
  local -a candidates=(
    "args = [\"./target/release/${contest}\", \"./${contest}\"]"
    "args = [\"${WORKSPACE_FOLDER}/target/release/${contest}-a\", \"./${contest}\"]"
  )

  if [[ ! -f "$config_path" ]]; then
    echo "Error: $config_path not found" >&2
    exit 1
  fi

  if grep -Fqx "$desired" "$config_path"; then
    echo "ℹ pahcer binary path already configured"
    return 0
  fi

  local from
  for from in "${candidates[@]}"; do
    if grep -Fqx "$from" "$config_path"; then
      python3 - "$config_path" "$from" "$desired" <<'PY'
import sys
path, frm, to = sys.argv[1:4]
open(path, "w").write(open(path).read().replace(frm, to))
PY
      echo "✅ pahcer binary path set to ./target/release/${contest}-a (contest-local target)"
      return 0
    fi
  done

  echo "⚠ Expected pahcer binary args not found in $config_path; leaving as-is" >&2
}

setup_optuna_config() {
  if [[ -f "$contest_dir/optuna_config.toml" ]]; then
    if [[ ! -f "$contest_dir/.gitignore" ]] || ! grep -Fqx "/.optuna/" "$contest_dir/.gitignore"; then
      {
        echo ""
        echo "# Optuna studies and generated runtime files"
        echo "/.optuna/"
      } >> "$contest_dir/.gitignore"
    fi
    echo "ℹ optuna_config.toml already exists"
    return 0
  fi
  if ! command -v ahc_optuna >/dev/null 2>&1; then
    echo "⚠ ahc_optuna is unavailable; rebuild the Dev Container to enable tuning" >&2
    return 0
  fi
  (cd "$contest_dir" && ahc_optuna init)
  echo "✅ Optuna tuning template created"
}

# --- Step 7: make the contest its own git repo ---
# The vscode-pahcer-ui extension resolves source paths relative to the git root
# (git ls-tree / git show), so its "copy source at this commit" feature only
# works when the contest directory IS the git root. Give each contest its own
# repository and keep the outer devcontainer repo from tracking it.
ensure_outer_gitignore_entry() {
  local entry="/src/contest/$contest/"
  local gi="$WORKSPACE_FOLDER/.gitignore"

  if [[ -f "$gi" ]] && grep -Fqx "$entry" "$gi"; then
    return 0
  fi

  {
    echo ""
    echo "# Per-contest git repo (managed independently for pahcer-UI); not tracked here"
    echo "$entry"
  } >> "$gi"
  echo "✅ Added $entry to .gitignore (outer repo)"
}

setup_contest_git() {
  if [[ -d "$contest_dir/.git" ]]; then
    echo "ℹ $contest already has its own git repo (skipping git init)"
    return 0
  fi

  ensure_outer_gitignore_entry

  # If the outer repo was already tracking this contest, untrack it (staged only;
  # the working tree is untouched and the user commits the removal when ready).
  if git -C "$WORKSPACE_FOLDER" ls-files --error-unmatch "src/contest/$contest" >/dev/null 2>&1; then
    git -C "$WORKSPACE_FOLDER" rm -r --cached --quiet "src/contest/$contest" >/dev/null 2>&1 || true
    echo "✅ Untracked src/contest/$contest from the outer repo (staged; commit when ready)"
  fi

  # Contest-local ignore: keep tools/, run outputs and binaries out of the
  # contest repo so the pahcer-UI "Run" commit snapshots only the solver source.
  cat > "$contest_dir/.gitignore" <<'GITIGNORE'
# Build output
/target/
*.rs.bk
*.pdb

# Compiled solver binary that pahcer moves into the contest dir
/ahc[0-9]*

# Official local tools + generated inputs/outputs (large, regenerable)
/tools/

# pahcer run history / best scores (regenerable)
/pahcer/

# pahcer-UI local state (result archives, visualizer, meta)
/.pahcer-ui/

# Optuna studies and generated runtime files
/.optuna/

# legacy pahcer-studio (separate cloned repo)
/pahcer-studio/
GITIGNORE

  git -C "$contest_dir" init -q
  git -C "$contest_dir" add -A >/dev/null 2>&1 || true
  git -C "$contest_dir" commit -q -m "init $contest" >/dev/null 2>&1 || true
  echo "✅ Initialized git repo in $contest_dir (pahcer-UI copySource enabled)"
}

setup_tools
setup_pahcer
setup_cargo_config
configure_pahcer_binary_path
setup_optuna_config
setup_contest_git

# --- Step 8: Remember contest dir for ahc_cd ---
echo "$contest_dir" > "$WORKSPACE_FOLDER/.ahc_last_contest"

echo ""
echo "✅ AHC setup complete for $contest"
echo ""
echo "   cd \"$contest_dir\""
echo "   # or: ahc_cd"
echo ""
echo "   Open this contest folder in VS Code and use the pahcer-UI extension"
echo "   (Pahcer: テストを実行) to run tests and browse results."
