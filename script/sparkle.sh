#!/usr/bin/env bash

cc_sparkle_framework_path() {
  local root_dir="$1"
  local framework="$root_dir/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

  if [[ ! -d "$framework" ]]; then
    echo "Sparkle.framework not found at $framework" >&2
    return 1
  fi

  printf '%s\n' "$framework"
}

cc_sparkle_bin_dir() {
  local root_dir="$1"
  local bin_dir="$root_dir/.build/artifacts/sparkle/Sparkle/bin"

  if [[ ! -x "$bin_dir/generate_appcast" ]]; then
    echo "Sparkle generate_appcast not found at $bin_dir" >&2
    return 1
  fi

  printf '%s\n' "$bin_dir"
}

cc_binary_has_rpath() {
  local binary="$1"
  local rpath="$2"

  otool -l "$binary" | grep -Fq "$rpath"
}

cc_embed_sparkle() {
  local root_dir="$1"
  local app_bundle="$2"
  local app_binary="$3"
  local frameworks_dir="$app_bundle/Contents/Frameworks"
  local sparkle_src
  local rpath="@executable_path/../Frameworks"

  sparkle_src="$(cc_sparkle_framework_path "$root_dir")"

  mkdir -p "$frameworks_dir"
  rm -rf "$frameworks_dir/Sparkle.framework"
  ditto "$sparkle_src" "$frameworks_dir/Sparkle.framework"

  if ! cc_binary_has_rpath "$app_binary" "$rpath"; then
    codesign --remove-signature "$app_binary" >/dev/null 2>&1 || true
    install_name_tool -add_rpath "$rpath" "$app_binary"
  fi
}

cc_sign_sparkle() {
  local app_bundle="$1"
  local sparkle="$app_bundle/Contents/Frameworks/Sparkle.framework"
  local version_dir="$sparkle/Versions/Current"
  local xpc

  [[ -d "$sparkle" ]] || return 0
  if [[ "$CC_CODESIGN_IDENTITY" == "-" ]]; then
    return 0
  fi

  local -a codesign_args=(--force --sign "$CC_CODESIGN_IDENTITY" --options runtime --timestamp)

  if [[ -d "$version_dir/XPCServices" ]]; then
    for xpc in "$version_dir/XPCServices"/*.xpc; do
      [[ -d "$xpc" ]] || continue
      codesign "${codesign_args[@]}" "$xpc"
    done
  fi

  if [[ -d "$version_dir/Updater.app" ]]; then
    codesign "${codesign_args[@]}" "$version_dir/Updater.app"
  fi

  if [[ -x "$version_dir/Autoupdate" ]]; then
    codesign "${codesign_args[@]}" "$version_dir/Autoupdate"
  fi

  codesign "${codesign_args[@]}" "$sparkle"
}

cc_sparkle_private_key() {
  local root_dir="$1"

  if [[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
    printf '%s' "$SPARKLE_ED_PRIVATE_KEY"
    return 0
  fi

  if [[ -f "$root_dir/secrets/sparkle_eddsa" ]]; then
    tr -d '\n' <"$root_dir/secrets/sparkle_eddsa"
    return 0
  fi

  return 1
}

cc_write_appcast() {
  local root_dir="$1"
  local zip_path="$2"
  local download_prefix="$3"
  local private_key
  local bin_dir
  local archives_dir
  local appcast_path="$root_dir/dist/appcast.xml"

  if ! private_key="$(cc_sparkle_private_key "$root_dir")"; then
    rm -f "$appcast_path"
    echo "Sparkle appcast skipped; missing SPARKLE_ED_PRIVATE_KEY" >&2
    return 0
  fi

  bin_dir="$(cc_sparkle_bin_dir "$root_dir")"
  archives_dir="$(mktemp -d "${TMPDIR:-/tmp}/cc-appcast.XXXXXX")"
  mkdir -p "$root_dir/dist"
  cp "$zip_path" "$archives_dir/cc-macos.zip"

  # Reusing a feed can retain hardware requirements from an earlier build of the same version.
  # 0.4.0 changed bundle identity; earlier installs require manual replacement.
  if ! printf '%s' "$private_key" | "$bin_dir/generate_appcast" \
    --ed-key-file - \
    --download-url-prefix "$download_prefix" \
    --link "$CC_RELEASES_URL" \
    --maximum-deltas 0 \
    --informational-update-versions '<0.4.0' \
    -o "$archives_dir/appcast.xml" \
    "$archives_dir"; then
    rm -f "$appcast_path"
    rm -rf "$archives_dir"
    return 1
  fi

  if [[ ! -f "$archives_dir/appcast.xml" ]]; then
    rm -f "$appcast_path"
    rm -rf "$archives_dir"
    echo "generate_appcast did not write $appcast_path" >&2
    return 1
  fi
  mv "$archives_dir/appcast.xml" "$appcast_path"
  rm -rf "$archives_dir"
}
