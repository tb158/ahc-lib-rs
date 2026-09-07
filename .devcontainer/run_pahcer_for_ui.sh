#!/bin/bash

set -euo pipefail

usage() {
  cat <<'EOUSAGE'
Usage: run_pahcer_for_ui.sh [contest-or-dir] [OPTIONS] [-- pahcer-args...]

Run pahcer in the devcontainer and archive the result so the vscode-pahcer-ui
extension (statiolake/vscode-pahcer-ui) picks it up with a commit hash, per-case
outputs/errors, and the "この時点のソースコードをコピー" (copy source) feature working.

This replaces the old run_pahcer_for_studio.sh (pahcer-studio is no longer used).

What it does (mirrors the extension's "Pahcer: テストを実行"):
  1. Commit the current source in the contest's own git repo -> commit hash
  2. pahcer run
  3. Copy tools/out and tools/err into .pahcer-ui/results/result_<id>/{out,err}
  4. Write .pahcer-ui/results/result_<id>/meta/execution.json  ({commitHash})
     and meta/testcase_XXXX.json ({firstInputLine, stderrVars})

Options:
  -c, --comment COMMENT         Comment for the run (passed to pahcer)
  -n, --test-case-count COUNT   Number of cases (default: current config range)
  -s, --start-seed SEED         First seed (default: current config start_seed)
      --shuffle                 Pass --shuffle to pahcer
      --freeze-best-scores      Pass --freeze-best-scores to pahcer
      --no-commit               Skip the source commit (no commit hash recorded)
  -h, --help                    Show this help

Examples:
  run_pahcer_for_ui.sh
  run_pahcer_for_ui.sh ahc068 -c "beam width 200"
  run_pahcer_for_ui.sh ahc068 -s 20 -n 30 --shuffle
  run_pahcer_for_ui.sh ahc068 -- --rank
EOUSAGE
  exit 1
}

contest_or_dir=""
comment=""
test_case_count=""
start_seed=""
shuffle=0
freeze_best_scores=0
no_commit=0
extra_pahcer_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--comment)
      [[ $# -ge 2 ]] || usage
      comment="$2"
      shift 2
      ;;
    -n|--test-case-count)
      [[ $# -ge 2 ]] || usage
      test_case_count="$2"
      shift 2
      ;;
    -s|--start-seed)
      [[ $# -ge 2 ]] || usage
      start_seed="$2"
      shift 2
      ;;
    --shuffle)
      shuffle=1
      shift
      ;;
    --freeze-best-scores)
      freeze_best_scores=1
      shift
      ;;
    --no-commit)
      no_commit=1
      shift
      ;;
    --)
      shift
      extra_pahcer_args=("$@")
      break
      ;;
    -h|--help)
      usage
      ;;
    -*)
      echo "Error: Unknown option: $1" >&2
      usage
      ;;
    *)
      if [[ -z "$contest_or_dir" ]]; then
        contest_or_dir="$1"
        shift
      else
        echo "Error: Unexpected argument: $1" >&2
        usage
      fi
      ;;
  esac
done

resolve_contest_dir() {
  if [[ -n "$contest_or_dir" ]]; then
    if [[ -d "$contest_or_dir" ]]; then
      (cd "$contest_or_dir" && pwd)
      return 0
    fi
    if [[ -n "${WORKSPACE_FOLDER:-}" && -d "$WORKSPACE_FOLDER/src/contest/$contest_or_dir" ]]; then
      echo "$WORKSPACE_FOLDER/src/contest/$contest_or_dir"
      return 0
    fi
    echo "Error: Contest directory not found: $contest_or_dir" >&2
    exit 1
  fi

  if [[ -f "./pahcer_config.toml" ]]; then
    pwd
    return 0
  fi
  if [[ -n "${WORKSPACE_FOLDER:-}" && -f "$WORKSPACE_FOLDER/.ahc_last_contest" ]]; then
    cat "$WORKSPACE_FOLDER/.ahc_last_contest"
    return 0
  fi

  echo "Error: Run from a contest directory or pass a contest id." >&2
  exit 1
}

read_config_int() {
  local key="$1"
  sed -nE "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*([0-9]+).*$/\\1/p" "$config_path" | head -1
}

