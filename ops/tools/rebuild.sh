#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
artifact_dir="$project_dir/artifacts/runtime-src"
desktop_artifact_dir="$project_dir/artifacts/runtime-desktop-src"

rm -rf "$artifact_dir"
rm -rf "$desktop_artifact_dir"
mkdir -p "$artifact_dir"
mkdir -p "$desktop_artifact_dir"
cp -R "$project_dir/app/src"/. "$artifact_dir"/
rm -rf "$artifact_dir/bin" "$artifact_dir/obj" "$artifact_dir/artifacts" "$artifact_dir/state"
cp -R "$project_dir/app/desktop/WindowsStatToolkit.Desktop"/. "$desktop_artifact_dir"/
rm -rf "$desktop_artifact_dir/bin" "$desktop_artifact_dir/obj" "$desktop_artifact_dir/.vs"
echo "rebuild OK: $artifact_dir and $desktop_artifact_dir"
