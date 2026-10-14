#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/app_bundle.sh"
source "$ROOT_DIR/script/sparkle.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cc-app-bundle-test.XXXXXX")"
TMP_ROOT="$(cd "$TMP_ROOT" && pwd)"
trap 'rm -rf "$TMP_ROOT"' EXIT
FAKE_ROOT="$TMP_ROOT/project"
FAKE_BIN="$TMP_ROOT/fakebin"
mkdir -p "$FAKE_ROOT" "$FAKE_BIN"
export CC_TEST_SIGN_LOG="$TMP_ROOT/sign.log"
cat >"$FAKE_BIN/codesign" <<'CODESIGN'
#!/bin/bash
printf '%s\n' "$*" >>"$CC_TEST_SIGN_LOG"
CODESIGN
cat >"$FAKE_BIN/xcrun" <<'XCRUN'
#!/bin/bash
[[ "$1" == actool ]] || exit 1
while [[ "$#" -gt 0 ]]; do
  if [[ "$1" == --compile ]]; then
    printf 'test icon\n' >"$2/cc.icns"
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
test "$(cc_sparkle_framework_path "$FAKE_ROOT")" = "$SPARKLE_FRAMEWORK"
test "$(cc_sparkle_bin_dir "$FAKE_ROOT")" = "$SPARKLE_BIN_DIR"

APP_BUNDLE="$TMP_ROOT/$CC_APP_BUNDLE_NAME.app"
APP_MACOS="$APP_BUNDLE/Contents/MacOS"
APP_HELPERS="$APP_BUNDLE/Contents/Helpers"
APP_RESOURCES="$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
printf '#!/bin/sh\nexit 0\n' >"$APP_MACOS/cc"
cp "$APP_MACOS/cc" "$TMP_ROOT/cc-host"
printf '#!/bin/sh\nprintf "test CLI\\n"\n' >"$TMP_ROOT/$CC_CLI_PRODUCT_NAME"
chmod +x "$APP_MACOS/cc" "$TMP_ROOT/$CC_CLI_PRODUCT_NAME"
cc_embed_cli "$APP_BUNDLE" "$TMP_ROOT/$CC_CLI_PRODUCT_NAME"
cmp -s "$TMP_ROOT/cc-host" "$APP_MACOS/cc"
cc_copy_bundle_resources "$ROOT_DIR" "$APP_RESOURCES"
cc_embed_sparkle "$FAKE_ROOT" "$APP_BUNDLE" "$APP_MACOS/cc"
cc_write_info_plist "$APP_BUNDLE/Contents/Info.plist" 1.2.3
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
plutil -lint "$INFO_PLIST" >/dev/null
test "$(plutil -extract CFBundleShortVersionString raw "$INFO_PLIST")" = 1.2.3
test "$(basename "$APP_BUNDLE")" = cc.app
test "$(plutil -extract CFBundleName raw "$INFO_PLIST")" = cc:
test "$(plutil -extract CFBundleDisplayName raw "$INFO_PLIST")" = cc:
test "$(plutil -extract CFBundleExecutable raw "$INFO_PLIST")" = cc
test "$(plutil -extract CFBundleIconFile raw "$INFO_PLIST")" = cc.icns
test "$(plutil -extract CFBundleIconName raw "$INFO_PLIST")" = cc
test "$(plutil -extract CFBundleIdentifier raw "$INFO_PLIST")" = work.hayashigoto.cc
test "$(plutil -extract SUFeedURL raw "$INFO_PLIST")" = "$CC_SPARKLE_FEED_URL"
test "$(plutil -extract SUPublicEDKey raw "$INFO_PLIST")" = "$CC_SPARKLE_PUBLIC_ED_KEY"
test "$(plutil -extract SUEnableAutomaticChecks raw "$INFO_PLIST")" = true
test "$(plutil -extract CFBundleURLTypes.0.CFBundleURLSchemes.0 raw "$INFO_PLIST")" = cc
test ! -e "$APP_BUNDLE/Contents/PlugIns"
test -d "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
test -x "$APP_HELPERS/cc:"
cmp -s "$TMP_ROOT/$CC_CLI_PRODUCT_NAME" "$APP_HELPERS/cc:"
test "$("$APP_HELPERS/cc:")" = "test CLI"
test -x "$APP_RESOURCES/install_agent_tools.sh"
cmp -s "$ROOT_DIR/script/install_agent_tools.sh" "$APP_RESOURCES/install_agent_tools.sh"
cmp -s "$ROOT_DIR/skills/cc-handoff/SKILL.md" "$APP_RESOURCES/skills/cc-handoff/SKILL.md"

