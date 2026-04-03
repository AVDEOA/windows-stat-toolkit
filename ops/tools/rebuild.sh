#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
artifact_dir="$project_dir/artifacts/runtime-src"

rm -rf "$artifact_dir"
mkdir -p "$artifact_dir"
cp -R "$project_dir/app/src"/. "$artifact_dir"/
rm -rf "$artifact_dir/bin" "$artifact_dir/obj" "$artifact_dir/artifacts"
echo "rebuild OK: $artifact_dir"
