#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="PitcherPlant"
BUNDLE_ID="com.pitcherplant.desktop"
SCHEME="PitcherPlantApp"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT_DIR/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/PitcherPlantApp.xcodeproj"
DERIVED_DATA_PATH="$ROOT_DIR/.build/xcode"
APP_BUNDLE="$DERIVED_DATA_PATH/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

export PITCHERPLANT_WORKSPACE_ROOT="${PITCHERPLANT_WORKSPACE_ROOT:-$REPO_ROOT}"

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  ACTIVE_DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"
  if [[ "$ACTIVE_DEVELOPER_DIR" == "/Library/Developer/CommandLineTools" ]]; then
    if [[ -d "/Applications/Xcode-beta.app/Contents/Developer" ]]; then
      export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
    elif [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
      export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    else
      echo "No full Xcode installation found. Install Xcode or set DEVELOPER_DIR explicitly." >&2
      exit 1
    fi
  fi
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
