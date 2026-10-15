#!/usr/bin/env bash
set -euo pipefail

INSTALL_HOME="${CC_INSTALL_HOME:-$HOME}"
INSTALL_APP="${CC_INSTALL_APP:-}"
if [[ -z "$INSTALL_APP" ]]; then
  for candidate in /Applications/cc.app "$INSTALL_HOME/Applications/cc.app"; do
    if [[ -d "$candidate" ]]; then
      INSTALL_APP="$candidate"
      break
    fi
  done
  INSTALL_APP="${INSTALL_APP:-/Applications/cc.app}"
fi
INSTALL_HOME="${INSTALL_HOME%/}"
INSTALL_APP="${INSTALL_APP%/}"
CLI_BINARY="$INSTALL_APP/Contents/Helpers/cc-shelf"
SKILL_SOURCE="$INSTALL_APP/Contents/Resources/skills/cc-handoff/SKILL.md"
CLI_DESTINATION="$INSTALL_HOME/.local/bin/cc-shelf"
PREVIOUS_CLI_DESTINATION="$INSTALL_HOME/.local/bin/cc:"
PREVIOUS_CLI_BINARY="$INSTALL_APP/Contents/Helpers/cc:"
CODEX_DESTINATION="$INSTALL_HOME/.codex/skills/cc-handoff"
CLAUDE_DESTINATION="$INSTALL_HOME/.claude/skills/cc-handoff"
MANIFEST_NAME=".cc-install-manifest"
OWNER_MARKER="cc: cc-handoff installer v1"
PRINT_PLAN=0
CHECK_MODE=0
ARGUMENT_ERROR=0
for argument in "$@"; do
  if [[ "$argument" == --check ]]; then CHECK_MODE=1; fi
done
if [[ "$#" == 1 && "$1" == --print-plan ]]; then
  PRINT_PLAN=1
elif [[ "$#" == 1 && "$1" == --check ]]; then
  CHECK_MODE=1
elif [[ "$#" != 0 ]]; then
  ARGUMENT_ERROR=1
fi

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

file_hash() {
  /usr/bin/shasum -a 256 "$1" | awk '{print $1}'
}

print_check() {
  printf '{"status":"%s","cli":"%s","codex":"%s","claude":"%s","legacy_cli":"%s"}\n' \
    "$1" "$2" "$3" "$4" "$5"
}

if (( ARGUMENT_ERROR )); then
  if (( CHECK_MODE )); then print_check unknown unknown unknown unknown unknown; fi
  printf 'usage: install_agent_tools.sh [--print-plan | --check]\n' >&2
  exit 2
fi

