#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/app_bundle.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cc-agent-tools-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT
TEST_APP="$TMP_ROOT/Applications/cc.app"
mkdir -p "$TEST_APP/Contents/Helpers" "$TEST_APP/Contents/Resources/skills/cc-handoff"
printf '#!/bin/sh\nexit 0\n' >"$TEST_APP/Contents/Helpers/cc-shelf"
chmod +x "$TEST_APP/Contents/Helpers/cc-shelf"
cc_write_info_plist "$TEST_APP/Contents/Info.plist" 1.2.3
cp "$ROOT_DIR/skills/cc-handoff/SKILL.md" "$TEST_APP/Contents/Resources/skills/cc-handoff/SKILL.md"

run_installer() {
  local test_home="$1"
  shift
  CC_INSTALL_HOME="$test_home" CC_INSTALL_APP="$TEST_APP" \
    "$ROOT_DIR/script/install_agent_tools.sh" "$@" >"$TMP_ROOT/install.log" 2>"$TMP_ROOT/install-error.log"
}

expect_rejection() {
  if run_installer "$1"; then
    echo "Expected installer to preserve a conflicting destination" >&2
    exit 1
  fi
}

TEST_HOME="$TMP_ROOT/clean home"
mkdir "$TEST_HOME"
run_installer "$TEST_HOME" --print-plan
grep -Fq "CLI link: $TEST_HOME/.local/bin/cc-shelf -> $TEST_APP/Contents/Helpers/cc-shelf" "$TMP_ROOT/install.log"
test ! -e "$TEST_HOME/.local"
test ! -e "$TEST_HOME/.codex"
test ! -e "$TEST_HOME/.claude"
run_installer "$TEST_HOME"
test "$(readlink "$TEST_HOME/.local/bin/cc-shelf")" = "$TEST_APP/Contents/Helpers/cc-shelf"
for agent in .codex .claude; do
  cmp -s "$TEST_APP/Contents/Resources/skills/cc-handoff/SKILL.md" "$TEST_HOME/$agent/skills/cc-handoff/SKILL.md"
  test -f "$TEST_HOME/$agent/skills/cc-handoff/.cc-install-manifest"
done
CLI_INODE="$(stat -f '%i' "$TEST_HOME/.local/bin/cc-shelf")"
SKILL_INODE="$(stat -f '%i' "$TEST_HOME/.codex/skills/cc-handoff/SKILL.md")"
run_installer "$TEST_HOME"
test "$(stat -f '%i' "$TEST_HOME/.local/bin/cc-shelf")" = "$CLI_INODE"
test "$(stat -f '%i' "$TEST_HOME/.codex/skills/cc-handoff/SKILL.md")" = "$SKILL_INODE"

printf '\nUpdated bundled handoff instructions.\n' >>"$TEST_APP/Contents/Resources/skills/cc-handoff/SKILL.md"
run_installer "$TEST_HOME"
for agent in .codex .claude; do
  cmp -s "$TEST_APP/Contents/Resources/skills/cc-handoff/SKILL.md" "$TEST_HOME/$agent/skills/cc-handoff/SKILL.md"
done

printf '\nMy custom instruction.\n' >>"$TEST_HOME/.codex/skills/cc-handoff/SKILL.md"
cp "$TEST_HOME/.codex/skills/cc-handoff/SKILL.md" "$TMP_ROOT/edited-skill.md"
expect_rejection "$TEST_HOME"
cmp -s "$TMP_ROOT/edited-skill.md" "$TEST_HOME/.codex/skills/cc-handoff/SKILL.md"
cmp -s "$TEST_APP/Contents/Resources/skills/cc-handoff/SKILL.md" "$TEST_HOME/.claude/skills/cc-handoff/SKILL.md"
test "$(stat -f '%i' "$TEST_HOME/.local/bin/cc-shelf")" = "$CLI_INODE"

FILE_HOME="$TMP_ROOT/existing-cli-file"
mkdir -p "$FILE_HOME/.local/bin"
printf 'my existing command\n' >"$FILE_HOME/.local/bin/cc-shelf"
expect_rejection "$FILE_HOME"
test "$(cat "$FILE_HOME/.local/bin/cc-shelf")" = 'my existing command'
test ! -e "$FILE_HOME/.codex"
test ! -e "$FILE_HOME/.claude"

