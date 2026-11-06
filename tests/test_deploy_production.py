import importlib.util
import io
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('deploy', Path(__file__).resolve().parents[1] / 'scripts/deploy-production.py')
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)


class DeployCheckTests(unittest.TestCase):
    def test_latest_deployment_is_selected_by_time(self):
        self.assertEqual(deploy.active_deployment([{'id':'new','created_on':'2026-11-02'}, {'id':'old','created_on':'2026-10-30'}])['id'], 'new')

    def test_deploy_note_has_priority(self):
        d = {'id': next(iter(deploy.LEGACY)), 'annotations': {'workers/message': 'commit=abc123 branch=main'}}
        self.assertEqual(deploy.live_commit(d, b'wrong')[0], 'abc123')

    def test_manual_commit_cannot_override_cloudflare_note(self):
        d = {'id': 'new', 'annotations': {'workers/message': 'commit=abc123 branch=main'}}
        with self.assertRaisesRegex(RuntimeError, 'cannot override'):
            deploy.live_commit(d, b'', '887e864')

    def test_manual_commit_must_exist_locally(self):
        with self.assertRaisesRegex(RuntimeError, 'absent from this checkout'):
            deploy.live_commit({'id': 'new'}, b'', 'not-a-local-commit')

    def test_manual_commit_is_resolved_to_full_hash(self):
        commit, source = deploy.live_commit({'id': 'new'}, b'', '887e864')
        self.assertEqual(commit, deploy.git('rev-parse', '887e864^{commit}'))
        self.assertIn('manually supplied', source)

    def test_cloudflare_beacon_is_removed_from_source_comparison(self):
        page = b'<html>\n<script type="module" src="https://static.cloudflareinsights.com/beacon.min.js/abc" integrity="x"></script>\n</html>'
        self.assertEqual(deploy.source_page_bytes(page), b'<html>\n</html>')

    def test_unknown_legacy_content_stops(self):
        with self.assertRaisesRegex(RuntimeError, 'no recorded commit'):
            deploy.live_commit({'id': next(iter(deploy.LEGACY))}, b'wrong')

    def test_missing_live_work_stops(self):
        with patch.object(deploy, 'ROOT', Path(__file__).resolve().parents[1]):
            with self.assertRaisesRegex(RuntimeError, 'missing live work'):
                deploy.lost_commits('ce3d4255f02dbe833f44c2b4c5b01e124cf706b7', '887e864')

    def test_build_runs_the_python_tests_then_the_release_build(self):
        steps = deploy.build_steps()
        self.assertEqual(steps[0][1:], ('-m', 'unittest', 'discover', '-s', 'tests'))
        self.assertEqual(steps[-1], ('swift', 'build', '-c', 'release'))
        self.assertTrue((deploy.ROOT / 'tests' / Path(__file__).name).exists())

    def test_swift_test_only_runs_when_the_package_has_swift_tests(self):
        self.assertNotIn(('swift', 'test'), deploy.build_steps())
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / 'Package.swift').write_text('.testTarget(name: "TidyTests", dependencies: ["Tidy"])')
            self.assertIn(('swift', 'test'), deploy.build_steps(tmp))

    def test_site_pages_are_read_from_the_commit(self):
        self.assertEqual(deploy.site_pages('ce3d4255f02dbe833f44c2b4c5b01e124cf706b7'), ['/'])
        with patch.object(deploy, 'git', return_value='site/assets\nsite/index.html\nsite/privacy.html\nsite/terms.html'):
            self.assertEqual(deploy.site_pages('any'), ['/', '/privacy', '/terms'])

    def fake_site(self, missing_for=0, also=None):
        # A live site where /privacy is "not found" for the first `missing_for` rounds of checks.
        calls = {'/': 0}

        def get(url):
            path = url[len(deploy.SITE):]
            if path == '/':
                calls['/'] += 1
            if path in (also or {}):
                return also[path], b'x', ''
            if path == '/privacy' and calls['/'] <= missing_for:
                return 404, b'', ''
            ok = path in ('/', '/privacy', '/assets/hero-light.png', '/signature/signature.js')
            return (200, b'x', '') if ok else (404, b'', '')
        return patch.multiple(deploy, get=get, site_pages=lambda commit: ['/', '/privacy'])

    def test_check_after_a_deploy_waits_for_a_new_page(self):
        with self.fake_site(missing_for=2), patch.object(deploy.time, 'sleep') as sleep, redirect_stdout(io.StringIO()) as out:
            deploy.verify_site('any', wait=60)
        self.assertEqual(sleep.call_count, 2)
        self.assertIn('Not live everywhere yet', out.getvalue())
        self.assertIn('Public /privacy: HTTP 200', out.getvalue())

    def test_check_after_a_deploy_gives_up_on_a_real_failure(self):
        ticks = iter(range(0, 1000, 30))
        with self.fake_site(missing_for=999), patch.object(deploy.time, 'sleep'), \
                patch.object(deploy.time, 'monotonic', lambda: next(ticks)), redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(RuntimeError, r'/privacy failed: HTTP 404'):
                deploy.verify_site('any', wait=60)

    def test_check_before_a_deploy_does_not_wait(self):
        with self.fake_site(missing_for=999), patch.object(deploy.time, 'sleep') as sleep, redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(RuntimeError, r'/privacy failed'):
                deploy.verify_site('any')
        sleep.assert_not_called()

    def test_a_hidden_path_that_loads_is_a_problem(self):
        with self.fake_site(also={'/wrangler.jsonc': 200}), patch.object(deploy.time, 'sleep'), redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(RuntimeError, r'/wrangler.jsonc returned HTTP 200'):
                deploy.verify_site('any')

    def test_no_response_counts_as_a_failure(self):
        def get(url):
            raise OSError('connection refused')
        with patch.multiple(deploy, get=get, site_pages=lambda commit: ['/']), redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(RuntimeError, r'no response'):
                deploy.verify_site('any')

    def test_newer_branch_lists_additions(self):
        self.assertIn('Codex and Claude', deploy.lost_commits('ce3d4255f02dbe833f44c2b4c5b01e124cf706b7', 'f4764cc'))


if __name__ == '__main__': unittest.main()
