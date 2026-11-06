#!/usr/bin/env python3
"""Guarded production deploy for the static Tidy site."""
import argparse
import hashlib
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKER = 'tidy-app'
SITE = 'https://tidy-app.tommymassaro.com'
RELEASE_BRANCH = 'main'
# Cloudflare takes a little while to serve a new version everywhere, so the check after a deploy retries.
POST_DEPLOY_WAIT = 90
RETRY_EVERY = 5
# Verified 2026-11-03: active Cloudflare deployment, exact live index bytes,
# and site/index.html from ce3d425 match. Commit attribution is inferred.
LEGACY = {'dc287bd2-f77f-481f-827b-02b291ea0d77': {'commit': 'ce3d4255f02dbe833f44c2b4c5b01e124cf706b7', 'index_sha256': '77e53701ada23a60e2782cdec2d2c7299a918ab833cb6a5ead1f55cb2c22721a'}}


def run(*args, check=True):
    p = subprocess.run(args, cwd=ROOT, text=True, capture_output=True)
    if check and p.returncode:
        raise RuntimeError(f"{' '.join(args)} failed: {p.stderr.strip() or p.stdout.strip()}")
    return p.stdout.strip()


def git(*args): return run('git', *args)


def get(url):
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'Tidy-deploy-check/1'}), timeout=15) as r:
            return r.status, r.read(), r.headers.get('Content-Type', '')
    except urllib.error.HTTPError as e:
        return e.code, e.read(), e.headers.get('Content-Type', '')


def active_deployment(deployments):
    if not deployments: raise RuntimeError('Cloudflare has no deployments; cannot establish what is live.')
    return max(deployments, key=lambda d: d['created_on'])


def source_page_bytes(index_bytes):
    # Cloudflare may inject its analytics beacon for some user agents. Remove only
    # this exact kind of script before comparing against the checked-in HTML.
    return re.sub(rb'<script type="module" src="https://static\.cloudflareinsights\.com/beacon\.min\.js/[^"]+"[^>]*></script>\n', b'', index_bytes)


def live_commit(deployment, index_bytes, manual_commit=None):
    notes = deployment.get('annotations') or {}
    message = notes.get('workers/message', '')
    for word in message.split():
        if word.startswith('commit='):
            if manual_commit is not None:
                raise RuntimeError('--live cannot override a commit recorded by Cloudflare.')
            return word[7:], 'Cloudflare deploy note'
    if manual_commit is not None:
        if subprocess.run(['git', 'cat-file', '-e', f'{manual_commit}^{{commit}}'], cwd=ROOT, capture_output=True).returncode:
            raise RuntimeError(f'--live commit {manual_commit} is absent from this checkout. Fetch the branch containing it first.')
        return git('rev-parse', f'{manual_commit}^{{commit}}'), 'manually supplied with --live; verify against Cloudflare history'
    legacy = LEGACY.get(deployment['id'])
    if legacy and hashlib.sha256(source_page_bytes(index_bytes)).hexdigest() == legacy['index_sha256']:
        return legacy['commit'], 'legacy site match (commit attribution inferred)'
    raise RuntimeError('Active deployment has no recorded commit and does not match the verified legacy page. Check Cloudflare history, then provide --live <commit>; do not guess.')


def lost_commits(live, head):
    known = subprocess.run(['git', 'cat-file', '-e', f'{live}^{{commit}}'], cwd=ROOT).returncode == 0
    if not known: raise RuntimeError(f'Live commit {live} is absent here. Push and fetch the branch that contains it first.')
    if subprocess.run(['git', 'merge-base', '--is-ancestor', live, head], cwd=ROOT).returncode:
        commits = git('log', '--oneline', f'{head}..{live}') or live
        raise RuntimeError(f'This branch is missing live work:\n{commits}\nMerge the branch containing {live} before deploying.')
    return git('log', '--oneline', f'{live}..{head}')


def site_pages(commit):
    # The pages in site/ at a commit, as URLs. Before a deploy this is what's live, so a page that's
    # being added doesn't stop its own deploy; after it, the commit just deployed.
    names = git('ls-tree', '--name-only', commit, 'site/').splitlines()
    pages = [name[len('site/'):-len('.html')] for name in names if name.endswith('.html')]
    return ['/' + ('' if page == 'index' else page) for page in sorted(pages)]


def fetch_status(path):
    try:
        status, body, _ = get(SITE + path)
    except OSError as e:
        return f'no response ({e})', b''
    return status, body


def site_problems(commit):
    # Every public and hidden URL at once. Returns (lines to print, what's wrong).
    public = [*site_pages(commit), '/assets/hero-light.png', '/signature/signature.js']
    hidden = ['/.git/config', '/wrangler.jsonc', '/AGENTS.md', '/CLAUDE.md', '/release.sh', '/Sources/', '/build/', '/docs/', '/__tidy_unknown_page__']
    lines, problems = [], []
    for path in public:
        status, body = fetch_status(path)
        if status != 200 or not body: problems.append(f'Public page or asset {path} failed: HTTP {status}')
        else: lines.append(f'Public {path}: HTTP {status}')
    for path in hidden:
        status, _ = fetch_status(path)
        if status != 404: problems.append(f'Hidden or unknown path {path} returned HTTP {status}, expected 404')
        else: lines.append(f'Hidden {path}: HTTP 404')
    return lines, problems


