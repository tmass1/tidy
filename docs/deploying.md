# Deploying the site

The landing page (`site/`) goes live at https://tidy-app.tommymassaro.com through one command:

```bash
scripts/deploy-site --check    # look first: every check, no build, no deploy
scripts/deploy-site            # the real thing
```

Its job is to stop one mistake: deploying from a branch, checkout or computer that doesn't have work
that's already live. Cloudflare would replace the whole site with whatever you send, so anything
missing would quietly disappear from the site.

## What it does

1. **Uncommitted changes.** Stops if anything in `site/`, `wrangler.jsonc` or the script itself is changed,
   new, or sitting in `site/` while ignored by git (like a `.DS_Store`). What goes live is always a commit.
2. **What's live.** Asks Cloudflare which version is live and reads the note on it, which names the commit
   and branch it came from. Deploys from before this script have no note, so for those it compares the live
   files with every past version of `site/` and uses the one that matches exactly. It doesn't matter who
   deployed last: you, Claude or Codex.
3. **Live work on this branch.** Stops if this branch doesn't have the live commit.
4. **Things to confirm.** Asks before going on if you're not on `main`, if your commits aren't pushed, or if
   GitHub has commits you don't have.
5. **Checks.** Runs the script's tests, checks that every image, font and script the page uses exists, checks
   the site isn't also published at a workers.dev or preview address, and does a dry-run build.
6. **What it adds.** Lists the commits and files that change since what's live, then asks you to type `deploy`.
7. **Deploy**, with the commit and branch recorded on the new Cloudflare version.
8. **Checks the live site.** Every file on the site is the version just deployed, and private paths
   (`.DS_Store`, `wrangler.jsonc`, `.git/config`, `CLAUDE.md`, the script) still return "not found". The whole
   site is public; nothing on it needs a sign-in.
9. **Undo and to-do.** Prints the rollback command and what's left: a release note, merging into `main` if you
   deployed from another branch, and pushing.

`--check` runs steps 1 to 6 without the dry-run build and stops before deploying. `--yes` answers the
questions in steps 4 and 6 for you; agents use it only after Tommy has said yes in chat. Nothing gets past
a stop, with or without `--yes`.

Claude can't run a raw `wrangler deploy` in this project: a hook (`.claude/settings.json`) blocks it and points
here. Codex follows the same rule from `AGENTS.md`.

## The stops, and what to do

**There are uncommitted changes in files the site uses.** Commit them, or undo them, and run it again. A line
starting `!!` is a file git ignores that would still be uploaded: delete it.

**Couldn't ask Cloudflare what's live.** Usually you're signed out of Wrangler. Run `wrangler whoami`, then
`wrangler login` if needed.

**The live site is split between versions.** Someone started a gradual rollout in Cloudflare. Finish or undo
it there first.

**The live commit isn't in this checkout.** The site was deployed from somewhere whose work isn't here. Run
`git fetch origin`. If it's still missing, push it from the computer or checkout it came from, then fetch.

**Can't tell which commit is live.** The live version has no note and doesn't match any version of `site/`
here. Fetch first. If that doesn't help, work out which commit was deployed (the deploy times in
`wrangler deployments list` next to `git log -- site` usually make it clear) and name it:
`scripts/deploy-site --check --live-commit <commit>`.

**This branch is missing work that's live.** The important one. It lists the live commits you'd take off the
site and the branches that have them. Merge one of those branches (usually `main`) into yours and run it again.

**The deploy script's tests failed / The page points at files that don't exist / wrangler.jsonc would publish
the site somewhere extra / The production build failed.** Something in the project is broken. Fix it and
commit before deploying.

**This needs a yes and there's no terminal to ask in.** It was run where it can't ask you, for example by an
agent. Run it in Terminal yourself, or tell the agent yes in chat so it can add `--yes`.

**Stopped at your answer.** You said no. Nothing changed.

## Rolling back

Every deploy ends by printing the exact command, with the version that was live before:

```bash
wrangler rollback <previous-version-id> --message "Roll back to <commit>"
```

That puts the old version back in seconds, without a build. `wrangler deployments list` shows older versions if
you need to go further back. After a rollback, fix the problem on a branch and deploy again with
`scripts/deploy-site`. The rolled-back version keeps its note, so the check still knows what's live.

## Tests

```bash
python3 -m unittest discover -s scripts/tests
```

They use throwaway git repos and a fake Cloudflare, so they never touch the real site.