LINK_HOME="$TMP_ROOT/existing-cli-link"
mkdir -p "$LINK_HOME/.local/bin"
ln -s /usr/bin/true "$LINK_HOME/.local/bin/cc-shelf"
expect_rejection "$LINK_HOME"
test "$(readlink "$LINK_HOME/.local/bin/cc-shelf")" = /usr/bin/true
test ! -e "$LINK_HOME/.codex"

SKILL_HOME="$TMP_ROOT/existing-skill"
mkdir -p "$SKILL_HOME/.claude/skills/cc-handoff"
printf 'my skill\n' >"$SKILL_HOME/.claude/skills/cc-handoff/SKILL.md"
expect_rejection "$SKILL_HOME"
test "$(cat "$SKILL_HOME/.claude/skills/cc-handoff/SKILL.md")" = 'my skill'
test ! -e "$SKILL_HOME/.local"
test ! -e "$SKILL_HOME/.codex"

EXTRA_HOME="$TMP_ROOT/extra-skill-file"
mkdir "$EXTRA_HOME"
run_installer "$EXTRA_HOME"
printf 'keep this file\n' >"$EXTRA_HOME/.codex/skills/cc-handoff/notes.txt"
expect_rejection "$EXTRA_HOME"
test "$(cat "$EXTRA_HOME/.codex/skills/cc-handoff/notes.txt")" = 'keep this file'

PARENT_HOME="$TMP_ROOT/symlink-parent"
mkdir "$PARENT_HOME" "$TMP_ROOT/external-skills"
ln -s "$TMP_ROOT/external-skills" "$PARENT_HOME/.codex"
expect_rejection "$PARENT_HOME"
test -z "$(find "$TMP_ROOT/external-skills" -mindepth 1 -print -quit)"
test ! -e "$PARENT_HOME/.local"

ROLLBACK_HOME="$TMP_ROOT/rollback-home"
mkdir "$ROLLBACK_HOME" "$TMP_ROOT/fakebin"
cat >"$TMP_ROOT/fakebin/mv" <<'MV'
#!/bin/bash
if [[ "$#" == 2 && ( "$2" == "$CC_TEST_FAIL_DEST" || "$1" == "${CC_TEST_FAIL_SOURCE:-}" ) && ! -e "$CC_TEST_FAIL_ONCE" ]]; then
  if [[ "${CC_TEST_FAIL_AFTER_MOVE:-0}" == 1 ]]; then
    /bin/mv "$@" || exit "$?"
  fi
  : >"$CC_TEST_FAIL_ONCE"
  exit 1
fi
exec /bin/mv "$@"
MV
chmod +x "$TMP_ROOT/fakebin/mv"
export CC_TEST_FAIL_DEST="$ROLLBACK_HOME/.claude/skills/cc-handoff"
export CC_TEST_FAIL_ONCE="$TMP_ROOT/failed-once"
ORIGINAL_TEST_PATH="$PATH"
PATH="$TMP_ROOT/fakebin:$PATH"
expect_rejection "$ROLLBACK_HOME"
PATH="$ORIGINAL_TEST_PATH"
test -e "$CC_TEST_FAIL_ONCE"
test ! -e "$ROLLBACK_HOME/.local"
test ! -e "$ROLLBACK_HOME/.codex"
test ! -e "$ROLLBACK_HOME/.claude"
test -z "$(find "$ROLLBACK_HOME" -mindepth 1 -print -quit)"

run_installer "$ROLLBACK_HOME"
cp "$ROLLBACK_HOME/.codex/skills/cc-handoff/SKILL.md" "$TMP_ROOT/before-upgrade.md"
printf '\nAnother bundled update.\n' >>"$TEST_APP/Contents/Resources/skills/cc-handoff/SKILL.md"
rm "$CC_TEST_FAIL_ONCE"
PATH="$TMP_ROOT/fakebin:$PATH"
expect_rejection "$ROLLBACK_HOME"
PATH="$ORIGINAL_TEST_PATH"
test -e "$CC_TEST_FAIL_ONCE"
for agent in .codex .claude; do
  cmp -s "$TMP_ROOT/before-upgrade.md" "$ROLLBACK_HOME/$agent/skills/cc-handoff/SKILL.md"
done
test "$(readlink "$ROLLBACK_HOME/.local/bin/cc-shelf")" = "$TEST_APP/Contents/Helpers/cc-shelf"
test -z "$(find "$ROLLBACK_HOME" -maxdepth 1 -name '.cc-agent-tools.*' -print -quit)"

