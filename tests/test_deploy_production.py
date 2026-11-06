import importlib.util
import tempfile
import unittest
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

    def test_newer_branch_lists_additions(self):
        self.assertIn('Codex and Claude', deploy.lost_commits('ce3d4255f02dbe833f44c2b4c5b01e124cf706b7', 'f4764cc'))


if __name__ == '__main__': unittest.main()