SOURCE_ERROR=""
SOURCE_HASH=""
validate_source() {
  local bundle_id
  if [[ "$INSTALL_HOME" != /* || ! -d "$INSTALL_HOME" || -L "$INSTALL_HOME" ]]; then
    SOURCE_ERROR="CC_INSTALL_HOME must be an existing absolute directory."
  elif [[ ! -r "$INSTALL_HOME" || ! -x "$INSTALL_HOME" ]]; then
    SOURCE_ERROR="Could not inspect CC_INSTALL_HOME."
  elif [[ "$INSTALL_APP" != /* || ! -d "$INSTALL_APP" || -L "$INSTALL_APP" ]]; then
    SOURCE_ERROR="cc: app not found at $INSTALL_APP."
  elif ! bundle_id="$(plutil -extract CFBundleIdentifier raw "$INSTALL_APP/Contents/Info.plist" 2>/dev/null)"; then
    SOURCE_ERROR="Could not inspect the selected cc: app."
  elif [[ "$bundle_id" != work.hayashigoto.cc ]]; then
    SOURCE_ERROR="The selected app is not cc:."
  elif [[ ! -f "$CLI_BINARY" || ! -x "$CLI_BINARY" || -L "$CLI_BINARY" ]]; then
    SOURCE_ERROR="The selected cc: app does not contain its CLI."
  elif [[ ! -f "$SKILL_SOURCE" || -L "$SKILL_SOURCE" || ! -r "$SKILL_SOURCE" ]]; then
    SOURCE_ERROR="Could not read the selected app's handoff skill."
  elif ! SOURCE_HASH="$(file_hash "$SKILL_SOURCE" 2>/dev/null)"; then
    SOURCE_ERROR="Could not read the selected app's handoff skill."
  fi
  [[ -z "$SOURCE_ERROR" ]]
}

if ! validate_source; then
  if (( CHECK_MODE )); then print_check unknown unknown unknown unknown unknown; fi
  fail "$SOURCE_ERROR"
fi

PARENTS=(
  "$INSTALL_HOME/.local" "$INSTALL_HOME/.local/bin"
  "$INSTALL_HOME/.codex" "$INSTALL_HOME/.codex/skills"
  "$INSTALL_HOME/.claude" "$INSTALL_HOME/.claude/skills"
)

# These read-only inspectors also guard the installer's writes. They return
# state separately from their diagnostic so --check can report every component.
inspection_result() {
  INSPECTION_STATE="$1"
  INSPECTION_MESSAGE="$2"
}

inspect_parents() {
  local parent
  inspection_result up-to-date ""
  for parent in "$@"; do
    if [[ -L "$parent" ]]; then
      inspection_result blocked "Preserving existing symlink: $parent"
      return
    elif [[ -e "$parent" ]]; then
      if [[ ! -d "$parent" ]]; then
        inspection_result blocked "Preserving existing file: $parent"
        return
      elif [[ ! -r "$parent" || ! -x "$parent" ]]; then
        inspection_result unknown "Could not inspect directory: $parent"
        return
      fi
    fi
  done
}

inspect_cli() {
  local target
  inspect_parents "$INSTALL_HOME/.local" "$INSTALL_HOME/.local/bin"
  [[ "$INSPECTION_STATE" == up-to-date ]] || return 0
  if [[ -L "$CLI_DESTINATION" ]]; then
    if ! target="$(readlink "$CLI_DESTINATION" 2>/dev/null)"; then
      inspection_result unknown "Could not inspect CLI symlink: $CLI_DESTINATION"
    elif [[ "$target" == "$CLI_BINARY" ]]; then
      inspection_result up-to-date ""
    else
      inspection_result blocked "Preserving an unrelated CLI symlink: $CLI_DESTINATION"
    fi
  elif [[ -e "$CLI_DESTINATION" ]]; then
    inspection_result blocked "Preserving an existing CLI file: $CLI_DESTINATION"
  else
    inspection_result not-installed ""
  fi
}

inspect_skill() {
  local destination="$1"
  local manifest="$destination/$MANIFEST_NAME"
  local manifest_owner saved_hash manifest_lines manifest_bytes actual_hash extra_files
  inspect_parents "${destination%/skills/cc-handoff}" "${destination%/cc-handoff}"
  [[ "$INSPECTION_STATE" == up-to-date ]] || return 0
  if [[ -L "$destination" ]]; then
    inspection_result blocked "Preserving existing skill symlink: $destination"
  elif [[ ! -e "$destination" ]]; then
    inspection_result not-installed ""
  elif [[ ! -d "$destination" ]]; then
    inspection_result blocked "Preserving an existing skill file: $destination"
  elif [[ ! -r "$destination" || ! -x "$destination" ]]; then
    inspection_result unknown "Could not inspect skill directory: $destination"
  elif ! extra_files="$(find "$destination" -mindepth 1 -maxdepth 1 ! -name SKILL.md ! -name "$MANIFEST_NAME" -print -quit 2>/dev/null)"; then
    inspection_result unknown "Could not inspect the existing skill: $destination"
  elif [[ -n "$extra_files" ]]; then
    inspection_result blocked "Preserving extra files in the skill: $destination"
  elif [[ ! -f "$manifest" || -L "$manifest" || ! -f "$destination/SKILL.md" || -L "$destination/SKILL.md" ]]; then
    inspection_result blocked "Preserving an existing skill without a recognized install manifest: $destination"
  elif [[ ! -r "$manifest" || ! -r "$destination/SKILL.md" ]]; then
    inspection_result unknown "Could not read the existing skill: $destination"
  elif ! manifest_owner="$(sed -n '1p' "$manifest" 2>/dev/null)" \
      || ! saved_hash="$(sed -n '2p' "$manifest" 2>/dev/null)" \
      || ! manifest_lines="$(wc -l <"$manifest" 2>/dev/null)" \
      || ! manifest_bytes="$(wc -c <"$manifest" 2>/dev/null)"; then
    inspection_result unknown "Could not read the skill manifest: $destination"
  elif [[ "$manifest_owner" != "$OWNER_MARKER" || ! "$saved_hash" =~ ^[0-9a-f]{64}$ \
      || "${manifest_lines//[[:space:]]/}" != 2 \
      || "${manifest_bytes//[[:space:]]/}" != "$((${#OWNER_MARKER} + 66))" ]]; then
    inspection_result blocked "Preserving an unrecognized skill manifest: $destination"
  elif ! actual_hash="$(file_hash "$destination/SKILL.md" 2>/dev/null)"; then
    inspection_result unknown "Could not read the existing skill: $destination"
  elif [[ "$actual_hash" != "$saved_hash" ]]; then
    inspection_result user-modified "Preserving a user-edited skill: $destination"
  elif [[ "$actual_hash" != "$SOURCE_HASH" ]]; then
    inspection_result outdated ""
  else
    inspection_result up-to-date ""
  fi
}

inspect_legacy_cli() {
  local target
  LEGACY_INSPECTION_FAILED=0
  inspect_parents "$INSTALL_HOME/.local" "$INSTALL_HOME/.local/bin"
  if [[ "$INSPECTION_STATE" != up-to-date ]]; then
    LEGACY_CLI_STATE=unknown
    # A known foreign parent is blocked, rather than an unknown I/O failure.
    if [[ "$INSPECTION_STATE" == unknown ]]; then LEGACY_INSPECTION_FAILED=1; fi
  elif [[ -L "$PREVIOUS_CLI_DESTINATION" ]]; then
    if ! target="$(readlink "$PREVIOUS_CLI_DESTINATION" 2>/dev/null)"; then
      LEGACY_CLI_STATE=unknown
      LEGACY_INSPECTION_FAILED=1
    elif [[ "$target" == "$PREVIOUS_CLI_BINARY" ]]; then
      LEGACY_CLI_STATE=managed
    else
      LEGACY_CLI_STATE=unrelated
    fi
  elif [[ -e "$PREVIOUS_CLI_DESTINATION" ]]; then
    LEGACY_CLI_STATE=unrelated
  else
    LEGACY_CLI_STATE=absent
  fi
}

preflight_cli() {
  inspect_cli
  case "$INSPECTION_STATE" in
    up-to-date|not-installed) ;;
    *) fail "$INSPECTION_MESSAGE" ;;
  esac
}

preflight_skill() {
  inspect_skill "$1"
  case "$INSPECTION_STATE" in
    up-to-date|not-installed|outdated) ;;
    *) fail "$INSPECTION_MESSAGE" ;;
  esac
}

if (( CHECK_MODE )); then
  inspect_cli
  CLI_STATE="$INSPECTION_STATE"
  inspect_skill "$CODEX_DESTINATION"
  CODEX_STATE="$INSPECTION_STATE"
  inspect_skill "$CLAUDE_DESTINATION"
  CLAUDE_STATE="$INSPECTION_STATE"
  inspect_legacy_cli
  CHECK_STATUS=up-to-date
  CHECK_EXIT_STATUS=0
  case "$CLI_STATE $CODEX_STATE $CLAUDE_STATE" in
    *unknown*) CHECK_STATUS=unknown; CHECK_EXIT_STATUS=1 ;;
    *blocked*) CHECK_STATUS=blocked ;;
    *user-modified*) CHECK_STATUS=user-modified ;;
    *outdated*) CHECK_STATUS=outdated ;;
    'not-installed not-installed not-installed') CHECK_STATUS=not-installed ;;
    *not-installed*) CHECK_STATUS=outdated ;;
  esac
  if (( LEGACY_INSPECTION_FAILED )); then
    CHECK_STATUS=unknown
    CHECK_EXIT_STATUS=1
  elif [[ "$LEGACY_CLI_STATE" == managed && ( "$CHECK_STATUS" == up-to-date || "$CHECK_STATUS" == not-installed ) ]]; then
    CHECK_STATUS=outdated
  fi
  print_check "$CHECK_STATUS" "$CLI_STATE" "$CODEX_STATE" "$CLAUDE_STATE" "$LEGACY_CLI_STATE"
  if (( CHECK_EXIT_STATUS )); then printf 'Could not inspect all agent tool files.\n' >&2; fi
  exit "$CHECK_EXIT_STATUS"
fi

preflight_cli
preflight_skill "$CODEX_DESTINATION"
preflight_skill "$CLAUDE_DESTINATION"

if [[ "$PRINT_PLAN" == 1 ]]; then
  printf 'CLI link: %s -> %s\nCodex skill: %s\nClaude skill: %s\n' \
    "$CLI_DESTINATION" "$CLI_BINARY" "$CODEX_DESTINATION" "$CLAUDE_DESTINATION"
  if [[ -L "$PREVIOUS_CLI_DESTINATION" && "$(readlink "$PREVIOUS_CLI_DESTINATION")" == "$PREVIOUS_CLI_BINARY" ]]; then
    printf 'Previous CLI link to remove: %s\n' "$PREVIOUS_CLI_DESTINATION"
  fi
  exit 0
fi

STAGING_DIR="$(mktemp -d "$INSTALL_HOME/.cc-agent-tools.XXXXXX")"
SUCCESS=0
CLI_INSTALLED=0
CODEX_INSTALLED=0
CLAUDE_INSTALLED=0
CREATED_DIR_COUNT=0
CREATED_DIRS=()

restore_skill() {
  local destination="$1"
  local backup="$2"
  local installed="$3"
  if [[ "$installed" == 1 ]]; then
    rm -rf "$destination" || return 1
  fi
  if [[ -d "$backup" ]]; then
    [[ ! -e "$destination" && ! -L "$destination" ]] || return 1
    mv "$backup" "$destination" || return 1
  fi
}

cleanup() {
  local rollback_failed=0
  local index
  if [[ "$SUCCESS" != 1 ]]; then
    if [[ "$CLI_INSTALLED" == 1 ]]; then
      if [[ -L "$CLI_DESTINATION" && "$(readlink "$CLI_DESTINATION")" == "$CLI_BINARY" ]]; then
        rm -f "$CLI_DESTINATION" || rollback_failed=1
      elif [[ -e "$CLI_DESTINATION" || -L "$CLI_DESTINATION" ]]; then
        rollback_failed=1
      fi
    fi
    if [[ -L "$STAGING_DIR/cli.previous" ]]; then
      if [[ ! -e "$PREVIOUS_CLI_DESTINATION" && ! -L "$PREVIOUS_CLI_DESTINATION" ]]; then
        mv "$STAGING_DIR/cli.previous" "$PREVIOUS_CLI_DESTINATION" || rollback_failed=1
      else
        rollback_failed=1
      fi
    fi
    restore_skill "$CLAUDE_DESTINATION" "$STAGING_DIR/claude.previous" "$CLAUDE_INSTALLED" || rollback_failed=1
    restore_skill "$CODEX_DESTINATION" "$STAGING_DIR/codex.previous" "$CODEX_INSTALLED" || rollback_failed=1
    for ((index = CREATED_DIR_COUNT - 1; index >= 0; index--)); do
      rmdir "${CREATED_DIRS[index]}" 2>/dev/null || true
    done
  fi
  if [[ "$rollback_failed" == 1 ]]; then
    printf 'Installation rollback needs attention. Preserved recovery files at %s\n' "$STAGING_DIR" >&2
  else
    rm -rf "$STAGING_DIR"
  fi
}
trap cleanup EXIT

for parent in "${PARENTS[@]}"; do
  if [[ ! -d "$parent" ]]; then
    mkdir "$parent"
    CREATED_DIRS[CREATED_DIR_COUNT]="$parent"
    CREATED_DIR_COUNT=$((CREATED_DIR_COUNT + 1))
  fi
done

stage_skill() {
  local staged="$1"
  mkdir "$staged"
  cp "$SKILL_SOURCE" "$staged/SKILL.md"
  printf '%s\n%s\n' "$OWNER_MARKER" "$SOURCE_HASH" >"$staged/$MANIFEST_NAME"
  chmod 755 "$staged"
  chmod 644 "$staged/SKILL.md" "$staged/$MANIFEST_NAME"
}

commit_skill() {
  local destination="$1"
  local staged="$2"
  local backup="$3"
  local installed_flag="$4"

  preflight_skill "$destination"
  if [[ -d "$destination" ]]; then
    if [[ "$(file_hash "$destination/SKILL.md")" == "$SOURCE_HASH" ]]; then
      return 0
    fi
    mv "$destination" "$backup"
  fi
  printf -v "$installed_flag" '%s' 1
  mv "$staged" "$destination"
}

stage_skill "$STAGING_DIR/codex.new"
stage_skill "$STAGING_DIR/claude.new"
commit_skill "$CODEX_DESTINATION" "$STAGING_DIR/codex.new" "$STAGING_DIR/codex.previous" CODEX_INSTALLED
commit_skill "$CLAUDE_DESTINATION" "$STAGING_DIR/claude.new" "$STAGING_DIR/claude.previous" CLAUDE_INSTALLED
preflight_cli
if [[ ! -L "$CLI_DESTINATION" ]]; then
  ln -s "$CLI_BINARY" "$STAGING_DIR/cli.new"
  CLI_INSTALLED=1
  mv "$STAGING_DIR/cli.new" "$CLI_DESTINATION"
fi
# Retire only the exact link installed for this app. Custom commands survive.
if [[ -L "$PREVIOUS_CLI_DESTINATION" && "$(readlink "$PREVIOUS_CLI_DESTINATION")" == "$PREVIOUS_CLI_BINARY" ]]; then
  mv "$PREVIOUS_CLI_DESTINATION" "$STAGING_DIR/cli.previous"
fi
SUCCESS=1
printf 'Installed CLI link: %s\nInstalled Codex skill: %s\nInstalled Claude skill: %s\n' \
  "$CLI_DESTINATION" "$CODEX_DESTINATION" "$CLAUDE_DESTINATION"