# A CLI creation failure restores managed skills, before or after the move.
CLI_ROLLBACK_HOME="$TMP_ROOT/cli-rollback-home"
mkdir "$CLI_ROLLBACK_HOME"
run_installer "$CLI_ROLLBACK_HOME"
rm "$CLI_ROLLBACK_HOME/.local/bin/cc-shelf"
for agent in .codex .claude; do
  cp "$CLI_ROLLBACK_HOME/$agent/skills/cc-handoff/SKILL.md" "$TMP_ROOT/before-$agent.md"
  cp "$CLI_ROLLBACK_HOME/$agent/skills/cc-handoff/.cc-install-manifest" "$TMP_ROOT/before-$agent.manifest"
done
printf '\nCLI transaction update.\n' >>"$TEST_APP/Contents/Resources/skills/cc-handoff/SKILL.md"
export CC_TEST_FAIL_DEST="$CLI_ROLLBACK_HOME/.local/bin/cc-shelf"
for after_move in 0 1; do
  export CC_TEST_FAIL_AFTER_MOVE="$after_move"
  rm -f "$CC_TEST_FAIL_ONCE"
  PATH="$TMP_ROOT/fakebin:$ORIGINAL_TEST_PATH"
  expect_rejection "$CLI_ROLLBACK_HOME"
  PATH="$ORIGINAL_TEST_PATH"
  test -e "$CC_TEST_FAIL_ONCE"
  test ! -L "$CLI_ROLLBACK_HOME/.local/bin/cc-shelf"
  for agent in .codex .claude; do
    cmp -s "$TMP_ROOT/before-$agent.md" "$CLI_ROLLBACK_HOME/$agent/skills/cc-handoff/SKILL.md"
    cmp -s "$TMP_ROOT/before-$agent.manifest" "$CLI_ROLLBACK_HOME/$agent/skills/cc-handoff/.cc-install-manifest"
  done
  test -z "$(find "$CLI_ROLLBACK_HOME" -maxdepth 1 -name '.cc-agent-tools.*' -print -quit)"
done
unset CC_TEST_FAIL_AFTER_MOVE
run_installer "$CLI_ROLLBACK_HOME"
test "$(readlink "$CLI_ROLLBACK_HOME/.local/bin/cc-shelf")" = "$TEST_APP/Contents/Helpers/cc-shelf"

SKILL_LINK_HOME="$TMP_ROOT/skill-symlink-home"
mkdir -p "$SKILL_LINK_HOME/.codex/skills" "$TMP_ROOT/foreign-skill"
printf 'keep external instructions\n' >"$TMP_ROOT/foreign-skill/SKILL.md"
ln -s "$TMP_ROOT/foreign-skill" "$SKILL_LINK_HOME/.codex/skills/cc-handoff"
expect_rejection "$SKILL_LINK_HOME"
test "$(readlink "$SKILL_LINK_HOME/.codex/skills/cc-handoff")" = "$TMP_ROOT/foreign-skill"
test "$(cat "$TMP_ROOT/foreign-skill/SKILL.md")" = 'keep external instructions'
test ! -e "$SKILL_LINK_HOME/.local"
test ! -e "$SKILL_LINK_HOME/.claude"