# Commit the current source in the contest's own git repo (mirrors the
# extension's commitAll("Run")). Prints the resulting commit hash, or nothing.
commit_source() {
  git -C "$contest_dir" rev-parse --git-dir >/dev/null 2>&1 || return 0
  git -C "$contest_dir" add -A >/dev/null 2>&1 || true
  if git -C "$contest_dir" rev-parse HEAD >/dev/null 2>&1; then
    if ! git -C "$contest_dir" diff-index --quiet HEAD 2>/dev/null; then
      git -C "$contest_dir" commit -q -m "Run" >/dev/null 2>&1 || true
    fi
  else
    git -C "$contest_dir" commit -q -m "Run" >/dev/null 2>&1 || true
  fi
  git -C "$contest_dir" rev-parse HEAD 2>/dev/null || true
}

contest_dir="$(resolve_contest_dir)"
contest_dir="$(cd "$contest_dir" && pwd)"
config_path="$contest_dir/pahcer_config.toml"
out_dir="$contest_dir/tools/out"
err_dir="$contest_dir/tools/err"
in_dir="$contest_dir/tools/in"

if [[ ! -f "$config_path" ]]; then
  echo "Error: pahcer_config.toml not found: $config_path" >&2
  exit 1
fi

# Tuning and normal pahcer runs share the solver binary and tools/out + tools/err.
# Keep them mutually exclusive so scores and wall-clock measurements are not corrupted.
mkdir -p "$contest_dir/pahcer"
exec {pahcer_lock_fd}>"$contest_dir/pahcer/.run.lock"
if ! flock -n "$pahcer_lock_fd"; then
  echo "Error: another pahcer or Optuna run is active for this contest" >&2
  exit 1
fi

# Warn if the contest is not its own git repo: the extension resolves source
# paths relative to the git root, so copySource only works when the contest
# directory IS the git root.
git_top="$(git -C "$contest_dir" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$git_top" ]]; then
  echo "⚠ $contest_dir is not a git repository. No commit hash will be recorded."
  echo "  Run cargo_compete_new.sh (or 'git init' here) to enable copySource."
  no_commit=1
elif [[ "$(cd "$git_top" && pwd)" != "$contest_dir" ]]; then
  echo "⚠ $contest_dir is not its own git repository (git root: $git_top)."
  echo "  pahcer-UI copySource needs the contest dir to be the git root."
  echo "  Run cargo_compete_new.sh for new contests, or 'git init' in this directory."
fi

current_start_seed="$(read_config_int start_seed)"
current_end_seed="$(read_config_int end_seed)"
if [[ -z "$current_start_seed" || -z "$current_end_seed" ]]; then
  echo "Error: Could not read start_seed/end_seed from $config_path" >&2
  exit 1
fi

start_seed="${start_seed:-$current_start_seed}"
test_case_count="${test_case_count:-$((current_end_seed - current_start_seed))}"
if [[ ! "$start_seed" =~ ^[0-9]+$ || ! "$test_case_count" =~ ^[1-9][0-9]*$ ]]; then
  echo "Error: start seed must be >= 0 and test case count must be >= 1" >&2
  exit 1
fi
end_seed=$((start_seed + test_case_count))

# --- 1. Commit the source so the extension can recover it later ---
# Commit BEFORE mutating pahcer_config.toml so the snapshot captures the user's
# real source and seed config (not the temporary range), and so the working tree
# is left clean after this run instead of showing a spurious config diff.
commit_hash=""
if [[ "$no_commit" -eq 0 ]]; then
  commit_hash="$(commit_source)"
  if [[ -n "$commit_hash" ]]; then
    echo "Source committed: ${commit_hash:0:7}"
  fi
fi

# --- 2. Temporarily narrow the seed range for this run (restored on exit) ---
config_backup="$(mktemp)"
cp "$config_path" "$config_backup"
cleanup() {
  local exit_code=$?
  trap - EXIT INT TERM
  cp "$config_backup" "$config_path" 2>/dev/null || true
  rm -f "$config_backup"
  exit "$exit_code"
}
trap cleanup EXIT INT TERM

sed -i -E "s/^([[:space:]]*start_seed[[:space:]]*=[[:space:]]*).*/\\1${start_seed}/" "$config_path"
sed -i -E "s/^([[:space:]]*end_seed[[:space:]]*=[[:space:]]*).*/\\1${end_seed}/" "$config_path"

