#!/usr/bin/env bash
set -euo pipefail

APP_NAME="cc:"
APP_BUNDLE_NAME="cc"
APP_EXECUTABLE_NAME="cc"
BUNDLE_ID="work.hayashigoto.cc"
ZIP_URL="https://github.com/hayashiii-ghub/cc/releases/latest/download/cc-macos.zip"
TMP_DIR="$(mktemp -d)"
ZIP_PATH="$TMP_DIR/cc-macos.zip"
EXTRACT_DIR="$TMP_DIR/extract"
INSTALL_HOME="${CC_INSTALL_HOME:-$HOME}"
INSTALL_HOME="${INSTALL_HOME%/}"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

validate_app() {
  local app="$1"
  local info_plist="$app/Contents/Info.plist"
  local version

  [[ -d "$app" && ! -L "$app" && -f "$info_plist" ]] || return 1
  [[ "$(plutil -extract CFBundleIdentifier raw "$info_plist" 2>/dev/null)" == "$BUNDLE_ID" ]] || return 1
  [[ "$(plutil -extract CFBundleExecutable raw "$info_plist" 2>/dev/null)" == "$APP_EXECUTABLE_NAME" ]] || return 1
  [[ -x "$app/Contents/MacOS/$APP_EXECUTABLE_NAME" ]] || return 1
  version="$(plutil -extract CFBundleShortVersionString raw "$info_plist" 2>/dev/null)"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  codesign --verify --deep --strict "$app"
}

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

choose_install_dir() {
  if [[ -n "${CC_INSTALL_DIR:-}" ]]; then
    printf '%s\n' "$CC_INSTALL_DIR"
    return
  fi

  local directory
  for directory in /Applications "$INSTALL_HOME/Applications"; do
    if [[ -d "$directory/$APP_BUNDLE_NAME.app" ]]; then
      printf '%s\n' "$directory"
      return
    fi
  done
  if [[ -w /Applications ]]; then
    printf '%s\n' /Applications
  else
    printf '%s\n' "$INSTALL_HOME/Applications"
  fi
}

# A subshell keeps backup paths in scope for unexpected command failures.
install_app() (
  local source_app="$1"
  local destination_app="$2"
  local install_dir="$(dirname "$destination_app")"
  local staged_app="$install_dir/.$APP_BUNDLE_NAME.app.new.$$"
  local backup_app="$install_dir/.$APP_BUNDLE_NAME.app.backup.$$"
  local cli_destination="$INSTALL_HOME/.local/bin/cc:"
  local cli_binary="$destination_app/Contents/Helpers/cc:"
  local cli_managed=0
  local app_installed=0
  local success=0
  local use_sudo=0

  if [[ ! -w "$install_dir" ]]; then
    use_sudo=1
    echo "Installing to $install_dir requires administrator permission."
  fi

  run_install() {
    if (( use_sudo )); then
      sudo "$@"
    else
      "$@"
    fi
  }

  rollback_install() {
    local rollback_failed=0
    if [[ "$success" != 1 ]]; then
      if [[ "$app_installed" == 1 ]]; then
        run_install rm -rf "$destination_app" || rollback_failed=1
      fi
      if [[ -e "$backup_app" ]]; then
        if [[ ! -e "$destination_app" && ! -L "$destination_app" ]]; then
          run_install mv "$backup_app" "$destination_app" || rollback_failed=1
        else
          rollback_failed=1
        fi
      fi
    else
      run_install rm -rf "$backup_app" || rollback_failed=1
    fi
    run_install rm -rf "$staged_app" || rollback_failed=1
    if [[ "$rollback_failed" == 1 ]]; then
      printf 'Installation recovery needs attention. Preserved backup: %s\n' "$backup_app" >&2
    fi
  }

  local existing
  if [[ -e "$destination_app" || -L "$destination_app" ]]; then
    [[ -d "$destination_app" && ! -L "$destination_app" \
        && "$(plutil -extract CFBundleIdentifier raw "$destination_app/Contents/Info.plist" 2>/dev/null)" == "$BUNDLE_ID" ]] \
      || { echo "Preserving an unrelated app or symlink: $destination_app" >&2; exit 1; }
  fi
  for existing in "$staged_app" "$backup_app"; do
    [[ ! -e "$existing" && ! -L "$existing" ]] \
      || { echo "Preserving an existing recovery path: $existing" >&2; exit 1; }
  done

  # The existing exact helper link keeps its inode across app updates. Custom
  # commands are not part of app installation and remain untouched.
  if [[ -L "$cli_destination" && "$(readlink "$cli_destination")" == "$cli_binary" ]]; then
    cli_managed=1
    [[ ! -L "$INSTALL_HOME/.local" && ! -L "$INSTALL_HOME/.local/bin" ]] \
      || { echo "Preserving a symlinked CLI directory." >&2; exit 1; }
    [[ -x "$source_app/Contents/Helpers/cc:" ]] \
      || { echo "The archive lacks the CLI required by the existing installation." >&2; exit 1; }
  fi
  trap 'status=$?; rollback_install; exit "$status"' EXIT
  trap 'exit 130' HUP INT TERM

  run_install ditto "$source_app" "$staged_app"
  validate_app "$staged_app" \
    || { echo "Staged cc.app failed validation" >&2; exit 1; }
  if (( cli_managed )); then
    [[ -x "$staged_app/Contents/Helpers/cc:" ]] \
      || { echo "The archive lacks the CLI required by the existing installation." >&2; exit 1; }
  fi

  if [[ -e "$destination_app" ]]; then
    run_install mv "$destination_app" "$backup_app"
  fi
  app_installed=1
  run_install mv "$staged_app" "$destination_app"
  validate_app "$destination_app" \
    || { echo "Installed cc.app failed validation" >&2; exit 1; }
  run_install xattr -dr com.apple.quarantine "$destination_app" 2>/dev/null || true
  success=1
)