MANIFEST_HOME="$TMP_ROOT/foreign-manifest-home"
mkdir "$MANIFEST_HOME"
run_installer "$MANIFEST_HOME"
manifest="$MANIFEST_HOME/.codex/skills/cc-handoff/.cc-install-manifest"
saved_hash="$(sed -n '2p' "$manifest")"
printf 'Unrelated skill installer\n%s\n' "$saved_hash" >"$manifest"
cp "$manifest" "$TMP_ROOT/foreign-manifest.before"
expect_rejection "$MANIFEST_HOME"
cmp -s "$TMP_ROOT/foreign-manifest.before" "$manifest"
# Renaming the managed command also refreshes unedited installed skills.
PREVIOUS_HOME="$TMP_ROOT/previous-command-home"
mkdir "$PREVIOUS_HOME"
run_installer "$PREVIOUS_HOME"
rm "$PREVIOUS_HOME/.local/bin/cc-shelf"
ln -s "$TEST_APP/Contents/Helpers/cc:" "$PREVIOUS_HOME/.local/bin/cc:"
printf '\nInstructions for the renamed command.\n' >>"$TEST_APP/Contents/Resources/skills/cc-handoff/SKILL.md"
run_installer "$PREVIOUS_HOME" --print-plan
grep -Fq "Previous CLI link to remove: $PREVIOUS_HOME/.local/bin/cc:" "$TMP_ROOT/install.log"
test -L "$PREVIOUS_HOME/.local/bin/cc:"
test ! -L "$PREVIOUS_HOME/.local/bin/cc-shelf"
run_installer "$PREVIOUS_HOME"
test ! -e "$PREVIOUS_HOME/.local/bin/cc:" && test ! -L "$PREVIOUS_HOME/.local/bin/cc:"
test "$(readlink "$PREVIOUS_HOME/.local/bin/cc-shelf")" = "$TEST_APP/Contents/Helpers/cc-shelf"
for agent in .codex .claude; do
  cmp -s "$TEST_APP/Contents/Resources/skills/cc-handoff/SKILL.md" "$PREVIOUS_HOME/$agent/skills/cc-handoff/SKILL.md"
done

# The previous name can belong to someone else, including a dangling link.
for kind in file link; do
  previous_custom_home="$TMP_ROOT/previous-custom-$kind"
  mkdir -p "$previous_custom_home/.local/bin"
  if [[ "$kind" == link ]]; then
    ln -s "$TMP_ROOT/unrelated-missing-command" "$previous_custom_home/.local/bin/cc:"
  else
    printf 'unrelated command\n' >"$previous_custom_home/.local/bin/cc:"
  fi
  run_installer "$previous_custom_home"
  test "$(readlink "$previous_custom_home/.local/bin/cc-shelf")" = "$TEST_APP/Contents/Helpers/cc-shelf"
  if [[ "$kind" == link ]]; then
    test "$(readlink "$previous_custom_home/.local/bin/cc:")" = "$TMP_ROOT/unrelated-missing-command"
  else
    test "$(cat "$previous_custom_home/.local/bin/cc:")" = 'unrelated command'
  fi
done

# Failure while retiring the old link restores it, the skills, and new CLI state.
PREVIOUS_ROLLBACK_HOME="$TMP_ROOT/previous-rollback-home"
mkdir "$PREVIOUS_ROLLBACK_HOME"
run_installer "$PREVIOUS_ROLLBACK_HOME"
rm "$PREVIOUS_ROLLBACK_HOME/.local/bin/cc-shelf"
ln -s "$TEST_APP/Contents/Helpers/cc:" "$PREVIOUS_ROLLBACK_HOME/.local/bin/cc:"
for agent in .codex .claude; do
  cp "$PREVIOUS_ROLLBACK_HOME/$agent/skills/cc-handoff/SKILL.md" "$TMP_ROOT/previous-$agent.md"
  cp "$PREVIOUS_ROLLBACK_HOME/$agent/skills/cc-handoff/.cc-install-manifest" "$TMP_ROOT/previous-$agent.manifest"
done
printf '\nCommand rename transaction update.\n' >>"$TEST_APP/Contents/Resources/skills/cc-handoff/SKILL.md"
export CC_TEST_FAIL_DEST="" CC_TEST_FAIL_SOURCE="$PREVIOUS_ROLLBACK_HOME/.local/bin/cc:"
for after_move in 0 1; do
  export CC_TEST_FAIL_AFTER_MOVE="$after_move"
  rm -f "$CC_TEST_FAIL_ONCE"
  PATH="$TMP_ROOT/fakebin:$ORIGINAL_TEST_PATH"
  expect_rejection "$PREVIOUS_ROLLBACK_HOME"
  PATH="$ORIGINAL_TEST_PATH"
  test -e "$CC_TEST_FAIL_ONCE"
  test "$(readlink "$PREVIOUS_ROLLBACK_HOME/.local/bin/cc:")" = "$TEST_APP/Contents/Helpers/cc:"
  test ! -L "$PREVIOUS_ROLLBACK_HOME/.local/bin/cc-shelf"
  for agent in .codex .claude; do
    cmp -s "$TMP_ROOT/previous-$agent.md" "$PREVIOUS_ROLLBACK_HOME/$agent/skills/cc-handoff/SKILL.md"
    cmp -s "$TMP_ROOT/previous-$agent.manifest" "$PREVIOUS_ROLLBACK_HOME/$agent/skills/cc-handoff/.cc-install-manifest"
  done
  test -z "$(find "$PREVIOUS_ROLLBACK_HOME" -maxdepth 1 -name '.cc-agent-tools.*' -print -quit)"
