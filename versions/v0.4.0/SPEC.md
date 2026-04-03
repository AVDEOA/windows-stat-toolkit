# SPEC v0.4.0

## Goal
- Create the first runnable desktop exe concept for diagnosing Windows PCs over the network.

## Requirements
- Manage remote PCs through add/edit/delete UI.
- Connect over SSH and run remote PowerShell collection.
- Generate an AI-oriented summary bundle for `3/7/14/30 days` or `All time`.
- Enforce a maximum AI bundle size of 30 MB by trimming the noisiest blocks first.
- Generate a concise PC report with configuration and issue summary.
- Generate separate human-readable reports for individual diagnostic blocks.
- Send Telegram alerts for offline hosts, low disk space, and newly seen critical event categories while monitoring is active.

## Non-goals
- No direct OpenAI or ChatGPT submission.
- No Windows Service agent yet.
- No password-based SSH UX in this first concept.