# --- 3. Run pahcer (start from a clean tools/out & tools/err) ---
rm -rf "$out_dir" "$err_dir"

pahcer_args=(run)
[[ -n "$comment" ]] && pahcer_args+=(-c "$comment")
[[ "$shuffle" -eq 1 ]] && pahcer_args+=(--shuffle)
[[ "$freeze_best_scores" -eq 1 ]] && pahcer_args+=(--freeze-best-scores)
[[ ${#extra_pahcer_args[@]} -gt 0 ]] && pahcer_args+=("${extra_pahcer_args[@]}")

marker="$(mktemp)"
echo "Config: start_seed=$start_seed, end_seed=$end_seed"
echo "Running in $contest_dir: pahcer ${pahcer_args[*]}"
(cd "$contest_dir" && pahcer "${pahcer_args[@]}")

# --- 4. Locate the JSON result this run produced ---
json_path="$(find "$contest_dir/pahcer/json" -maxdepth 1 -type f -name 'result_*.json' -newer "$marker" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)"
rm -f "$marker"
if [[ -z "$json_path" || ! -f "$json_path" ]]; then
  echo "Error: pahcer completed, but no new JSON result was found in $contest_dir/pahcer/json" >&2
  exit 1
fi

result_id="$(basename "$json_path")"
result_id="${result_id#result_}"
result_id="${result_id%.json}"
result_root="$contest_dir/.pahcer-ui/results/result_${result_id}"

# --- 5. Archive per-case outputs/errors where the extension looks for them ---
mkdir -p "$result_root/out" "$result_root/err" "$result_root/meta"
[[ -d "$out_dir" ]] && cp -a "$out_dir/." "$result_root/out/" 2>/dev/null || true
[[ -d "$err_dir" ]] && cp -a "$err_dir/." "$result_root/err/" 2>/dev/null || true

# --- 6. Write execution.json + per-case metadata (firstInputLine, stderrVars) ---
python3 - "$json_path" "$in_dir" "$err_dir" "$result_root" "$commit_hash" <<'PY'
import json, re, sys, os

json_path, in_dir, err_dir, result_root, commit_hash = sys.argv[1:6]
meta_dir = os.path.join(result_root, "meta")
os.makedirs(meta_dir, exist_ok=True)

# execution.json: the extension reads .commitHash from here.
with open(os.path.join(meta_dir, "execution.json"), "w", encoding="utf-8") as f:
    json.dump({"commitHash": commit_hash or None}, f, indent=2)

with open(json_path, encoding="utf-8") as f:
    result = json.load(f)

var_re = re.compile(r"\$([A-Za-z_][A-Za-z_0-9]*)\s*=\s*(-?\d+(?:\.\d+)?)")

def num(s):
    return int(s) if re.fullmatch(r"-?\d+", s) else float(s)

def first_input_line(seed):
    p = os.path.join(in_dir, f"{seed:04d}.txt")
    try:
        with open(p, encoding="utf-8") as f:
            return f.readline().rstrip("\r\n")
    except OSError:
        return ""

def stderr_vars(seed):
    p = os.path.join(err_dir, f"{seed:04d}.txt")
    vars = {}
    try:
        with open(p, encoding="utf-8", errors="replace") as f:
            for line in f:
                m = var_re.search(line)
                if m:
                    vars[m.group(1)] = num(m.group(2))  # last value wins
    except OSError:
        pass
    return vars

for case in result.get("cases", []):
    seed = case.get("seed")
    if seed is None:
        continue
    meta = {"firstInputLine": first_input_line(seed), "stderrVars": stderr_vars(seed)}
    with open(os.path.join(meta_dir, f"testcase_{seed:04d}.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)
PY

echo ""
echo "✅ Imported into pahcer-UI:"
echo "  contest : $contest_dir"
echo "  result  : $json_path"
echo "  archived: $result_root"
if [[ -n "$commit_hash" ]]; then
  echo "  commit  : ${commit_hash:0:7}  (copySource enabled for this run)"
else
  echo "  commit  : (none — copySource unavailable for this run)"
fi
echo "  cases   : $start_seed..$((end_seed - 1))"
echo ""
echo "Refresh the pahcer-UI view (Pahcer: 結果を更新) to see this run."