unset CC_CODESIGN_IDENTITY
cc_sign_cli_and_app "$APP_BUNDLE"
test "$(sed -n '1p' "$CC_TEST_SIGN_LOG")" = "--force --sign - $APP_HELPERS/cc:"
test "$(sed -n '2p' "$CC_TEST_SIGN_LOG")" = "--force --sign - $APP_BUNDLE"
test "$(sed -n '3p' "$CC_TEST_SIGN_LOG")" = "--verify --deep --strict $APP_BUNDLE"
: >"$CC_TEST_SIGN_LOG"
CC_CODESIGN_IDENTITY='Developer ID Application: cc Test'
cc_sign_cli_and_app "$APP_BUNDLE"
test "$(sed -n '1p' "$CC_TEST_SIGN_LOG")" = "--force --sign $CC_CODESIGN_IDENTITY --options runtime --timestamp $APP_HELPERS/cc:"
test "$(sed -n '2p' "$CC_TEST_SIGN_LOG")" = "--force --sign $CC_CODESIGN_IDENTITY --options runtime --timestamp $APP_BUNDLE"
if grep -q -- --entitlements "$CC_TEST_SIGN_LOG"; then
  echo "cc: CLI packaging must not request App Group entitlements" >&2
  exit 1
fi
APPCAST_PATH="$FAKE_ROOT/dist/appcast.xml"
APPCAST_ZIP="$TMP_ROOT/cc-macos.zip"
export CC_TEST_APPCAST_LOG="$TMP_ROOT/appcast.log"
mkdir -p "$FAKE_ROOT/dist"
printf 'test archive\n' >"$APPCAST_ZIP"
cat >"$SPARKLE_BIN_DIR/generate_appcast" <<'APPCAST'
#!/bin/bash
set -euo pipefail
cat >/dev/null
output=''
informational_versions=''
while [[ "$#" -gt 0 ]]; do
  if [[ "$1" == --informational-update-versions ]]; then
    informational_versions="$2"
    shift 2
    continue
  fi
  if [[ "$1" == -o ]]; then
    output="$2"
    break
  fi
  shift
done
[[ -n "$output" ]]
[[ "$informational_versions" == '<0.4.0' ]]
printf '%s\n' "$output" >>"$CC_TEST_APPCAST_LOG"
case "${CC_TEST_APPCAST_MODE:-success}" in
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
SPARKLE_ED_PRIVATE_KEY=test-dummy-key cc_write_appcast \
  "$FAKE_ROOT" "$APPCAST_ZIP" 'https://example.invalid/releases/v0.3.0/'
grep -q '<title>Universal</title>' "$APPCAST_PATH"
if grep -q hardwareRequirements "$APPCAST_PATH"; then
  echo 'Appcast retained stale CPU requirements' >&2
  exit 1
fi
test "$(wc -l <"$CC_TEST_APPCAST_LOG")" -eq 1

# Missing keys must remove a stale feed without invoking the generator.
write_stale_appcast
SPARKLE_ED_PRIVATE_KEY= cc_write_appcast \
  "$FAKE_ROOT" "$APPCAST_ZIP" 'https://example.invalid/releases/v0.3.0/' 2>/dev/null
test ! -e "$APPCAST_PATH"
test "$(wc -l <"$CC_TEST_APPCAST_LOG")" -eq 1

# Failed generation, including partial output, must not leave a publishable feed.
write_stale_appcast
if SPARKLE_ED_PRIVATE_KEY=test-dummy-key CC_TEST_APPCAST_MODE=fail \
    cc_write_appcast "$FAKE_ROOT" "$APPCAST_ZIP" \
    'https://example.invalid/releases/v0.3.0/'; then
  echo 'Appcast generation failure was accepted' >&2
  exit 1
fi
test ! -e "$APPCAST_PATH"

# An exit-zero generator that writes no feed is also a failed generation.
write_stale_appcast
if SPARKLE_ED_PRIVATE_KEY=test-dummy-key CC_TEST_APPCAST_MODE=missing \
    cc_write_appcast "$FAKE_ROOT" "$APPCAST_ZIP" \
    'https://example.invalid/releases/v0.3.0/' 2>/dev/null; then
  echo 'Missing appcast output was accepted' >&2
  exit 1
fi
test ! -e "$APPCAST_PATH"
test "$(wc -l <"$CC_TEST_APPCAST_LOG")" -eq 3

# Exercise the build/run script with isolated process and build tools.
mkdir -p "$FAKE_ROOT/script" "$FAKE_ROOT/Assets" "$FAKE_ROOT/skills" "$TMP_ROOT/build-bin"
for script in app_bundle.sh sparkle.sh version.sh build_and_run.sh install_agent_tools.sh; do
  cp "$ROOT_DIR/script/$script" "$FAKE_ROOT/script/$script"
