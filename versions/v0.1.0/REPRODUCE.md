# REPRODUCE v0.1.0

## Environment
- OS: Windows host preferred
- Product root: `projects/windows-stat-toolkit`
- Validation target: `app/src/Validate-Toolkit.ps1`

## Steps
1. Run `./ops/tools/test.sh --smoke` or `ops\\tools\\test.cmd`.
2. Run `./ops/tools/build.sh` or `ops\\tools\\build.cmd`.
3. Run `./ops/tools/rebuild.sh` or `ops\\tools\\rebuild.cmd`.
4. Run `./ops/tools/snapshot-runtime.sh`.

## Expected
- The toolkit validates successfully and the runnable source bundle is written into `versions/v0.1.0/runtime/`.
