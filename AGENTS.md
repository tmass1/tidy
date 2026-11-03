# Tidy: agent instructions

Codex and Claude work on this project in separate worktrees. Read `docs/agent-workflow.md` before making changes. Project instructions are in `CLAUDE.md`; they apply to Codex too.

## Production site deploys

Production is the only Cloudflare target. Before every deploy, ask Tommy to name the target and wait for his answer. Deploy production only with `python3 scripts/deploy-production.py`, after running `python3 scripts/deploy-production.py --check` and showing Tommy its complete output, including additions and reminders. Never bypass a stop or run `wrangler deploy` directly for production. An approval applies to one deploy only. See `docs/production-deploy.md`.
