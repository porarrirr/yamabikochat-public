#!/usr/bin/env python3
"""Check the publishable working tree for private files and identifying settings.

This is a release guard, not a general-purpose secret scanner. Third-party license
attributions are preserved. Findings show paths and rule names, never secret values.
"""
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
paths = subprocess.check_output(
    ['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=ROOT
).decode().split('\0')
forbidden = re.compile(
    r'(^|/)(AGENTS\.md|SUBAGENTS\.md|memo(?:s)?|\.env(?:\..*)?|xcuserdata|'
    r'AppStoreCreative|AppStoreScreenshots|AppStoreReviewNotes\.md|design-reviews)(/|$)'
    r'|\.(?:p12|p8|key|pem|mobileprovision|provisionprofile|ipa|xcresult|log)$'
    r'|^ios/Performance-'
)
rules = {
    'local home path': re.compile(r'/(?:Users|home)/[A-Za-z][\w.-]+/'),
    'personal app identifier': re.compile(r'com\.' + r'porarri\.'),
    'personal website': re.compile(r'porarrirr' + r'\.github\.io'),
    'signing team': re.compile(r'(?:DEVELOPMENT_TEAM\s*[:=]|DevelopmentTeam\s*=)\s*[A-Z0-9]{10}'),
    'private key': re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
    'GitHub token': re.compile(r'gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}'),
    'AWS access key': re.compile(r'AKIA[A-Z0-9]{16}'),
}
findings = []
for name in sorted(set(paths)):
    if not name or not (ROOT / name).is_file():
        continue
    if forbidden.search(name):
        findings.append((name, 'private file type'))
    # Vendor notices retain legally required names and contact details.
    if name.startswith('third_party/') or name in ('LICENSE', 'THIRD_PARTY_NOTICES.md'):
        continue
    try:
        content = (ROOT / name).read_text()
    except UnicodeDecodeError:
        continue
    for label, pattern in rules.items():
        if pattern.search(content):
            findings.append((name, label))
for name, label in findings:
    print(f'{name}: {label}', file=sys.stderr)
if findings:
    sys.exit(1)
print('Public content checks passed.')