done
unset CC_TEST_FAIL_AFTER_MOVE CC_TEST_FAIL_SOURCE
run_installer "$PREVIOUS_ROLLBACK_HOME"
test ! -L "$PREVIOUS_ROLLBACK_HOME/.local/bin/cc:"
test "$(readlink "$PREVIOUS_ROLLBACK_HOME/.local/bin/cc-shelf")" = "$TEST_APP/Contents/Helpers/cc-shelf"

# --check must classify installed state without touching inspected files.
CHECK_GUARD_BIN="$TMP_ROOT/check-guard-bin"
mkdir "$CHECK_GUARD_BIN"
export CC_TEST_CHECK_MUTATION_LOG="$TMP_ROOT/check-mutations.log"
for command in mkdir mktemp cp mv ln rm chmod rmdir; do
  cat >"$CHECK_GUARD_BIN/$command" <<'MUTATION'
#!/bin/bash
printf '%s\n' "$0" >>"$CC_TEST_CHECK_MUTATION_LOG"
printf 'A read-only check invoked a mutating command.\n' >&2
exit 90
MUTATION
done
cat >"$CHECK_GUARD_BIN/readlink" <<'READLINK'
#!/bin/bash
if [[ "$1" == "${CC_TEST_CHECK_FAIL_READLINK:-}" ]]; then exit 1; fi
exec /usr/bin/readlink "$@"
READLINK
cat >"$CHECK_GUARD_BIN/find" <<'FIND'
#!/bin/bash
if [[ "$1" == "${CC_TEST_CHECK_FAIL_FIND:-}" ]]; then exit 1; fi
exec /usr/bin/find "$@"
FIND
chmod +x "$CHECK_GUARD_BIN"/*

snapshot_check_home() {
  python3 - "$1" <<'SNAPSHOT'
import hashlib
import json
import os
from pathlib import Path
import stat
import sys

root = Path(sys.argv[1])
rows = []
def visit(path):
    info = path.lstat()
    row = [str(path.relative_to(root)), info.st_mode, info.st_ino, info.st_mtime_ns]
    if stat.S_ISLNK(info.st_mode):
        row.append(os.readlink(path))
    elif stat.S_ISREG(info.st_mode):
        try:
            row.append(hashlib.sha256(path.read_bytes()).hexdigest())
        except PermissionError:
            row.append('unreadable')
    rows.append(row)
    if stat.S_ISDIR(info.st_mode):
        try:
            children = sorted(path.iterdir())
        except PermissionError:
            return
        for child in children:
            visit(child)
visit(root)
print(json.dumps(rows, ensure_ascii=True))
SNAPSHOT
}

CHECK_CASE_COUNT=0
assert_check() {
  local test_home="$1" expected_status="$2" expected_cli="$3"
  local expected_codex="$4" expected_claude="$5" expected_legacy="$6"
  local expected_exit="${7:-0}" actual_exit=0
  snapshot_check_home "$test_home" >"$TMP_ROOT/check-before.json"
  : >"$CC_TEST_CHECK_MUTATION_LOG"
  CC_INSTALL_HOME="$test_home" CC_INSTALL_APP="${CC_TEST_CHECK_APP:-$TEST_APP}" \
    PATH="$CHECK_GUARD_BIN:$PATH" \
    "$ROOT_DIR/script/install_agent_tools.sh" --check \
    >"$TMP_ROOT/check.json" 2>"$TMP_ROOT/check-error.log" || actual_exit=$?
  snapshot_check_home "$test_home" >"$TMP_ROOT/check-after.json"
  cmp -s "$TMP_ROOT/check-before.json" "$TMP_ROOT/check-after.json"
  test ! -s "$CC_TEST_CHECK_MUTATION_LOG"
  python3 - "$TMP_ROOT/check.json" "$actual_exit" "$expected_exit" \
    "$expected_status" "$expected_cli" "$expected_codex" "$expected_claude" "$expected_legacy" <<'CHECK'
import json
from pathlib import Path
import sys

raw = Path(sys.argv[1]).read_text()
assert raw.endswith('\n') and raw.count('\n') == 1, raw
result = json.loads(raw)
keys = ['status', 'cli', 'codex', 'claude', 'legacy_cli']
expected = dict(zip(keys, sys.argv[4:]))
assert result == expected, (result, expected)
assert sys.argv[2] == sys.argv[3], ('exit status', sys.argv[2], sys.argv[3])
CHECK
  if [[ "$expected_exit" == 0 ]]; then test ! -s "$TMP_ROOT/check-error.log"; fi
  CHECK_CASE_COUNT=$((CHECK_CASE_COUNT + 1))
}

CHECK_EMPTY_HOME="$TMP_ROOT/check-empty-home"
mkdir "$CHECK_EMPTY_HOME"
assert_check "$CHECK_EMPTY_HOME" not-installed not-installed not-installed not-installed absent

CHECK_READY_HOME="$TMP_ROOT/check-ready-home"
mkdir "$CHECK_READY_HOME"
run_installer "$CHECK_READY_HOME"
assert_check "$CHECK_READY_HOME" up-to-date up-to-date up-to-date up-to-date absent

CHECK_PARTIAL_HOME="$TMP_ROOT/check-partial-home"
mkdir "$CHECK_PARTIAL_HOME"
run_installer "$CHECK_PARTIAL_HOME"
rm -rf "$CHECK_PARTIAL_HOME/.claude/skills/cc-handoff"
assert_check "$CHECK_PARTIAL_HOME" outdated up-to-date up-to-date not-installed absent

CHECK_STALE_HOME="$TMP_ROOT/check-stale-home"
mkdir "$CHECK_STALE_HOME"
run_installer "$CHECK_STALE_HOME"
stale_skill="$CHECK_STALE_HOME/.codex/skills/cc-handoff"
printf '\nPreviously bundled instructions.\n' >>"$stale_skill/SKILL.md"
stale_hash="$(shasum -a 256 "$stale_skill/SKILL.md" | awk '{print $1}')"
printf 'cc: cc-handoff installer v1\n%s\n' "$stale_hash" >"$stale_skill/.cc-install-manifest"
assert_check "$CHECK_STALE_HOME" outdated up-to-date outdated up-to-date absent
# The same shared inspection permits an installer-owned, unedited update.
run_installer "$CHECK_STALE_HOME"
assert_check "$CHECK_STALE_HOME" up-to-date up-to-date up-to-date up-to-date absent

CHECK_EDITED_HOME="$TMP_ROOT/check-edited-home"
mkdir "$CHECK_EDITED_HOME"
run_installer "$CHECK_EDITED_HOME"
printf '\nMy edit.\n' >>"$CHECK_EDITED_HOME/.codex/skills/cc-handoff/SKILL.md"
assert_check "$CHECK_EDITED_HOME" user-modified up-to-date user-modified up-to-date absent
expect_rejection "$CHECK_EDITED_HOME"
# Structural conflicts take priority over an edited file in the same skill.
printf 'keep\n' >"$CHECK_EDITED_HOME/.codex/skills/cc-handoff/extra.txt"
assert_check "$CHECK_EDITED_HOME" blocked up-to-date blocked up-to-date absent

for kind in file link dangling; do
  check_home="$TMP_ROOT/check-foreign-cli-$kind"
  mkdir -p "$check_home/.local/bin"
  case "$kind" in
    file) printf 'foreign command\n' >"$check_home/.local/bin/cc-shelf" ;;
    link) ln -s /usr/bin/true "$check_home/.local/bin/cc-shelf" ;;
    dangling) ln -s "$TMP_ROOT/missing-foreign-command" "$check_home/.local/bin/cc-shelf" ;;
  esac
  assert_check "$check_home" blocked blocked not-installed not-installed absent
  expect_rejection "$check_home"
done

for kind in foreign-owner malformed-hash extra-line unmanaged skill-link manifest-link; do
  check_home="$TMP_ROOT/check-foreign-skill-$kind"
  mkdir "$check_home"
  run_installer "$check_home"
  skill="$check_home/.codex/skills/cc-handoff"
  case "$kind" in
    foreign-owner) sed -i '' '1s/.*/Another installer/' "$skill/.cc-install-manifest" ;;
    malformed-hash) printf 'cc: cc-handoff installer v1\nnot-a-sha256\n' >"$skill/.cc-install-manifest" ;;
    extra-line) printf 'extra\n' >>"$skill/.cc-install-manifest" ;;
    unmanaged) rm "$skill/.cc-install-manifest" ;;
    skill-link) rm "$skill/SKILL.md"; ln -s "$SKILL_HOME/.claude/skills/cc-handoff/SKILL.md" "$skill/SKILL.md" ;;
    manifest-link)
      cp "$skill/.cc-install-manifest" "$TMP_ROOT/foreign-skill-manifest"
      rm "$skill/.cc-install-manifest"
      ln -s "$TMP_ROOT/foreign-skill-manifest" "$skill/.cc-install-manifest"
      ;;
  esac
  assert_check "$check_home" blocked up-to-date blocked up-to-date absent
  expect_rejection "$check_home"
