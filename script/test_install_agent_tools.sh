#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/app_bundle.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cc-agent-tools-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT
TEST_APP="$TMP_ROOT/Applications/cc.app"
mkdir -p "$TEST_APP/Contents/Helpers" "$TEST_APP/Contents/Resources/skills/cc-handoff"
printf '#!/bin/sh\nexit 0\n' >"$TEST_APP/Contents/Helpers/cc:"
chmod +x "$TEST_APP/Contents/Helpers/cc:"
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
grep -Fq "CLI link: $TEST_HOME/.local/bin/cc: -> $TEST_APP/Contents/Helpers/cc:" "$TMP_ROOT/install.log"
test ! -e "$TEST_HOME/.local"
test ! -e "$TEST_HOME/.codex"
test ! -e "$TEST_HOME/.claude"
run_installer "$TEST_HOME"
test "$(readlink "$TEST_HOME/.local/bin/cc:")" = "$TEST_APP/Contents/Helpers/cc:"
for agent in .codex .claude; do
  cmp -s "$TEST_APP/Contents/Resources/skills/cc-handoff/SKILL.md" "$TEST_HOME/$agent/skills/cc-handoff/SKILL.md"
  test -f "$TEST_HOME/$agent/skills/cc-handoff/.cc-install-manifest"
done
CLI_INODE="$(stat -f '%i' "$TEST_HOME/.local/bin/cc:")"
SKILL_INODE="$(stat -f '%i' "$TEST_HOME/.codex/skills/cc-handoff/SKILL.md")"
run_installer "$TEST_HOME"
test "$(stat -f '%i' "$TEST_HOME/.local/bin/cc:")" = "$CLI_INODE"
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
test "$(stat -f '%i' "$TEST_HOME/.local/bin/cc:")" = "$CLI_INODE"

FILE_HOME="$TMP_ROOT/existing-cli-file"
mkdir -p "$FILE_HOME/.local/bin"
printf 'my existing command\n' >"$FILE_HOME/.local/bin/cc:"
expect_rejection "$FILE_HOME"
test "$(cat "$FILE_HOME/.local/bin/cc:")" = 'my existing command'
test ! -e "$FILE_HOME/.codex"
test ! -e "$FILE_HOME/.claude"

LINK_HOME="$TMP_ROOT/existing-cli-link"
mkdir -p "$LINK_HOME/.local/bin"
ln -s /usr/bin/true "$LINK_HOME/.local/bin/cc:"
expect_rejection "$LINK_HOME"
test "$(readlink "$LINK_HOME/.local/bin/cc:")" = /usr/bin/true
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
if [[ "$#" == 2 && "$2" == "$CC_TEST_FAIL_DEST" && ! -e "$CC_TEST_FAIL_ONCE" ]]; then
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
test "$(readlink "$ROLLBACK_HOME/.local/bin/cc:")" = "$TEST_APP/Contents/Helpers/cc:"
test -z "$(find "$ROLLBACK_HOME" -maxdepth 1 -name '.cc-agent-tools.*' -print -quit)"

# A CLI creation failure restores managed skills, before or after the move.
CLI_ROLLBACK_HOME="$TMP_ROOT/cli-rollback-home"
mkdir "$CLI_ROLLBACK_HOME"
run_installer "$CLI_ROLLBACK_HOME"
rm "$CLI_ROLLBACK_HOME/.local/bin/cc:"
for agent in .codex .claude; do
  cp "$CLI_ROLLBACK_HOME/$agent/skills/cc-handoff/SKILL.md" "$TMP_ROOT/before-$agent.md"
  cp "$CLI_ROLLBACK_HOME/$agent/skills/cc-handoff/.cc-install-manifest" "$TMP_ROOT/before-$agent.manifest"
done
printf '\nCLI transaction update.\n' >>"$TEST_APP/Contents/Resources/skills/cc-handoff/SKILL.md"
export CC_TEST_FAIL_DEST="$CLI_ROLLBACK_HOME/.local/bin/cc:"
for after_move in 0 1; do
  export CC_TEST_FAIL_AFTER_MOVE="$after_move"
  rm -f "$CC_TEST_FAIL_ONCE"
  PATH="$TMP_ROOT/fakebin:$ORIGINAL_TEST_PATH"
  expect_rejection "$CLI_ROLLBACK_HOME"
  PATH="$ORIGINAL_TEST_PATH"
  test -e "$CC_TEST_FAIL_ONCE"
  test ! -L "$CLI_ROLLBACK_HOME/.local/bin/cc:"
  for agent in .codex .claude; do
    cmp -s "$TMP_ROOT/before-$agent.md" "$CLI_ROLLBACK_HOME/$agent/skills/cc-handoff/SKILL.md"
    cmp -s "$TMP_ROOT/before-$agent.manifest" "$CLI_ROLLBACK_HOME/$agent/skills/cc-handoff/.cc-install-manifest"
  done
  test -z "$(find "$CLI_ROLLBACK_HOME" -maxdepth 1 -name '.cc-agent-tools.*' -print -quit)"
done
unset CC_TEST_FAIL_AFTER_MOVE
run_installer "$CLI_ROLLBACK_HOME"
test "$(readlink "$CLI_ROLLBACK_HOME/.local/bin/cc:")" = "$TEST_APP/Contents/Helpers/cc:"

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
printf 'Agent tools installer checks passed.\n'
