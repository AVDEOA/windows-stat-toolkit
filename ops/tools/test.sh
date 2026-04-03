#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "--smoke" ]; then
  echo "test FAIL: use the Windows wrapper for PowerShell validation: projects\\windows-stat-toolkit\\ops\\tools\\test.cmd" >&2
  exit 1
fi

echo "test FAIL: use the Windows wrapper for PowerShell validation: projects\\windows-stat-toolkit\\ops\\tools\\test.cmd" >&2
exit 1
