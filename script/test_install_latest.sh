#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/app_bundle.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cc-install-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

make_app() {
  local app="$1"
  local version="$2"
  local bundle_id="${3:-work.hayashigoto.cc}"
  local helper="${4:-cc-shelf}"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources"
  cc_write_info_plist "$app/Contents/Info.plist" "$version"
  plutil -replace CFBundleIdentifier -string "$bundle_id" "$app/Contents/Info.plist"
  printf '#!/bin/sh\nexit 0\n' >"$app/Contents/MacOS/cc"
  printf '%s\n' "$version" >"$app/Contents/Resources/existing-marker"
  chmod +x "$app/Contents/MacOS/cc"
  if [[ "$helper" != none ]]; then
    printf '#!/bin/sh\nexit 0\n' >"$app/Contents/Helpers/$helper"
    chmod +x "$app/Contents/Helpers/$helper"
    codesign --force --sign - "$app/Contents/Helpers/$helper"
  fi
  codesign --force --sign - "$app"
}

run_installer() {
  local install_dir="$1"
  local install_home="$2"
  local archive="$3"
  shift 3
  CC_INSTALL_DIR="$install_dir" CC_INSTALL_HOME="$install_home" \
    CC_ZIP_PATH="$archive" CC_SKIP_STOP="${CC_TEST_SKIP_STOP:-1}" CC_SKIP_OPEN=1 \
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
mkdir -p "$INSTALL_HOME/.local/bin" "$INSTALL_HOME/.codex/skills/cc-handoff"
make_app "$INSTALL_DIR/cc.app" 1.0.0
CLI_TARGET="$INSTALL_DIR/cc.app/Contents/Helpers/cc-shelf"
ln -s "$CLI_TARGET" "$INSTALL_HOME/.local/bin/cc-shelf"
CLI_INODE="$(stat -f '%i' "$INSTALL_HOME/.local/bin/cc-shelf")"
printf 'my edited skill\n' >"$INSTALL_HOME/.codex/skills/cc-handoff/SKILL.md"

INVALID_APP="$TEST_ROOT/invalid/cc.app"
mkdir -p "$INVALID_APP/Contents"
printf 'invalid\n' >"$INVALID_APP/Contents/payload"
ditto -c -k --keepParent "$INVALID_APP" "$TEST_ROOT/invalid.zip"
expect_rejection "$INSTALL_DIR" "$INSTALL_HOME" "$TEST_ROOT/invalid.zip"
test "$(cat "$INSTALL_DIR/cc.app/Contents/Resources/existing-marker")" = 1.0.0

VALID_APP="$TEST_ROOT/valid/cc.app"
make_app "$VALID_APP" 9.9.9
ditto -c -k --keepParent "$VALID_APP" "$TEST_ROOT/valid.zip"

FAKE_BIN="$TEST_ROOT/fakebin"
mkdir "$FAKE_BIN"
cat >"$FAKE_BIN/codesign" <<'CODESIGN'
#!/bin/bash
app="${@: -1}"
if [[ "${CC_TEST_FAIL_STAGE:-0}" == 1 && "$app" == */.cc.app.new.* ]]; then
  exit 1
fi
if [[ -n "${CC_TEST_FAIL_VALIDATION:-}" && "$app" == "$CC_TEST_FAIL_VALIDATION" ]]; then
  exit 1
fi
exec /usr/bin/codesign "$@"
CODESIGN
cat >"$FAKE_BIN/mv" <<'MV'
#!/bin/bash
if [[ "$#" == 2 && "$2" == "${CC_TEST_FAIL_DEST:-}" && ! -e "$CC_TEST_FAIL_ONCE" ]]; then
  if [[ "${CC_TEST_FAIL_AFTER_MOVE:-0}" == 1 ]]; then
    /bin/mv "$@" || exit "$?"
  fi
  : >"$CC_TEST_FAIL_ONCE"
  exit 1
fi
exec /bin/mv "$@"
MV
chmod +x "$FAKE_BIN"/*
ORIGINAL_TEST_PATH="$PATH"
export CC_TEST_FAIL_ONCE="$TEST_ROOT/failed-once"

# Every failure leaves the previous app, CLI inode, and edited skill intact.
for phase in staged installed move-before move-after; do
  export CC_TEST_FAIL_STAGE=0 CC_TEST_FAIL_VALIDATION="" CC_TEST_FAIL_DEST="" CC_TEST_FAIL_AFTER_MOVE=0
  case "$phase" in
    staged) export CC_TEST_FAIL_STAGE=1 ;;
    installed) export CC_TEST_FAIL_VALIDATION="$INSTALL_DIR/cc.app" ;;
    move-before) export CC_TEST_FAIL_DEST="$INSTALL_DIR/cc.app" ;;
    move-after) export CC_TEST_FAIL_DEST="$INSTALL_DIR/cc.app" CC_TEST_FAIL_AFTER_MOVE=1 ;;
  esac
  rm -f "$CC_TEST_FAIL_ONCE"
  PATH="$FAKE_BIN:$ORIGINAL_TEST_PATH"
  expect_rejection "$INSTALL_DIR" "$INSTALL_HOME" "$TEST_ROOT/valid.zip"
  PATH="$ORIGINAL_TEST_PATH"
  test "$(cat "$INSTALL_DIR/cc.app/Contents/Resources/existing-marker")" = 1.0.0
  test "$(readlink "$INSTALL_HOME/.local/bin/cc-shelf")" = "$CLI_TARGET"
  test "$(stat -f '%i' "$INSTALL_HOME/.local/bin/cc-shelf")" = "$CLI_INODE"
  test "$(cat "$INSTALL_HOME/.codex/skills/cc-handoff/SKILL.md")" = 'my edited skill'
  test -z "$(find "$INSTALL_DIR" -maxdepth 1 -name '.cc.app.*' -print -quit)"
  if [[ "$phase" == move-* ]]; then test -e "$CC_TEST_FAIL_ONCE"; fi
done
unset CC_TEST_FAIL_STAGE CC_TEST_FAIL_VALIDATION CC_TEST_FAIL_DEST CC_TEST_FAIL_AFTER_MOVE

run_installer "$INSTALL_DIR" "$INSTALL_HOME" "$TEST_ROOT/valid.zip" "$ROOT_DIR/script/install_latest.sh"
test "$(plutil -extract CFBundleShortVersionString raw "$INSTALL_DIR/cc.app/Contents/Info.plist")" = 9.9.9
test "$(plutil -extract CFBundleExecutable raw "$INSTALL_DIR/cc.app/Contents/Info.plist")" = cc
test "$(readlink "$INSTALL_HOME/.local/bin/cc-shelf")" = "$CLI_TARGET"
test "$(stat -f '%i' "$INSTALL_HOME/.local/bin/cc-shelf")" = "$CLI_INODE"
codesign --verify --deep --strict "$INSTALL_DIR/cc.app"
run_installer "$INSTALL_DIR" "$INSTALL_HOME" "$TEST_ROOT/valid.zip" "$ROOT_DIR/script/install_latest.sh"
test "$(stat -f '%i' "$INSTALL_HOME/.local/bin/cc-shelf")" = "$CLI_INODE"
test -z "$(find "$INSTALL_DIR" -maxdepth 1 -name '.cc.app.*' -print -quit)"

# Stop only the selected app, including an installation path containing spaces.
PROCESS_DIR="$TEST_ROOT/Process Applications"
PROCESS_HOME="$TEST_ROOT/process-home"
mkdir "$PROCESS_HOME"
make_app "$PROCESS_DIR/cc.app" 1.0.0
export CC_TEST_PS_LIST="$TEST_ROOT/process-list"
export CC_TEST_KILL_LOG="$TEST_ROOT/killed-pids"
cat >"$FAKE_BIN/ps" <<'PS'
#!/bin/bash
[[ "$*" == '-axww -o pid=,comm=' ]] || exit 1
cat "$CC_TEST_PS_LIST"
PS
cat >"$TEST_ROOT/process-test-env.sh" <<'ENV'
kill() { printf '%s\n' "$*" >>"$CC_TEST_KILL_LOG"; }
pkill() { printf 'unscoped pkill\n' >>"$CC_TEST_KILL_LOG"; return 1; }
ENV
chmod +x "$FAKE_BIN/ps"
printf ' 101 %s\n 102 /usr/bin/cc\n 103 %s-worker\n 104 %s\n invalid %s\n' \
  "$PROCESS_DIR/cc.app/Contents/MacOS/cc" \
  "$PROCESS_DIR/cc.app/Contents/MacOS/cc" \
  "$TEST_ROOT/Other.app/Contents/MacOS/cc" \
  "$PROCESS_DIR/cc.app/Contents/MacOS/cc" >"$CC_TEST_PS_LIST"
: >"$CC_TEST_KILL_LOG"
PATH="$FAKE_BIN:$ORIGINAL_TEST_PATH" BASH_ENV="$TEST_ROOT/process-test-env.sh" CC_TEST_SKIP_STOP=0 \
  run_installer "$PROCESS_DIR" "$PROCESS_HOME" "$TEST_ROOT/valid.zip" "$ROOT_DIR/script/install_latest.sh"
test "$(cat "$CC_TEST_KILL_LOG")" = 101
test "$(cat "$PROCESS_DIR/cc.app/Contents/Resources/existing-marker")" = 9.9.9

# Standalone/piped installation does not opt a user into CLI or skill setup.
PIPED_DIR="$TEST_ROOT/PipedApplications"
PIPED_HOME="$TEST_ROOT/piped-home"
mkdir "$PIPED_HOME"
run_installer "$PIPED_DIR" "$PIPED_HOME" "$TEST_ROOT/valid.zip" bash <"$ROOT_DIR/script/install_latest.sh"
codesign --verify --deep --strict "$PIPED_DIR/cc.app"
test ! -e "$PIPED_HOME/.local"
test ! -e "$PIPED_HOME/.codex"

MISSING_HELPER_APP="$TEST_ROOT/missing-helper/cc.app"
make_app "$MISSING_HELPER_APP" 9.9.9 work.hayashigoto.cc none
ditto -c -k --keepParent "$MISSING_HELPER_APP" "$TEST_ROOT/missing-helper.zip"
expect_rejection "$INSTALL_DIR" "$INSTALL_HOME" "$TEST_ROOT/missing-helper.zip"
test "$(cat "$INSTALL_DIR/cc.app/Contents/Resources/existing-marker")" = 9.9.9
test "$(stat -f '%i' "$INSTALL_HOME/.local/bin/cc-shelf")" = "$CLI_INODE"

# App-only updates preserve unrelated commands, even dangling links.
for kind in file link; do
  custom_dir="$TEST_ROOT/custom-$kind-apps"
  custom_home="$TEST_ROOT/custom-$kind-home"
  mkdir -p "$custom_home/.local/bin"
  make_app "$custom_dir/cc.app" 1.0.0
  if [[ "$kind" == link ]]; then
    ln -s "$TEST_ROOT/missing-custom-command" "$custom_home/.local/bin/cc-shelf"
  else
    printf 'my command\n' >"$custom_home/.local/bin/cc-shelf"
  fi
  run_installer "$custom_dir" "$custom_home" "$TEST_ROOT/valid.zip" "$ROOT_DIR/script/install_latest.sh"
  if [[ "$kind" == link ]]; then
    test "$(readlink "$custom_home/.local/bin/cc-shelf")" = "$TEST_ROOT/missing-custom-command"
  else
    test "$(cat "$custom_home/.local/bin/cc-shelf")" = 'my command'
  fi
  test "$(cat "$custom_dir/cc.app/Contents/Resources/existing-marker")" = 9.9.9
done

# App-only updates keep old agent-tool state until its explicit reinstall.
PREVIOUS_DIR="$TEST_ROOT/Previous Applications"
PREVIOUS_HOME="$TEST_ROOT/previous-home"
mkdir -p "$PREVIOUS_HOME/.local/bin" "$PREVIOUS_HOME/.codex/skills/cc-handoff"
make_app "$PREVIOUS_DIR/cc.app" 1.0.0 work.hayashigoto.cc cc:
PREVIOUS_TARGET="$PREVIOUS_DIR/cc.app/Contents/Helpers/cc:"
ln -s "$PREVIOUS_TARGET" "$PREVIOUS_HOME/.local/bin/cc:"
printf 'previous handoff instructions\n' >"$PREVIOUS_HOME/.codex/skills/cc-handoff/SKILL.md"
expect_rejection "$PREVIOUS_DIR" "$PREVIOUS_HOME" "$TEST_ROOT/missing-helper.zip"
test "$(cat "$PREVIOUS_DIR/cc.app/Contents/Resources/existing-marker")" = 1.0.0
test "$(readlink "$PREVIOUS_HOME/.local/bin/cc:")" = "$PREVIOUS_TARGET"
run_installer "$PREVIOUS_DIR" "$PREVIOUS_HOME" "$TEST_ROOT/valid.zip" "$ROOT_DIR/script/install_latest.sh"
test "$(cat "$PREVIOUS_DIR/cc.app/Contents/Resources/existing-marker")" = 9.9.9
test -x "$PREVIOUS_DIR/cc.app/Contents/Helpers/cc-shelf"
test "$(readlink "$PREVIOUS_HOME/.local/bin/cc:")" = "$PREVIOUS_TARGET"
test ! -L "$PREVIOUS_HOME/.local/bin/cc-shelf"
test "$(cat "$PREVIOUS_HOME/.codex/skills/cc-handoff/SKILL.md")" = 'previous handoff instructions'
grep -Fq "To switch the CLI to cc-shelf and update its skills, run:" "$TEST_ROOT/install.log"
follow_up_command="$(sed -n 's/^  CC_INSTALL_HOME=/CC_INSTALL_HOME=/p' "$TEST_ROOT/install.log")"
test -n "$follow_up_command"
# Execute the printed command with a harmless recorder to verify its quoted
# app and home targets, including paths containing spaces.
cat >"$PREVIOUS_DIR/cc.app/Contents/Resources/install_agent_tools.sh" <<'FOLLOW_UP'
#!/bin/bash
printf '%s\n%s\n' "$CC_INSTALL_HOME" "$CC_INSTALL_APP"
FOLLOW_UP
chmod +x "$PREVIOUS_DIR/cc.app/Contents/Resources/install_agent_tools.sh"
env -u CC_INSTALL_HOME -u CC_INSTALL_APP bash -c "$follow_up_command" >"$TEST_ROOT/follow-up.log"
test "$(sed -n '1p' "$TEST_ROOT/follow-up.log")" = "$PREVIOUS_HOME"
test "$(sed -n '2p' "$TEST_ROOT/follow-up.log")" = "$PREVIOUS_DIR/cc.app"

FOREIGN_DIR="$TEST_ROOT/foreign-apps"
FOREIGN_HOME="$TEST_ROOT/foreign-home"
mkdir "$FOREIGN_HOME"
make_app "$FOREIGN_DIR/cc.app" 1.0.0 example.unrelated.app
expect_rejection "$FOREIGN_DIR" "$FOREIGN_HOME" "$TEST_ROOT/valid.zip"
test "$(plutil -extract CFBundleIdentifier raw "$FOREIGN_DIR/cc.app/Contents/Info.plist")" = example.unrelated.app
printf ' 105 %s\n' "$FOREIGN_DIR/cc.app/Contents/MacOS/cc" >"$CC_TEST_PS_LIST"
: >"$CC_TEST_KILL_LOG"
PATH="$FAKE_BIN:$ORIGINAL_TEST_PATH" BASH_ENV="$TEST_ROOT/process-test-env.sh" CC_TEST_SKIP_STOP=0 \
  expect_rejection "$FOREIGN_DIR" "$FOREIGN_HOME" "$TEST_ROOT/valid.zip"
test ! -s "$CC_TEST_KILL_LOG"
printf 'App installer update and rollback checks passed.\n'
