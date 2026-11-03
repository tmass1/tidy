"""Tests for the Claude Code hook that refuses a raw production deploy (scripts/hooks/block-raw-deploy)."""
import importlib.machinery
import importlib.util
import json
import subprocess
import sys
import unittest
from pathlib import Path

HOOK = Path(__file__).resolve().parents[1] / 'scripts/hooks/block-raw-deploy'
loader = importlib.machinery.SourceFileLoader('block_raw_deploy', str(HOOK))
spec = importlib.util.spec_from_loader('block_raw_deploy', loader)
hook = importlib.util.module_from_spec(spec)
loader.exec_module(hook)

BLOCKED = [
    'wrangler deploy',
    'npx wrangler deploy',
    'npx --yes wrangler@4.80.0 deploy --message hi',
    'cd site && wrangler deploy',
    'CLOUDFLARE_ACCOUNT_ID=x wrangler deploy',
    './node_modules/.bin/wrangler deploy',
    'wrangler -c wrangler.jsonc deploy',
    'wrangler deploy --name tidy-app --message "commit=abc branch=main"',
    'wrangler versions deploy abc@100%',
    "bash -c 'wrangler deploy'",
    'pnpm dlx wrangler deploy',
    'wrangler publish',
]

ALLOWED = [
    'python3 scripts/deploy-production.py --check',
    'python3 scripts/deploy-production.py --yes',
    'wrangler deploy --dry-run',
    'wrangler deployments list --json',
    'wrangler deployments status',
    'wrangler versions view abc --json',
    "wrangler rollback abc --name tidy-app --message 'Roll back'",
    'npx wrangler dev --port 5261',
    "git commit -m 'Replace raw wrangler deploy with the deploy check'",
    "grep -n 'wrangler deploy' CLAUDE.md",
    "cat <<'EOF' > notes.md\n`wrangler deploy` is blocked here\nEOF",
]


class BlockRawDeployTests(unittest.TestCase):
    def test_blocks_raw_production_deploys(self):
        for command in BLOCKED:
            self.assertTrue(hook.blocks(command), command)

    def test_allows_the_check_and_everything_else(self):
        for command in ALLOWED:
            self.assertFalse(hook.blocks(command), command)

    def test_exit_code_and_message_point_to_the_check(self):
        for command, expected in (('wrangler deploy', 2), ('ls', 0)):
            result = subprocess.run([sys.executable, str(HOOK)], capture_output=True, text=True,
                                    input=json.dumps({'tool_name': 'Bash', 'tool_input': {'command': command}}))
            self.assertEqual(result.returncode, expected, command)
            if expected:
                self.assertIn('scripts/deploy-production.py --check', result.stderr)
                self.assertIn('docs/production-deploy.md', result.stderr)

    def test_settings_run_this_hook_before_bash(self):
        settings = json.loads((HOOK.parents[2] / '.claude/settings.json').read_text())
        entries = settings['hooks']['PreToolUse']
        self.assertTrue(any(e['matcher'] == 'Bash' and 'scripts/hooks/block-raw-deploy' in h['command']
                            for e in entries for h in e['hooks']))

    def test_message_names_files_that_exist(self):
        root = HOOK.parents[2]
        for path in ('scripts/deploy-production.py', 'docs/production-deploy.md', 'AGENTS.md'):
            self.assertIn(path, hook.MESSAGE)
            self.assertTrue((root / path).exists(), path)


if __name__ == '__main__':
    unittest.main()
