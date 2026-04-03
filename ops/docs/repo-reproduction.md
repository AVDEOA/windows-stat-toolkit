# Repo Reproduction

## Environment

- Product root: `projects/windows-stat-toolkit`
- Runtime: Windows PowerShell scripts
- Main validator: `app/src/Validate-Toolkit.ps1`
- Main analyzer baseline: `app/src/AnalizeV9.ps1`

## Verification Paths

1. Run `./ops/tools/test.sh --smoke` or `ops\\tools\\test.cmd`.
2. Run `./ops/tools/build.sh` or `ops\\tools\\build.cmd`.
3. Run `./ops/tools/rebuild.sh` or `ops\\tools\\rebuild.cmd`.
4. Run `./ops/tools/snapshot-runtime.sh`.

## Optional Host Run

If you want a real report collection on a Windows host, run:

- `powershell.exe -ExecutionPolicy Bypass -File app\src\Run-All-Stat-Collection.ps1`
- `powershell.exe -ExecutionPolicy Bypass -File app\src\AnalizeV9.ps1`