done

# A parent collision is known blocked; the old CLI is safely left uninspected.
for relative in .local .local/bin .codex .codex/skills .claude .claude/skills; do
  for kind in link file; do
    check_home="$TMP_ROOT/check-parent-${relative//\//-}-$kind"
    check_target="$TMP_ROOT/check-external-${relative//\//-}-$kind"
    mkdir -p "$check_home/$(dirname "$relative")" "$check_target"
    if [[ "$kind" == link ]]; then
      ln -s "$check_target" "$check_home/$relative"
    else
      printf 'foreign parent\n' >"$check_home/$relative"
    fi
    case "$relative" in
      .local*) assert_check "$check_home" blocked blocked not-installed not-installed unknown ;;
      .codex*) assert_check "$check_home" blocked not-installed blocked not-installed absent ;;
      .claude*) assert_check "$check_home" blocked not-installed not-installed blocked absent ;;
    esac
    test -z "$(find "$check_target" -mindepth 1 -print -quit)"
    expect_rejection "$check_home"
  done
done

CHECK_LEGACY_HOME="$TMP_ROOT/check-legacy-home"
mkdir -p "$CHECK_LEGACY_HOME/.local/bin"
ln -s "$TEST_APP/Contents/Helpers/cc:" "$CHECK_LEGACY_HOME/.local/bin/cc:"
test ! -e "$CHECK_LEGACY_HOME/.local/bin/cc:"
assert_check "$CHECK_LEGACY_HOME" outdated not-installed not-installed not-installed managed
run_installer "$CHECK_LEGACY_HOME"
ln -s "$TEST_APP/Contents/Helpers/cc:" "$CHECK_LEGACY_HOME/.local/bin/cc:"
assert_check "$CHECK_LEGACY_HOME" outdated up-to-date up-to-date up-to-date managed
export CC_TEST_CHECK_FAIL_READLINK="$CHECK_LEGACY_HOME/.local/bin/cc:"
assert_check "$CHECK_LEGACY_HOME" unknown up-to-date up-to-date up-to-date unknown 1
unset CC_TEST_CHECK_FAIL_READLINK