done
cp "$ROOT_DIR/Assets/MenuBarTemplate.svg" "$FAKE_ROOT/Assets/MenuBarTemplate.svg"
ditto "$ROOT_DIR/skills/cc-handoff" "$FAKE_ROOT/skills/cc-handoff"
cp "$APP_MACOS/cc" "$TMP_ROOT/build-bin/cc"
cp "$APP_HELPERS/cc:" "$TMP_ROOT/build-bin/cc-cli"
ditto "$APP_BUNDLE" "$FAKE_ROOT/dist/cc.app"
INSTALLED_APP="$TMP_ROOT/Existing Applications/cc.app"
ditto "$APP_BUNDLE" "$INSTALLED_APP"
export CC_TEST_BUILD_BIN="$TMP_ROOT/build-bin"
export CC_TEST_PS_LIST="$TMP_ROOT/process-list"
export CC_TEST_PS_AFTER_OPEN="$TMP_ROOT/process-list-after-open"
export CC_TEST_KILL_LOG="$TMP_ROOT/killed-pids"
cat >"$FAKE_BIN/swift" <<'SWIFT'
#!/bin/bash
[[ "$1" == build ]] || exit 1
if [[ "${2:-}" == --show-bin-path ]]; then
  printf '%s\n' "$CC_TEST_BUILD_BIN"
fi
SWIFT
cat >"$FAKE_BIN/ps" <<'PS'
#!/bin/bash
[[ "$*" == '-axww -o pid=,comm=' ]] || exit 1
cat "$CC_TEST_PS_LIST"
PS
cat >"$TMP_ROOT/process-test-env.sh" <<'ENV'
kill() { printf '%s\n' "$*" >>"$CC_TEST_KILL_LOG"; }
pkill() { printf 'unscoped pkill\n' >>"$CC_TEST_KILL_LOG"; return 1; }
pgrep() { printf 'unscoped pgrep\n' >>"$CC_TEST_KILL_LOG"; return 0; }
function /usr/bin/open() { cat "$CC_TEST_PS_AFTER_OPEN" >"$CC_TEST_PS_LIST"; }
ENV
chmod +x "$FAKE_BIN/swift" "$FAKE_BIN/ps"
BUILD_APP_EXECUTABLE="$FAKE_ROOT/dist/cc.app/Contents/MacOS/cc"

write_running_processes() {
  printf ' 201 %s\n 202 %s\n 203 /usr/bin/cc\n 204 %s-worker\n 205 %s\n invalid %s\n' \
    "$BUILD_APP_EXECUTABLE" "$INSTALLED_APP/Contents/MacOS/cc" \
    "$BUILD_APP_EXECUTABLE" "$TMP_ROOT/Other.app/Contents/MacOS/cc" \
    "$BUILD_APP_EXECUTABLE" >"$CC_TEST_PS_LIST"
  : >"$CC_TEST_KILL_LOG"
}

run_build_verify() {
  BASH_ENV="$TMP_ROOT/process-test-env.sh" CC_INSTALL_APP="$INSTALLED_APP" \
    CC_CODESIGN_IDENTITY=- CC_VERSION=1.2.3 \
    "$FAKE_ROOT/script/build_and_run.sh" --verify >"$TMP_ROOT/build-run.log" 2>&1
}

# Only actual app paths stop; the started build's exact path satisfies verify.
write_running_processes
printf ' 301 %s\n 302 /usr/bin/cc\n' "$BUILD_APP_EXECUTABLE" >"$CC_TEST_PS_AFTER_OPEN"
run_build_verify || { cat "$TMP_ROOT/build-run.log" >&2; exit 1; }
test "$(cat "$CC_TEST_KILL_LOG")" = $'201\n202'

# A compiler or a different cc app cannot satisfy the launch verification.
write_running_processes
printf ' 302 /usr/bin/cc\n 303 %s\n' "$TMP_ROOT/Other.app/Contents/MacOS/cc" >"$CC_TEST_PS_AFTER_OPEN"
if run_build_verify; then
  echo 'An unrelated cc process satisfied build launch verification' >&2
  exit 1
fi
test "$(cat "$CC_TEST_KILL_LOG")" = $'201\n202'

# A same-named installed app with another bundle ID must remain running.
plutil -replace CFBundleIdentifier -string example.unrelated.app "$INSTALLED_APP/Contents/Info.plist"
write_running_processes
printf ' 301 %s\n' "$BUILD_APP_EXECUTABLE" >"$CC_TEST_PS_AFTER_OPEN"
run_build_verify || { cat "$TMP_ROOT/build-run.log" >&2; exit 1; }
test "$(cat "$CC_TEST_KILL_LOG")" = 201
printf 'App bundle resources, signing order, and appcast regression checks passed.\n'
