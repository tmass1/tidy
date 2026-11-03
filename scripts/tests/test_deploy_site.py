"""Tests for scripts/deploy-site's checks and the raw-deploy hook.

Each test builds a throwaway git repo (with a bare "origin") and fakes Cloudflare and the live
site, so nothing here touches the network or production.
Run: python3 -m unittest discover -s scripts/tests
"""
from __future__ import annotations

import contextlib
import importlib.machinery
import importlib.util
import io
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent.parent


def load(name: str, path: Path):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


ds = load("deploy_site", SCRIPTS / "deploy-site")
hook = load("block_raw_deploy", SCRIPTS / "hooks" / "block-raw-deploy")


def git(path: Path, *args: str) -> str:
    return subprocess.run(["git", "-c", "user.name=Test", "-c", "user.email=test@example.com",
                           "-c", "commit.gpgsign=false", "-c", "init.defaultBranch=main", "-C", str(path), *args],
                          check=True, capture_output=True, text=True).stdout.strip()


class FakeCloudflare:
    def __init__(self, note: str | None, version: str = "v-live"):
        self.note, self.version = note, version

    def live_version(self):
        return self.version, self.note


def site_fetcher(repo, rev: str, hidden_visible: bool = False):
    """A fake live site serving `rev`'s site/ files."""
    served = {ds.url_for(p): git(repo.path, "cat-file", "blob", b).encode() for p, b in repo.site_files(rev).items()}

    def fetch(path: str):
        if path in served:
            return 200, served[path]
        if hidden_visible and path in ds.HIDDEN_PATHS:
            return 200, b"secret"
        return 404, b""
    return fetch


