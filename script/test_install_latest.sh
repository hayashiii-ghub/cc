#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/app_bundle.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/context-install-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

make_app() {
  local app="$1"
  local version="$2"
  local bundle_id="${3:-work.hayashigoto.Context}"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources"
  context_write_info_plist "$app/Contents/Info.plist" "$version"
  plutil -replace CFBundleIdentifier -string "$bundle_id" "$app/Contents/Info.plist"
  printf '#!/bin/sh\nexit 0\n' >"$app/Contents/MacOS/Context"
  printf '#!/bin/sh\nexit 0\n' >"$app/Contents/Helpers/context"
  printf '%s\n' "$version" >"$app/Contents/Resources/existing-marker"
  chmod +x "$app/Contents/MacOS/Context" "$app/Contents/Helpers/context"
  codesign --force --sign - "$app/Contents/Helpers/context"
  codesign --force --sign - "$app"
}

run_installer() {
  local install_dir="$1"
  local install_home="$2"
  local archive="$3"
  shift 3
  CONTEXT_INSTALL_DIR="$install_dir" CONTEXT_INSTALL_HOME="$install_home" \
    CONTEXT_ZIP_PATH="$archive" CONTEXT_SKIP_STOP=1 CONTEXT_SKIP_OPEN=1 \
    "$@" >"$TEST_ROOT/install.log" 2>"$TEST_ROOT/install-error.log"
}

expect_rejection() {
  if run_installer "$@" "$ROOT_DIR/script/install_latest.sh"; then
    echo "Expected installer to reject this update" >&2
    exit 1
  fi
}

INSTALL_DIR="$TEST_ROOT/Applications"
INSTALL_HOME="$TEST_ROOT/home"
mkdir -p "$INSTALL_HOME/.local/bin"
make_app "$INSTALL_DIR/Context.app" 1.0.0
LEGACY_CLI="$INSTALL_DIR/Context.app/Contents/Helpers/context"
ln -s "$LEGACY_CLI" "$INSTALL_HOME/.local/bin/context"
mkdir -p "$INSTALL_HOME/.codex/skills/context-handoff"
printf 'my edited skill\n' >"$INSTALL_HOME/.codex/skills/context-handoff/SKILL.md"

INVALID_APP="$TEST_ROOT/invalid/cc.app"
mkdir -p "$INVALID_APP/Contents"
printf 'invalid\n' >"$INVALID_APP/Contents/payload"
ditto -c -k --keepParent "$INVALID_APP" "$TEST_ROOT/invalid.zip"
expect_rejection "$INSTALL_DIR" "$INSTALL_HOME" "$TEST_ROOT/invalid.zip"
test "$(cat "$INSTALL_DIR/Context.app/Contents/Resources/existing-marker")" = 1.0.0
test "$(readlink "$INSTALL_HOME/.local/bin/context")" = "$LEGACY_CLI"
test ! -e "$INSTALL_DIR/cc.app"

VALID_APP="$TEST_ROOT/valid/cc.app"
make_app "$VALID_APP" 9.9.9
ditto -c -k --keepParent "$VALID_APP" "$TEST_ROOT/valid.zip"

# Reject staged validation, installed validation, and rename failures without
# losing either the old app or its existing CLI link.
FAKE_BIN="$TEST_ROOT/fakebin"
mkdir "$FAKE_BIN"
cat >"$FAKE_BIN/codesign" <<'CODESIGN'
#!/bin/bash
app="${@: -1}"
if [[ "${CONTEXT_TEST_FAIL_STAGE:-0}" == 1 && "$app" == */.cc.app.new.* ]]; then
  exit 1
fi
if [[ -n "${CONTEXT_TEST_FAIL_VALIDATION:-}" && "$app" == "$CONTEXT_TEST_FAIL_VALIDATION" ]]; then
  exit 1
fi
exec /usr/bin/codesign "$@"
CODESIGN
cat >"$FAKE_BIN/mv" <<'MV'
#!/bin/bash
if [[ "$#" == 2 && "$2" == "$CONTEXT_TEST_FAIL_DEST" && ! -e "$CONTEXT_TEST_FAIL_ONCE" ]]; then
  : >"$CONTEXT_TEST_FAIL_ONCE"
  exit 1
