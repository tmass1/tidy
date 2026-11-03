import importlib.util
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

    def test_unknown_legacy_content_stops(self):
        with self.assertRaisesRegex(RuntimeError, 'no recorded commit'):
            deploy.live_commit({'id': next(iter(deploy.LEGACY))}, b'wrong')

    def test_missing_live_work_stops(self):
        with patch.object(deploy, 'ROOT', Path(__file__).resolve().parents[1]):
            with self.assertRaisesRegex(RuntimeError, 'missing live work'):
                deploy.lost_commits('ce3d4255f02dbe833f44c2b4c5b01e124cf706b7', '887e864')

    def test_newer_branch_lists_additions(self):
        self.assertIn('Codex and Claude', deploy.lost_commits('ce3d4255f02dbe833f44c2b4c5b01e124cf706b7', 'f4764cc'))


if __name__ == '__main__': unittest.main()