class RepoCase(unittest.TestCase):
    """origin and main have c1 → c2 (site change) → c3 (non-site change); branch `old` is at c1."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.origin = root / "origin.git"
        self.path = root / "work"
        git(root, "init", "--bare", "-q", str(self.origin))
        git(root, "init", "-q", str(self.path))
        (self.path / "site").mkdir()
        (self.path / ".gitignore").write_text(".DS_Store\n")
        self.write("site/index.html", '<link href="style.css"><img src="assets/a.png">')
        self.write("site/style.css", "body{}")
        (self.path / "site/assets").mkdir()
        self.write("site/assets/a.png", "png")
        self.c1 = self.commit("First site")
        self.write("site/index.html", '<link href="style.css"><img src="assets/a.png"><p>v2</p>')
        self.c2 = self.commit("Second site")
        self.write("README.md", "notes")
        self.c3 = self.commit("Docs only")
        git(self.path, "remote", "add", "origin", str(self.origin))
        git(self.path, "push", "-q", "-u", "origin", "main")
        git(self.path, "branch", "old", self.c1)
        self.repo = ds.Repo(self.path)

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, rel: str, text: str):
        (self.path / rel).write_text(text)

    def commit(self, message: str) -> str:
        git(self.path, "add", "-A")
        git(self.path, "commit", "-q", "-m", message)
        return git(self.path, "rev-parse", "HEAD")


class LiveCommit(RepoCase):
    def test_reads_the_note_on_the_live_version(self):
        sha, how, version = ds.find_live_commit(self.repo, FakeCloudflare(ds.note_for(self.c2, "main")), None)
        self.assertEqual((sha, version), (self.c2, "v-live"))
        self.assertIn("recorded", how)

    def test_note_for_a_commit_this_checkout_lacks_stops(self):
        with self.assertRaises(ds.Stop) as stop:
            ds.find_live_commit(self.repo, FakeCloudflare(f"commit={'a' * 40} branch=x"), None)
        self.assertIn("isn't in this checkout", stop.exception.title)
        self.assertIn("git fetch", stop.exception.detail)

    def test_without_a_note_it_matches_the_live_files(self):
        fetch = site_fetcher(self.repo, self.c3)
        sha, how, _ = ds.find_live_commit(self.repo, FakeCloudflare(None), None, fetcher=fetch)
        self.assertEqual(sha, self.c2, "c2 and c3 share a site/, so the earliest one is the live commit")
        self.assertIn("matched", how)

    def test_cloudflares_injected_analytics_beacon_is_ignored(self):
        plain = site_fetcher(self.repo, self.c2)
        beacon = b'<script defer src="https://static.cloudflareinsights.com/beacon.min.js/v1" data-cf-beacon="{}"></script>\n'

        def fetch(path):
            code, body = plain(path)
            return (code, body + beacon) if path == "/" else (code, body)
        sha, _, _ = ds.find_live_commit(self.repo, FakeCloudflare(None), None, fetcher=fetch)
        self.assertEqual(sha, self.c2)

    def test_without_a_note_or_a_match_it_stops_and_explains(self):
        with self.assertRaises(ds.Stop) as stop:
            ds.find_live_commit(self.repo, FakeCloudflare(None), None,
                                fetcher=lambda p: (200, b"something else") if p == "/" else (404, b""))
        self.assertIn("Can't tell", stop.exception.title)
        self.assertIn("--live-commit", stop.exception.detail)

    def test_a_named_commit_wins(self):
        sha, how, _ = ds.find_live_commit(self.repo, FakeCloudflare(None), self.c1[:8])
        self.assertEqual(sha, self.c1)
        self.assertIn("--live-commit", how)

    def test_an_unknown_named_commit_stops(self):
        with self.assertRaises(ds.Stop):
            ds.find_live_commit(self.repo, FakeCloudflare(None), "nope123")

    def test_note_round_trip(self):
        note = ds.note_for(self.c2, "claude/" + "x" * 80)
        self.assertLessEqual(len(note), 100)
        self.assertEqual(ds.NOTE.search(note).group(1), self.c2)


class MissingLiveWork(RepoCase):
    def test_a_branch_with_the_live_commit_passes(self):
        ds.check_contains_live(self.repo, self.c2)

    def test_a_branch_missing_live_work_stops_and_names_it(self):
        git(self.path, "checkout", "-q", "old")
        with self.assertRaises(ds.Stop) as stop:
            ds.check_contains_live(self.repo, self.c2)
        self.assertIn("missing work that's live", stop.exception.title)
        self.assertIn("Second site", stop.exception.detail)
        self.assertIn("main", stop.exception.detail)
        self.assertNotIn("First site", stop.exception.detail)


class Uncommitted(RepoCase):
    def test_clean_passes(self):
        ds.check_clean(self.repo)

    def test_changes_outside_the_site_are_fine(self):
        self.write("README.md", "edited")
        ds.check_clean(self.repo)

    def test_a_modified_site_file_stops(self):
        self.write("site/style.css", "body{color:red}")
        with self.assertRaises(ds.Stop) as stop:
            ds.check_clean(self.repo)
        self.assertIn("site/style.css", stop.exception.detail)

    def test_a_new_site_file_stops(self):
        self.write("site/new.html", "hi")
        with self.assertRaises(ds.Stop):
            ds.check_clean(self.repo)

    def test_an_ignored_file_in_site_stops(self):
        self.write("site/.DS_Store", "junk")
        with self.assertRaises(ds.Stop) as stop:
            ds.check_clean(self.repo)
        self.assertIn("!! site/.DS_Store", stop.exception.detail)


class Confirmations(RepoCase):
    def test_pushed_main_needs_nothing(self):
        self.assertEqual(ds.confirmations(self.repo, fetched=True), [])

    def test_another_unpushed_branch_asks(self):
        git(self.path, "checkout", "-q", "-b", "feature")
        self.write("README.md", "feature")
        self.commit("Feature work")
        asks = " ".join(ds.confirmations(self.repo, fetched=True))
        self.assertIn("feature, not main", asks)
        self.assertIn("hasn't been pushed", asks)

    def test_an_unpushed_detached_commit_asks(self):
        self.write("README.md", "detached")
        self.commit("Local only")
        git(self.path, "checkout", "-q", "--detach")
        asks = " ".join(ds.confirmations(self.repo, fetched=True))
        self.assertIn("detached checkout", asks)
        self.assertIn("This commit hasn't been pushed", asks)

    def test_a_pushed_detached_commit_only_asks_about_the_branch(self):
        git(self.path, "checkout", "-q", "--detach")
        self.assertEqual(len(ds.confirmations(self.repo, fetched=True)), 1)

    def test_unpushed_commits_ask(self):
        self.write("README.md", "more")
        self.commit("Local only")
        self.assertIn("aren't pushed", " ".join(ds.confirmations(self.repo, fetched=True)))

    def test_commits_on_the_remote_ask(self):
        git(self.path, "reset", "-q", "--hard", self.c2)
        self.assertIn("you don't have", " ".join(ds.confirmations(self.repo, fetched=True)))

    def test_a_failed_fetch_asks(self):
        self.assertIn("Couldn't fetch", " ".join(ds.confirmations(self.repo, fetched=False)))


class SiteChecks(RepoCase):
    def test_references_that_exist_pass(self):
        self.assertEqual(ds.site_references(self.path / "site"), [])

    def test_a_missing_reference_is_found(self):
        self.write("site/index.html", '<img src="assets/gone.png"><a href="https://x.com"><a href="#top">'
                                      '<script>/* e.g. <a href="/Example.dmg"> */</script><!-- <img src="old.png"> -->')
        self.assertEqual(ds.site_references(self.path / "site"), ["assets/gone.png"])

    def test_urls(self):
        self.assertEqual(ds.url_for("index.html"), "/")
        self.assertEqual(ds.url_for("docs/index.html"), "/docs/")
        self.assertEqual(ds.url_for("assets/a.png"), "/assets/a.png")

    def test_verify_live_passes_when_it_matches(self):
        self.assertEqual(ds.verify_live(self.repo, site_fetcher(self.repo, "HEAD"), wait=0), [])

    def test_verify_live_flags_old_files_and_visible_hidden_paths(self):
        problems = ds.verify_live(self.repo, site_fetcher(self.repo, self.c1, hidden_visible=True), wait=0)
        self.assertTrue(any("isn't the version just deployed" in p for p in problems))
        self.assertTrue(any("/.DS_Store is publicly visible" in p for p in problems))


class EndToEnd(RepoCase):
    """main() with Cloudflare faked and the slow checks (which run these tests) skipped."""

    def run_main(self, *args: str, note: str | None = None) -> tuple[int, str]:
        saved = ds.Cloudflare, ds.run_checks
        ds.Cloudflare = lambda repo: FakeCloudflare(note if note is not None else ds.note_for(self.c2, "main"))
        ds.run_checks = lambda repo, cf, build: None
        out = io.StringIO()
        try:
            with contextlib.redirect_stdout(out):
                code = ds.main([*args, "--repo", str(self.path)])
        finally:
            ds.Cloudflare, ds.run_checks = saved
        return code, out.getvalue()

    def test_check_passes_on_main(self):
        code, out = self.run_main("--check")
        self.assertEqual(code, 0, out)
        self.assertIn("Check passed", out)
        self.assertIn("Docs only", out)

    def test_check_stops_on_a_branch_missing_live_work(self):
        git(self.path, "checkout", "-q", "old")
        code, out = self.run_main("--check")
        self.assertEqual(code, 1)
        self.assertIn("STOP: This branch is missing work that's live", out)

    def test_yes_never_gets_past_a_stop(self):
        git(self.path, "checkout", "-q", "old")
        code, out = self.run_main("--yes")
        self.assertEqual(code, 1)
        self.assertIn("Nothing was deployed", out)

    def test_without_a_terminal_or_yes_it_asks_instead_of_deploying(self):
        code, out = self.run_main()
        self.assertEqual(code, 1)
        self.assertIn("no terminal", out)


class Hook(unittest.TestCase):
    BLOCKED = [
        "wrangler deploy",
        "npx wrangler deploy",
        "npx --yes wrangler@4.80.0 deploy --message hi",
        "cd site && wrangler deploy",
        "CLOUDFLARE_ACCOUNT_ID=x wrangler deploy",
        "./node_modules/.bin/wrangler deploy",
        "wrangler -c wrangler.jsonc deploy",
        "wrangler versions deploy abc@100%",
        "bash -c 'wrangler deploy'",
        "pnpm dlx wrangler deploy",
        "wrangler publish",
    ]
    ALLOWED = [
        "scripts/deploy-site --check",
        "scripts/deploy-site --yes",
        "wrangler deploy --dry-run",
        "wrangler deployments list --json",
        "wrangler deployments status",
        "wrangler versions view abc --json",
        "wrangler rollback abc --message 'Roll back'",
        "npx wrangler dev --port 5261",
        "git commit -m 'Replace raw wrangler deploy with scripts/deploy-site'",
        "grep -n 'wrangler deploy' CLAUDE.md",
        "python3 - <<'EOF'\nsub('README.md', 'Publish changes with\\n`wrangler deploy`.', 'x')\nEOF",
        "cat <<'EOF' > notes.md\n`wrangler deploy` is blocked here\nEOF",
    ]

    def test_blocks_raw_deploys(self):
        for command in self.BLOCKED:
            self.assertTrue(hook.blocks(command), command)

    def test_allows_everything_else(self):
        for command in self.ALLOWED:
            self.assertFalse(hook.blocks(command), command)

    def test_exit_code_and_message(self):
        script = SCRIPTS / "hooks" / "block-raw-deploy"
        for command, expected in (("wrangler deploy", 2), ("ls", 0)):
            result = subprocess.run([sys.executable, str(script)], capture_output=True, text=True,
                                    input=json.dumps({"tool_name": "Bash", "tool_input": {"command": command}}))
            self.assertEqual(result.returncode, expected, command)
            if expected:
                self.assertIn("scripts/deploy-site", result.stderr)


if __name__ == "__main__":
    unittest.main()
