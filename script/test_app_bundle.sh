#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/app_bundle.sh"
source "$ROOT_DIR/script/sparkle.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/context-app-bundle-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT
FAKE_ROOT="$TMP_ROOT/project"
FAKE_BIN="$TMP_ROOT/fakebin"
mkdir -p "$FAKE_ROOT" "$FAKE_BIN"
export CONTEXT_TEST_SIGN_LOG="$TMP_ROOT/sign.log"
cat >"$FAKE_BIN/codesign" <<'CODESIGN'
#!/bin/bash
printf '%s\n' "$*" >>"$CONTEXT_TEST_SIGN_LOG"
CODESIGN
cat >"$FAKE_BIN/xcrun" <<'XCRUN'
#!/bin/bash
[[ "$1" == actool ]] || exit 1
while [[ "$#" -gt 0 ]]; do
  if [[ "$1" == --compile ]]; then
    printf 'test icon\n' >"$2/Context.icns"
    exit 0
  fi
  shift
done
exit 1
XCRUN
cat >"$FAKE_BIN/otool" <<'OTOOL'
#!/bin/bash
printf '@executable_path/../Frameworks\n'
OTOOL
chmod +x "$FAKE_BIN"/*
PATH="$FAKE_BIN:$PATH"

SPARKLE_FRAMEWORK="$FAKE_ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
SPARKLE_BIN_DIR="$FAKE_ROOT/.build/artifacts/sparkle/Sparkle/bin"
mkdir -p "$SPARKLE_FRAMEWORK/Updater.app" "$SPARKLE_BIN_DIR"
printf '#!/bin/sh\nexit 0\n' >"$SPARKLE_FRAMEWORK/Sparkle"
printf '#!/bin/sh\nexit 0\n' >"$SPARKLE_BIN_DIR/generate_appcast"
chmod +x "$SPARKLE_FRAMEWORK/Sparkle" "$SPARKLE_BIN_DIR/generate_appcast"
test "$(context_sparkle_framework_path "$FAKE_ROOT")" = "$SPARKLE_FRAMEWORK"
test "$(context_sparkle_bin_dir "$FAKE_ROOT")" = "$SPARKLE_BIN_DIR"

APP_BUNDLE="$TMP_ROOT/$CONTEXT_APP_BUNDLE_NAME.app"
APP_MACOS="$APP_BUNDLE/Contents/MacOS"
APP_HELPERS="$APP_BUNDLE/Contents/Helpers"
APP_RESOURCES="$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
printf '#!/bin/sh\nexit 0\n' >"$APP_MACOS/Context"
cp "$APP_MACOS/Context" "$TMP_ROOT/Context-host"
printf '#!/bin/sh\nprintf "test CLI\\n"\n' >"$TMP_ROOT/$CONTEXT_CLI_PRODUCT_NAME"
chmod +x "$APP_MACOS/Context" "$TMP_ROOT/$CONTEXT_CLI_PRODUCT_NAME"
context_embed_cli "$APP_BUNDLE" "$TMP_ROOT/$CONTEXT_CLI_PRODUCT_NAME"
cmp -s "$TMP_ROOT/Context-host" "$APP_MACOS/Context"
context_copy_bundle_resources "$ROOT_DIR" "$APP_RESOURCES"
context_embed_sparkle "$FAKE_ROOT" "$APP_BUNDLE" "$APP_MACOS/Context"
context_write_info_plist "$APP_BUNDLE/Contents/Info.plist" 1.2.3
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
plutil -lint "$INFO_PLIST" >/dev/null
test "$(plutil -extract CFBundleShortVersionString raw "$INFO_PLIST")" = 1.2.3
test "$(basename "$APP_BUNDLE")" = cc.app
test "$(plutil -extract CFBundleName raw "$INFO_PLIST")" = cc:
test "$(plutil -extract CFBundleDisplayName raw "$INFO_PLIST")" = cc:
test "$(plutil -extract CFBundleExecutable raw "$INFO_PLIST")" = Context
test "$(plutil -extract CFBundleIdentifier raw "$INFO_PLIST")" = work.hayashigoto.Context
test "$(plutil -extract SUFeedURL raw "$INFO_PLIST")" = "$CONTEXT_SPARKLE_FEED_URL"
test "$(plutil -extract SUPublicEDKey raw "$INFO_PLIST")" = "$CONTEXT_SPARKLE_PUBLIC_ED_KEY"
test "$(plutil -extract SUEnableAutomaticChecks raw "$INFO_PLIST")" = true
test "$(plutil -extract CFBundleURLTypes.0.CFBundleURLSchemes.0 raw "$INFO_PLIST")" = context
if plutil -extract ContextWidgetAppGroup raw "$INFO_PLIST" >/dev/null 2>&1; then
  echo "Context must not include widget App Group metadata" >&2
  exit 1
fi
test ! -e "$APP_BUNDLE/Contents/PlugIns"
test -d "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
test -x "$APP_HELPERS/context"
cmp -s "$TMP_ROOT/$CONTEXT_CLI_PRODUCT_NAME" "$APP_HELPERS/context"
test -x "$APP_RESOURCES/install_agent_tools.sh"
cmp -s "$ROOT_DIR/script/install_agent_tools.sh" "$APP_RESOURCES/install_agent_tools.sh"
cmp -s "$ROOT_DIR/skills/context-handoff/SKILL.md" "$APP_RESOURCES/skills/context-handoff/SKILL.md"

unset CONTEXT_CODESIGN_IDENTITY
context_sign_cli_and_app "$APP_BUNDLE"
test "$(sed -n '1p' "$CONTEXT_TEST_SIGN_LOG")" = "--force --sign - $APP_HELPERS/context"
test "$(sed -n '2p' "$CONTEXT_TEST_SIGN_LOG")" = "--force --sign - $APP_BUNDLE"
test "$(sed -n '3p' "$CONTEXT_TEST_SIGN_LOG")" = "--verify --deep --strict $APP_BUNDLE"
: >"$CONTEXT_TEST_SIGN_LOG"
CONTEXT_CODESIGN_IDENTITY='Developer ID Application: Context Test'
context_sign_cli_and_app "$APP_BUNDLE"
test "$(sed -n '1p' "$CONTEXT_TEST_SIGN_LOG")" = "--force --sign $CONTEXT_CODESIGN_IDENTITY --options runtime --timestamp $APP_HELPERS/context"
test "$(sed -n '2p' "$CONTEXT_TEST_SIGN_LOG")" = "--force --sign $CONTEXT_CODESIGN_IDENTITY --options runtime --timestamp $APP_BUNDLE"
if grep -q -- --entitlements "$CONTEXT_TEST_SIGN_LOG"; then
  echo "Context CLI packaging must not request App Group entitlements" >&2
  exit 1
fi
APPCAST_PATH="$FAKE_ROOT/dist/appcast.xml"
APPCAST_ZIP="$TMP_ROOT/context-macos.zip"
export CONTEXT_TEST_APPCAST_LOG="$TMP_ROOT/appcast.log"
mkdir -p "$FAKE_ROOT/dist"
printf 'test archive\n' >"$APPCAST_ZIP"
cat >"$SPARKLE_BIN_DIR/generate_appcast" <<'APPCAST'
#!/bin/bash
set -euo pipefail
cat >/dev/null
output=''
while [[ "$#" -gt 0 ]]; do
  if [[ "$1" == -o ]]; then
    output="$2"
    break
  fi
  shift
done
[[ -n "$output" ]]
printf '%s\n' "$output" >>"$CONTEXT_TEST_APPCAST_LOG"
case "${CONTEXT_TEST_APPCAST_MODE:-success}" in
  fail)
    printf 'partial feed\n' >"$output"
    exit 1
    ;;
  missing)
    exit 0
    ;;
esac
# Match Sparkle's behavior: an existing feed retains its old CPU requirements.
[[ ! -f "$output" ]] || exit 0
printf '<rss><title>Universal</title></rss>\n' >"$output"
APPCAST
chmod +x "$SPARKLE_BIN_DIR/generate_appcast"

write_stale_appcast() {
  printf '<rss><hardwareRequirements>arm64</hardwareRequirements></rss>\n' >"$APPCAST_PATH"
}

# A rebuild of the same version must replace, rather than reuse, the old feed.
write_stale_appcast
SPARKLE_ED_PRIVATE_KEY=test-dummy-key context_write_appcast \
  "$FAKE_ROOT" "$APPCAST_ZIP" 'https://example.invalid/releases/v0.3.0/'
grep -q '<title>Universal</title>' "$APPCAST_PATH"
if grep -q hardwareRequirements "$APPCAST_PATH"; then
  echo 'Appcast retained stale CPU requirements' >&2
  exit 1
fi
test "$(wc -l <"$CONTEXT_TEST_APPCAST_LOG")" -eq 1

# Missing keys must remove a stale feed without invoking the generator.
write_stale_appcast
SPARKLE_ED_PRIVATE_KEY= context_write_appcast \
  "$FAKE_ROOT" "$APPCAST_ZIP" 'https://example.invalid/releases/v0.3.0/' 2>/dev/null
test ! -e "$APPCAST_PATH"
test "$(wc -l <"$CONTEXT_TEST_APPCAST_LOG")" -eq 1

# Failed generation, including partial output, must not leave a publishable feed.
write_stale_appcast
if SPARKLE_ED_PRIVATE_KEY=test-dummy-key CONTEXT_TEST_APPCAST_MODE=fail \
    context_write_appcast "$FAKE_ROOT" "$APPCAST_ZIP" \
    'https://example.invalid/releases/v0.3.0/'; then
  echo 'Appcast generation failure was accepted' >&2
  exit 1
fi
test ! -e "$APPCAST_PATH"

# An exit-zero generator that writes no feed is also a failed generation.
write_stale_appcast
if SPARKLE_ED_PRIVATE_KEY=test-dummy-key CONTEXT_TEST_APPCAST_MODE=missing \
    context_write_appcast "$FAKE_ROOT" "$APPCAST_ZIP" \
    'https://example.invalid/releases/v0.3.0/' 2>/dev/null; then
  echo 'Missing appcast output was accepted' >&2
  exit 1
fi
test ! -e "$APPCAST_PATH"
test "$(wc -l <"$CONTEXT_TEST_APPCAST_LOG")" -eq 3
printf 'App bundle resources, signing order, and appcast regression checks passed.\n'
