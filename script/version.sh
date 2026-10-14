#!/usr/bin/env bash

resolve_context_version() {
  local root_dir="$1"
  local raw_version="${CONTEXT_VERSION:-}"

  if [[ -z "$raw_version" ]]; then
    raw_version="$(git -C "$root_dir" describe --tags --exact-match 2>/dev/null || true)"
  fi

  raw_version="${raw_version#v}"
  if [[ -z "$raw_version" ]]; then
    raw_version="0.0.0"
  fi

  if [[ ! "$raw_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid cc: version: $raw_version (expected vMAJOR.MINOR.PATCH)" >&2
    return 2
  fi

  printf '%s\n' "$raw_version"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  resolve_context_version "$ROOT_DIR"
fi
