# Publishing the Tidy site

Production is `https://tidy-app.tommymassaro.com`. There is no staging site. The site is served by a Cloudflare Worker configured in `wrangler.jsonc`. Ask Tommy to name production as the target for each deploy.

Run `python3 scripts/deploy-production.py --check` first and show Tommy its complete output. It reads Cloudflare's active deployment, checks that this branch contains the live commit, lists commits this deploy would add, and checks the public and hidden URLs. It does not build or deploy. After Tommy approves that specific deploy, run `python3 scripts/deploy-production.py`. The command runs `swift test`, builds the release app with `swift build -c release`, and asks you to type `deploy`. `--yes` skips the terminal prompt only when Tommy has already approved in chat; it never skips a safety check. Never use raw `wrangler deploy` for production.

The current older deployment has no commit note. On November 3, the live home page exactly matched the copy at commit `ce3d425`, and the Cloudflare deployment timestamp was about one minute after that commit. The script recognizes that one deployment by ID and page checksum, and labels the commit attribution as **inferred**. Any different unmarked deployment stops until its commit is established by checking Cloudflare history and the live files. Future deploys record `commit=` and `branch=` in Cloudflare's deployment message.

## If it stops

- **Uncommitted site or deploy file:** commit the intended change first, or remove it if it should not ship. Never hide a change to get past the check.
- **No recorded live commit:** use Cloudflare's deployment history and the live site to identify the commit; add a reviewed one-time legacy mapping. Do not guess silently.
- **Live commit absent here:** push the branch holding it and fetch it on this computer.
- **Missing live work:** merge the branch containing the listed live commits. Re-run the check after the merge.
- **Public or hidden URL fails:** fix the site or access behavior before deploying. Only the home page and assets should load. Unknown paths and repository or build files should return 404.
- **Remote warning or side branch:** confirm the situation with Tommy before deploying. After a side-branch deploy, merge it into `main` so the release branch includes live work.

The command prints the previous Cloudflare version ID and a `wrangler rollback <version-id> --name tidy-app` command. Rollback changes production immediately, so ask Tommy which target he wants and get approval before running it. After a deploy, write a release note, merge a side branch into `main`, and push only when Tommy says to.
