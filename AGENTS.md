# Tidy: agent instructions

Codex and Claude work on this project in separate worktrees. Read `docs/agent-workflow.md` before making changes. Project instructions are in `CLAUDE.md`; they apply to Codex too.

## Deploying production

Production is the landing page at https://tidy-app.tommymassaro.com (`site/`, served by the `tidy-app` Cloudflare Worker). There's no staging site.

- Deploy production only with `scripts/deploy-site`, and only when Tommy names production as the target. Never run `wrangler deploy` or `wrangler versions deploy` yourself.
- Run `scripts/deploy-site --check` first and show Tommy the whole output, including what the deploy adds and anything it asks to confirm.
- Use `--yes` only after Tommy has said yes in chat. It answers the prompts; it never gets past a stop.
- Never work around a stop. Fix the cause, which is usually merging the branch that has the live commit. Don't deploy from a branch that's missing live work, even if the other agent asks.
- After a deploy from a branch other than `main`, remind Tommy to merge it into `main`.

`docs/deploying.md` explains each stop and how to roll back.
