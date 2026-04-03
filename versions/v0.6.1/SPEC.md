# SPEC v0.6.1

## Goal
- Fix broken remote collection UX and harden SSH connectivity for real operators.

## Requirements
- Support SSH password auth in the desktop host editor.
- Automatically register and save the SSH host fingerprint on first successful connection.
- Block later host-key mismatches.
- Provide an explicit SSH transport test action.
- Keep the portable self-contained desktop publish flow intact.

## Non-goals
- No persistent monitoring service in this step.
- No full credential-vault UX in this step.
- No analyzer overhaul in this step.
