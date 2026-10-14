#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/app_bundle.sh"
source "$ROOT_DIR/script/sparkle.sh"
source "$ROOT_DIR/script/version.sh"

APP_BUNDLE_NAME="$CC_APP_BUNDLE_NAME"
APP_EXECUTABLE_NAME="$CC_EXECUTABLE_NAME"
BUNDLE_ID="$CC_BUNDLE_ID"
APP_VERSION="$(resolve_cc_version "$ROOT_DIR")"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_BUNDLE_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_EXECUTABLE_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
CC_CODESIGN_IDENTITY="${CC_CODESIGN_IDENTITY:--}"

cc_app_pids() {
  local executable="$1"
  local pid command
  while IFS=' ' read -r pid command; do
    if [[ "$pid" =~ ^[0-9]+$ && "$command" == "$executable" ]]; then
      printf '%s\n' "$pid"
    fi
  done < <(ps -axww -o pid=,comm=)
}

stop_cc_app() {
  local pid
  while read -r pid; do
    kill "$pid" >/dev/null 2>&1 || true
  done < <(cc_app_pids "$1")
}

for existing_app in "$APP_BUNDLE" /Applications/cc.app "$HOME/Applications/cc.app" "${CC_INSTALL_APP:-}"; do
  [[ -n "$existing_app" && -f "$existing_app/Contents/Info.plist" ]] || continue
  [[ "$(plutil -extract CFBundleIdentifier raw "$existing_app/Contents/Info.plist" 2>/dev/null)" == "$BUNDLE_ID" \
      && "$(plutil -extract CFBundleExecutable raw "$existing_app/Contents/Info.plist" 2>/dev/null)" == "$APP_EXECUTABLE_NAME" ]] || continue
  stop_cc_app "$existing_app/Contents/MacOS/$APP_EXECUTABLE_NAME"
done

cd "$ROOT_DIR"
swift build
BUILD_BIN_DIR="$(swift build --show-bin-path)"
BUILD_BINARY="$BUILD_BIN_DIR/$APP_EXECUTABLE_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
cc_copy_bundle_resources "$ROOT_DIR" "$APP_RESOURCES"
chmod +x "$APP_BINARY"
cc_embed_sparkle "$ROOT_DIR" "$APP_BUNDLE" "$APP_BINARY"
cc_embed_cli "$APP_BUNDLE" "$BUILD_BIN_DIR/$CC_CLI_PRODUCT_NAME"

cc_write_info_plist "$INFO_PLIST" "$APP_VERSION"
cc_sign_sparkle "$APP_BUNDLE"
cc_sign_cli_and_app "$APP_BUNDLE"

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
    [[ -n "$(cc_app_pids "$APP_BINARY")" ]]
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