INSTALL_DIR="$(choose_install_dir)"
INSTALL_DIR="${INSTALL_DIR%/}"
[[ "$INSTALL_DIR" == /* && ! -L "$INSTALL_DIR" ]] \
  || { echo "CC_INSTALL_DIR must be an absolute directory, not a symlink." >&2; exit 1; }
[[ "$INSTALL_HOME" == /* && -d "$INSTALL_HOME" && ! -L "$INSTALL_HOME" ]] \
  || { echo "CC_INSTALL_HOME must be an existing absolute directory." >&2; exit 1; }
DESTINATION_APP="$INSTALL_DIR/$APP_BUNDLE_NAME.app"

if [[ -n "${CC_ZIP_PATH:-}" ]]; then
  echo "Using local $APP_NAME archive..."
  cp "$CC_ZIP_PATH" "$ZIP_PATH"
else
  echo "Downloading latest $APP_NAME..."
  curl -L --fail -A "Mozilla/5.0" -o "$ZIP_PATH" "$ZIP_URL"
fi
mkdir -p "$EXTRACT_DIR"
ditto -x -k "$ZIP_PATH" "$EXTRACT_DIR"
SOURCE_APP="$EXTRACT_DIR/$APP_BUNDLE_NAME.app"
validate_app "$SOURCE_APP" \
  || { echo "Archive did not contain a valid cc.app" >&2; exit 1; }

if [[ "${CC_SKIP_STOP:-0}" != 1 ]]; then
  echo "Stopping running $APP_NAME..."
  if [[ "$(plutil -extract CFBundleIdentifier raw "$DESTINATION_APP/Contents/Info.plist" 2>/dev/null)" == "$BUNDLE_ID" \
      && "$(plutil -extract CFBundleExecutable raw "$DESTINATION_APP/Contents/Info.plist" 2>/dev/null)" == "$APP_EXECUTABLE_NAME" ]]; then
    stop_cc_app "$DESTINATION_APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
  fi
fi
mkdir -p "$INSTALL_DIR"
echo "Installing to $DESTINATION_APP..."
install_app "$SOURCE_APP" "$DESTINATION_APP"
if [[ "${CC_SKIP_OPEN:-0}" != 1 ]]; then
  open "$DESTINATION_APP"
fi
echo "Updated $APP_NAME at $DESTINATION_APP"