for kind in file link; do
  check_home="$TMP_ROOT/check-unrelated-legacy-$kind"
  mkdir "$check_home"
  run_installer "$check_home"
  if [[ "$kind" == file ]]; then
    printf 'foreign old command\n' >"$check_home/.local/bin/cc:"
  else
    ln -s "$TMP_ROOT/another-missing-old-command" "$check_home/.local/bin/cc:"
  fi
  assert_check "$check_home" up-to-date up-to-date up-to-date up-to-date unrelated
done

# Actual inspection failures are unknown, never "missing" or "modified".
export CC_TEST_CHECK_FAIL_FIND="$CHECK_READY_HOME/.codex/skills/cc-handoff"
assert_check "$CHECK_READY_HOME" unknown up-to-date unknown up-to-date absent 1
unset CC_TEST_CHECK_FAIL_FIND
CC_TEST_CHECK_APP="$TMP_ROOT/no-such-app.app" \
  assert_check "$CHECK_READY_HOME" unknown unknown unknown unknown unknown 1
if [[ "$(id -u)" != 0 ]]; then
  chmod 000 "$CHECK_READY_HOME/.claude/skills/cc-handoff/SKILL.md"
  assert_check "$CHECK_READY_HOME" unknown up-to-date up-to-date unknown absent 1
  chmod 644 "$CHECK_READY_HOME/.claude/skills/cc-handoff/SKILL.md"
fi

printf 'Agent tools installer and %s read-only state checks passed.\n' "$CHECK_CASE_COUNT"
