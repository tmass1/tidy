# Publishing the Tidy site

Production is `https://tidy-app.tommymassaro.com`. There is no staging site. The site is served by a Cloudflare Worker configured in `wrangler.jsonc`. Ask Tommy to name production as the target for each deploy.

Run `python3 scripts/deploy-production.py --check` first and show Tommy its complete output. It reads Cloudflare's active deployment, checks that this branch contains the live commit, lists commits this deploy would add, and checks the public and hidden URLs. It does not build or deploy. After Tommy approves that specific deploy, run `python3 scripts/deploy-production.py`. The command runs the tests in `tests/` (plus `swift test` once the package has Swift tests; today it has none), builds the release app with `swift build -c release`, and asks you to type `deploy`. `--yes` skips the terminal prompt only when Tommy has already approved in chat; it never skips a safety check. Never use raw `wrangler deploy` for production.

The current older deployment has no commit note. On November 3, the live home page exactly matched the copy at commit `ce3d425`, and the Cloudflare deployment timestamp was about one minute after that commit. The script recognizes that one deployment by ID and page checksum, and labels the commit attribution as **inferred**. Any different unmarked deployment stops until its commit is established by checking Cloudflare history and the live files. After verifying the commit, pass `--live <commit>` to both `--check` and the approved deploy command. `--live` is refused when Cloudflare already recorded a commit, and the named commit must exist in this checkout. Future deploys record `commit=` and `branch=` in Cloudflare's deployment message.

## If it stops

- **Uncommitted site or deploy file:** commit the intended change first, or remove it if it should not ship. The command checks the whole checkout because it also builds the app. Never hide a change to get past the check.
- **No recorded live commit:** use Cloudflare's deployment history and the live site to identify the commit; pass the verified commit with `--live <commit>`. Do not guess silently.
- **Live commit absent here:** push the branch holding it and fetch it on this computer.
- **Missing live work:** merge the branch containing the listed live commits. Re-run the check after the merge.
- **Public or hidden URL fails:** fix the site or access behavior before deploying. Right after a deploy the check retries for up to 90 seconds, because Cloudflare takes a moment to serve a new version everywhere, and prints "Not live everywhere yet" while it waits. If it still fails, the deploy has gone out: look at the site and ask Tommy whether to roll back. Only the site's pages and assets should load. Unknown paths and repository or build files should return 404.
- **Remote warning or side branch:** confirm the situation with Tommy before deploying. After a side-branch deploy, merge it into `main` so the release branch includes live work.

The command prints the previous Cloudflare version ID and a `wrangler rollback <version-id> --name tidy-app` command. Rollback changes production immediately, so ask Tommy which target he wants and get approval before running it. After a deploy, write a release note, merge a side branch into `main`, and push only when Tommy says to.
