#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/../.." && pwd)"
version="${1:-}"
if [[ -z "$version" && -f "$project_dir/VERSION" ]]; then
  version="$(tr -d '[:space:]' < "$project_dir/VERSION")"
fi
if [[ -z "$version" ]]; then
  echo "snapshot FAIL: version is required or VERSION must exist" >&2
  exit 1
fi
source_dir="$project_dir/artifacts/runtime-src"
target_dir="$project_dir/versions/v${version}/runtime/src"
desktop_source_dir="$project_dir/artifacts/runtime-desktop-src"
desktop_target_dir="$project_dir/versions/v${version}/runtime/desktop-src"
desktop_publish_dir="$project_dir/artifacts/desktop-publish"
desktop_publish_target_dir="$project_dir/versions/v${version}/runtime/desktop-publish"
if [[ ! -d "$source_dir" ]]; then
  echo "snapshot FAIL: source runtime folder not found: $source_dir" >&2
  exit 1
fi
mkdir -p "$(dirname "$target_dir")"
rm -rf "$target_dir" "$desktop_target_dir" "$desktop_publish_target_dir"
mkdir -p "$target_dir"
cp -a "$source_dir"/. "$target_dir"/
if [[ -d "$desktop_source_dir" ]]; then
  mkdir -p "$desktop_target_dir"
  cp -a "$desktop_source_dir"/. "$desktop_target_dir"/
fi
if [[ -d "$desktop_publish_dir" ]]; then
  mkdir -p "$desktop_publish_target_dir"
  cp -a "$desktop_publish_dir"/. "$desktop_publish_target_dir"/
fi
echo "snapshot OK: $source_dir -> $target_dir"
