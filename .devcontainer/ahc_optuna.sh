#!/bin/bash

set -euo pipefail

if [[ -z "${WORKSPACE_FOLDER:-}" ]]; then
  echo "Error: WORKSPACE_FOLDER is not set" >&2
  exit 1
fi

runner="$WORKSPACE_FOLDER/scripts/ahc_optuna.py"
python_bin="/opt/ahc-optuna/bin/python3"

if [[ ! -x "$python_bin" ]]; then
  echo "Error: Optuna environment is missing. Rebuild the Dev Container." >&2
  exit 1
fi

if [[ ! -f "$runner" ]]; then
  echo "Error: runner not found: $runner" >&2
  exit 1
fi

exec "$python_bin" "$runner" "$@"