def verify_site(commit, wait=0):
    # Before a deploy wait is 0: what's live should already be right. After one it gives Cloudflare time.
    deadline = time.monotonic() + wait
    while True:
        lines, problems = site_problems(commit)
        if not problems or time.monotonic() >= deadline: break
        print(f'Not live everywhere yet ({problems[0]}). Checking again in {RETRY_EVERY} seconds.')
        time.sleep(RETRY_EVERY)
    for line in lines: print(line)
    if problems: raise RuntimeError('\n'.join(problems))


def build_steps(root=ROOT):
    # The tests are the Python ones in tests/. Tidy has no Swift test target, and `swift test` with
    # none fails ("no tests found"), so it only runs once Package.swift declares one.
    steps = [(sys.executable, '-m', 'unittest', 'discover', '-s', 'tests')]
    if 'testTarget(' in (Path(root) / 'Package.swift').read_text():
        steps.append(('swift', 'test'))
    steps.append(('swift', 'build', '-c', 'release'))
    return steps


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true', help='inspect production without build or deploy')
    parser.add_argument('--yes', action='store_true', help='nonterminal confirmation, only after Tommy approves in chat')
    parser.add_argument('--live', metavar='COMMIT', help='manually identified live commit, only when Cloudflare has no commit note')
    args = parser.parse_args()
    if args.check and args.yes: parser.error('--yes is only for an approved deploy')
    branch = git('branch', '--show-current'); head = git('rev-parse', 'HEAD')
    print(f'Folder: {ROOT}\nBranch: {branch}\nCommit: {head}')
    dirty = git('status', '--porcelain', '--untracked-files=all')
    if dirty: raise RuntimeError('Files in this checkout are not committed:\n' + dirty)
    git('fetch', 'origin', '--prune')
    deployments = json.loads(run('wrangler', 'deployments', 'list', '--name', WORKER, '--json'))
    active = active_deployment(deployments)
    if len(active.get('versions', [])) != 1 or active['versions'][0]['percentage'] != 100:
        raise RuntimeError('Production has a split deployment; identify each live commit before deploying.')
    print(f"Cloudflare deployment: {active['id']} ({active['created_on']})")
    status, index, _ = get(SITE + '/')
    if status != 200: raise RuntimeError(f'Live home page returned HTTP {status}')
    live, provenance = live_commit(active, index, args.live)
    print(f'Live commit: {live} ({provenance})')
    added = lost_commits(live, head)
    print('This deploy adds:\n' + (added or '(no new commits)'))
    remote = run('git', 'ls-remote', 'origin', f'refs/heads/{branch}', check=False).split()
    confirmations = []
    if branch != RELEASE_BRANCH: confirmations.append('side branch; merge it into main after any deploy')
    if not remote or remote[0] != head: confirmations.append('local and remote branch differ; push only when Tommy says so')
    origin_main = git('rev-parse', 'origin/main')
    if subprocess.run(['git', 'merge-base', '--is-ancestor', origin_main, head], cwd=ROOT).returncode:
        confirmations.append('remote main has commits this branch lacks')
    for item in confirmations: print('Reminder: confirm ' + item)
    verify_site(live)
    print('Rollback: wrangler rollback ' + active['versions'][0]['version_id'] + ' --name ' + WORKER)
    print('After deploy: write release notes; merge a side branch into main; push only when Tommy says so.')
    if args.check: print('Check complete. No build or deploy ran.'); return
    if confirmations and not args.yes:
        if input('Confirm these reminders before continuing (yes): ').strip() != 'yes': raise RuntimeError('Deploy cancelled.')
    for step in build_steps():
        run(*step)
    print('Tests and production build passed.')
    if not args.yes:
        if input("Type deploy to publish production: ").strip() != 'deploy': raise RuntimeError('Deploy cancelled.')
    else:
        print('--yes used: requires Tommy’s explicit approval in this chat.')
    run('wrangler', 'deploy', '--name', WORKER, '--message', f'commit={head} branch={branch}')
    print('Deployment complete. Checking live site...')
    try:
        verify_site(head, wait=POST_DEPLOY_WAIT)
    except RuntimeError as e:
        raise RuntimeError(f'The deploy went out, but the live site still fails its check after {POST_DEPLOY_WAIT} seconds:\n{e}\n'
                           f"Ask Tommy before rolling back: wrangler rollback {active['versions'][0]['version_id']} --name {WORKER}")
    print('Live site check passed.')


if __name__ == '__main__':
    try: main()
    except (RuntimeError, OSError, ValueError) as e:
        print('STOP: ' + str(e), file=sys.stderr); sys.exit(1)
