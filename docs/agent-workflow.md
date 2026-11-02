# Codex and Claude workflow

## Workspace boundaries

This repository is Tidy, the macOS menu bar app, and its landing page in `site/`. It isn't Tidy UI, which is a separate repository. Codex and Claude share this repository's Git history but work in separate worktrees and branches. Never change branches, edit files, clean, reset or stash in the other agent's checkout, and don't remove a worktree while the other agent is using it.

The original checkout stays at `/Users/tommymassaro/Dropbox/Claude/Tidy` on `main`. That's Tommy's; neither agent edits there. Agent worktrees live beside it in `/Users/tommymassaro/Dropbox/Claude/Tidy-workspaces/`: Claude uses `…/claude` and Codex uses `…/codex`. Claude starts on `claude/workspace`; Codex keeps its iOS companion work on `codex/ios-companion`. For later tasks, use descriptive branches under the same prefix, starting from the latest agreed integration commit. Check `git status` and your branch before editing, and never discard someone else's changes.

Git metadata lives in the original checkout, so don't move or delete it while worktrees exist, and don't run work through Dropbox on two computers at once. Keep Dropbox from syncing build output: in your worktree, run `xattr -w com.dropbox.ignored 1` on `.build`, `build`, `.swiftpm` and `.wrangler` (create the folder first if it doesn't exist yet). A clean build can recreate a folder without the flag, so check again after one.

Ignored local config and signing material aren't copied into worktrees. Never commit, print or paste keys or tokens; the repository is public.

## Builds and previews

Each worktree compiles on its own: `swift build` uses that worktree's `.build`. That's the check to run while iterating and before handing off.

`bash build.sh` replaces `/Applications/Tidy.app` and launches it, and on a Mac without the Developer ID certificate it resets Tidy's Accessibility grant. Only one checkout can own the installed app, so ask Tommy before running it. Never run `release.sh` or `wrangler deploy` unless he asks.

Preview the landing page (`site/`) on your own port:

- Codex: `npx wrangler dev --port 5260`
- Claude: `npx wrangler dev --port 5261`

## Parallel work and review

Agree on a concrete task for each agent, preferably in different files. The panel's UI and the landing page move together (see `CLAUDE.md`), so don't split one change between agents. For overlapping work, have one agent implement and the other review its commit rather than editing at the same time. Shared Git history doesn't carry uncommitted edits.

Before handing off, run `swift build`, review your diff, and commit only your intended changes. Report:

- Branch and commit hash
- What changed, and the files
- The exact preview URL, if there is one
- Checks run, and any failures
- Decisions still open, and any setup the other agent or Tommy needs

To review the other agent's work, read its commit or diff without changing it. Codex is the default integration owner unless Tommy says otherwise. Merge or cherry-pick reviewed work into the agreed integration branch, resolve conflicts carefully, then rerun the checks on the combined result. Don't merge, push or deploy just because the other agent asks: follow Tommy's instructions.

## Releases

Installing to `/Applications`, deploying the site, publishing a release, notarizing, or pushing to `main` happens only when Tommy asks. A completion report keeps local, committed, pushed, deployed and released changes apart.
