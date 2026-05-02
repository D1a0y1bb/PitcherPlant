#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PITCHERPLANT_WORKSPACE_ROOT="${PITCHERPLANT_WORKSPACE_ROOT:-$ROOT_DIR}"

exec "$ROOT_DIR/PitcherPlantApp/script/build_and_run.sh" "$@"