fi
exec /bin/mv "$@"
MV
chmod +x "$FAKE_BIN"/*
ORIGINAL_TEST_PATH="$PATH"
export CONTEXT_TEST_FAIL_STAGE=1
export CONTEXT_TEST_FAIL_DEST="$INSTALL_DIR/cc.app"
export CONTEXT_TEST_FAIL_ONCE="$TEST_ROOT/failed-once"
PATH="$FAKE_BIN:$PATH"
expect_rejection "$INSTALL_DIR" "$INSTALL_HOME" "$TEST_ROOT/valid.zip"
export CONTEXT_TEST_FAIL_STAGE=0
expect_rejection "$INSTALL_DIR" "$INSTALL_HOME" "$TEST_ROOT/valid.zip"
export CONTEXT_TEST_FAIL_VALIDATION="$INSTALL_DIR/cc.app"
expect_rejection "$INSTALL_DIR" "$INSTALL_HOME" "$TEST_ROOT/valid.zip"
unset CONTEXT_TEST_FAIL_VALIDATION
export CONTEXT_TEST_FAIL_DEST="$INSTALL_HOME/.local/bin/context"
rm "$CONTEXT_TEST_FAIL_ONCE"
expect_rejection "$INSTALL_DIR" "$INSTALL_HOME" "$TEST_ROOT/valid.zip"
PATH="$ORIGINAL_TEST_PATH"
test "$(cat "$INSTALL_DIR/Context.app/Contents/Resources/existing-marker")" = 1.0.0
test "$(readlink "$INSTALL_HOME/.local/bin/context")" = "$LEGACY_CLI"
test ! -e "$INSTALL_DIR/cc.app"
test -z "$(find "$INSTALL_DIR" -maxdepth 1 -name '.*.app.*' -print -quit)"
test -z "$(find "$INSTALL_HOME/.local/bin" -maxdepth 1 -name '.context-link.*' -print -quit)"

run_installer "$INSTALL_DIR" "$INSTALL_HOME" "$TEST_ROOT/valid.zip" "$ROOT_DIR/script/install_latest.sh"
INSTALLED_APP="$INSTALL_DIR/cc.app"
test "$(plutil -extract CFBundleShortVersionString raw "$INSTALLED_APP/Contents/Info.plist")" = 9.9.9
test "$(plutil -extract CFBundleDisplayName raw "$INSTALLED_APP/Contents/Info.plist")" = cc:
test "$(readlink "$INSTALL_HOME/.local/bin/context")" = "$INSTALLED_APP/Contents/Helpers/context"
test ! -e "$INSTALL_DIR/Context.app"
LEGACY_BACKUP="$(find "$INSTALL_DIR" -maxdepth 1 -name '.Context.app.backup.*' -print)"
test -n "$LEGACY_BACKUP"
test "$(cat "$LEGACY_BACKUP/Contents/Resources/existing-marker")" = 1.0.0
test "$(cat "$INSTALL_HOME/.codex/skills/context-handoff/SKILL.md")" = 'my edited skill'
codesign --verify --deep --strict "$INSTALLED_APP"
CLI_INODE="$(stat -f '%i' "$INSTALL_HOME/.local/bin/context")"
run_installer "$INSTALL_DIR" "$INSTALL_HOME" "$TEST_ROOT/valid.zip" "$ROOT_DIR/script/install_latest.sh"
test "$(stat -f '%i' "$INSTALL_HOME/.local/bin/context")" = "$CLI_INODE"
test -z "$(find "$INSTALL_DIR" -maxdepth 1 -name '.cc.app.*' -print -quit)"

# Legacy archives remain accepted by the standalone/piped installer.
LEGACY_ARCHIVE_APP="$TEST_ROOT/legacy-archive/Context.app"
make_app "$LEGACY_ARCHIVE_APP" 8.8.8
ditto -c -k --keepParent "$LEGACY_ARCHIVE_APP" "$TEST_ROOT/legacy.zip"
PIPED_DIR="$TEST_ROOT/PipedApplications"
PIPED_HOME="$TEST_ROOT/piped-home"
mkdir "$PIPED_HOME"
run_installer "$PIPED_DIR" "$PIPED_HOME" "$TEST_ROOT/legacy.zip" bash <"$ROOT_DIR/script/install_latest.sh"
test -x "$PIPED_DIR/cc.app/Contents/MacOS/Context"
test "$(plutil -extract CFBundleShortVersionString raw "$PIPED_DIR/cc.app/Contents/Info.plist")" = 8.8.8
codesign --verify --deep --strict "$PIPED_DIR/cc.app"

# Unknown links and regular commands must survive app migration unchanged.
for kind in link file; do
  protected_dir="$TEST_ROOT/protected-$kind-apps"
  protected_home="$TEST_ROOT/protected-$kind-home"
  mkdir -p "$protected_home/.local/bin"
  make_app "$protected_dir/Context.app" 1.0.0
  if [[ "$kind" == link ]]; then
    ln -s /usr/bin/true "$protected_home/.local/bin/context"
  else
    printf 'my command\n' >"$protected_home/.local/bin/context"
  fi
  run_installer "$protected_dir" "$protected_home" "$TEST_ROOT/valid.zip" "$ROOT_DIR/script/install_latest.sh"
  if [[ "$kind" == link ]]; then
    test "$(readlink "$protected_home/.local/bin/context")" = /usr/bin/true
  else
    test "$(cat "$protected_home/.local/bin/context")" = 'my command'
  fi
done

FOREIGN_DIR="$TEST_ROOT/foreign-apps"
FOREIGN_HOME="$TEST_ROOT/foreign-home"
mkdir "$FOREIGN_HOME"
make_app "$FOREIGN_DIR/cc.app" 1.0.0 example.unrelated.app
expect_rejection "$FOREIGN_DIR" "$FOREIGN_HOME" "$TEST_ROOT/valid.zip"
test "$(plutil -extract CFBundleIdentifier raw "$FOREIGN_DIR/cc.app/Contents/Info.plist")" = example.unrelated.app
printf 'App installer migration and rollback checks passed.\n'
