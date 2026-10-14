#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/app_bundle.sh"
source "$ROOT_DIR/script/sparkle.sh"
source "$ROOT_DIR/script/version.sh"

APP_NAME="$CONTEXT_APP_NAME"
APP_BUNDLE_NAME="$CONTEXT_APP_BUNDLE_NAME"
APP_EXECUTABLE_NAME="$CONTEXT_EXECUTABLE_NAME"
BUNDLE_ID="$CONTEXT_BUNDLE_ID"
APP_VERSION="$(resolve_context_version "$ROOT_DIR")"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_BUNDLE_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_EXECUTABLE_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
CONTEXT_CODESIGN_IDENTITY="${CONTEXT_CODESIGN_IDENTITY:--}"

pkill -x "$APP_EXECUTABLE_NAME" >/dev/null 2>&1 || true

cd "$ROOT_DIR"
swift build
BUILD_BIN_DIR="$(swift build --show-bin-path)"
BUILD_BINARY="$BUILD_BIN_DIR/$APP_EXECUTABLE_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
context_copy_bundle_resources "$ROOT_DIR" "$APP_RESOURCES"
chmod +x "$APP_BINARY"
context_embed_sparkle "$ROOT_DIR" "$APP_BUNDLE" "$APP_BINARY"
context_embed_cli "$APP_BUNDLE" "$BUILD_BIN_DIR/$CONTEXT_CLI_PRODUCT_NAME"

context_write_info_plist "$INFO_PLIST" "$APP_VERSION"
context_sign_sparkle "$APP_BUNDLE"
context_sign_cli_and_app "$APP_BUNDLE"

open_app() {
  if [[ "$#" -gt 0 ]]; then
    /usr/bin/open -n "$APP_BUNDLE" --args "$@"
  else
    /usr/bin/open -n "$APP_BUNDLE"
  fi
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
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_EXECUTABLE_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_EXECUTABLE_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
