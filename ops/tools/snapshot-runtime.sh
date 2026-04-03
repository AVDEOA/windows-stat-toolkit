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
if [[ ! -d "$source_dir" ]]; then
  echo "snapshot FAIL: source runtime folder not found: $source_dir" >&2
  exit 1
fi
mkdir -p "$(dirname "$target_dir")"
if [[ -e "$target_dir" ]]; then
  echo "snapshot SKIP: target already exists: $target_dir"
  exit 0
fi
mkdir -p "$target_dir"
cp -a "$source_dir"/. "$target_dir"/
echo "snapshot OK: $source_dir -> $target_dir"
