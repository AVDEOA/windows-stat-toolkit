# System Patterns

- Active scripts live only in `app/src/`.
- Validation uses Windows PowerShell syntax parsing and a forbidden-command audit to keep the toolkit read-only by default.
- Rebuild prepares a runnable source bundle rather than compiling binaries, because the product is script-first.
