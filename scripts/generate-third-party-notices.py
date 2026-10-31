#!/usr/bin/env python3
"""Generate complete npm and Swift notices from pinned, local license sources.

Run after npm ci. No license text, copyright holder, or missing grant is inferred
from an SPDX identifier. Supplemental upstream texts are pinned in sources.json.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / 'ios/PiRuntime'
THIRD_PARTY = ROOT / 'third_party'


def package_notices(directory):
    notices = []
    for parent, directories, files in os.walk(directory):
        directories[:] = sorted(d for d in directories if d != 'node_modules')
        for name in sorted(files):
            path = Path(parent) / name
            relative = path.relative_to(directory)
            if re.match(r'(?i)^(licen[cs]e|copying|notice)(?:[.\-_]|$)', name) or any(
                part.lower() == 'licenses' for part in relative.parts[:-1]
            ):
                notices.append((str(relative), path.read_text()))
    return sorted(notices)


def npm_notices():
    lock = json.loads((RUNTIME / 'package-lock.json').read_text())
    supplemental = THIRD_PARTY / 'npm-license-sources'
    sources = json.loads((supplemental / 'sources.json').read_text())
    for name, metadata in sources['files'].items():
        actual = hashlib.sha256((supplemental / name).read_bytes()).hexdigest()
        if actual != metadata['sha256']:
            raise SystemExit(f'License source checksum mismatch: {name}')
    packages = {}
    for relative, package in lock['packages'].items():
        if not relative or package.get('dev'):
            continue
        name = package.get('name') or relative.split('node_modules/')[-1]
        identity = f'{name}@{package["version"]}'
        directory = RUNTIME / relative
        if directory.exists():
            installed = json.loads((directory / 'package.json').read_text())
            if installed['version'] != package['version']:
                raise SystemExit(f'Run npm ci: installed version mismatch for {identity}')
        notices = package_notices(directory)
        filename = sources['packages'].get(identity)
        if filename:
            metadata = sources['files'][filename]
            notices.append((metadata['source'], (supplemental / filename).read_text()))
        if not notices:
            raise SystemExit(f'Missing upstream license text: {identity}')
        packages[identity] = (name, package['version'], package.get('license', 'See upstream notices'), notices)
    inventory = [
        '# Pi runtime npm production licenses', '',
        'Generated from `ios/PiRuntime/package-lock.json` by `scripts/generate-third-party-notices.py`.',
        'Full copyright notices and license texts: [npm-license-texts.md](npm-license-texts.md).',
        'Includes production transitive dependencies conservatively, including optional build helpers.',
        '', f'Count: {len(packages)} packages.', '', '| Package | Version | License |', '| --- | --- | --- |',
    ]
    full = ['# Pi runtime npm license texts', '',
            'Generated from the exact locked production dependencies and pinned upstream license sources.',
            'Third-party components retain their own licenses; the project MIT license does not replace them.', '']
    for identity, (name, version, license_name, notices) in sorted(packages.items()):
        inventory.append(f'| `{name}` | {version} | {license_name} |')
        full += [f'## {identity}', '', f'Declared license: {license_name}', '']
        for source, text in notices:
            full += [f'Source: {source}', '', '````', text.rstrip(), '````', '']
    return {'npm-licenses.md': '\n'.join(inventory) + '\n', 'npm-license-texts.md': '\n'.join(full)}


def swift_notices():
    directory = THIRD_PARTY / 'swift-licenses'
    packages = json.loads((directory / 'sources.json').read_text())
    resolved = ROOT / 'ios/YamabikoChat.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
    if resolved.exists():
        actual = {p['identity']: p['state']['revision'] for p in json.loads(resolved.read_text())['pins']}
        expected = {p['name']: p['revision'] for p in packages}
        if actual != expected:
            raise SystemExit('Swift dependency revisions changed; refresh third_party/swift-licenses first.')
    result = ['# Swift dependency license texts', '',
              'Upstream copyright, license, and NOTICE files at the recorded dependency revisions.', '']
    for package in packages:
        result += [f'## {package["name"]} {package["version"]}', '', f'Source: {package["source"]}', '']
        for filename in package['files']:
            result += [f'### {filename}', '', '````', (directory / filename).read_text().rstrip(), '````', '']
    return '\n'.join(result)


def python_core_notices():
    directory = THIRD_PARTY / 'python-core-licenses'
    sources = json.loads((directory / 'sources.json').read_text())
    result = ['# Python and WebAssembly core license texts', '',
              'Notices for CPython 3.14.2 and the core libraries recorded by Pyodide 314.0.7.',
              'Pyodide itself is covered by PYODIDE_LICENSE.txt in the app; source availability is described in PYODIDE-SOURCES.md.', '']
    for name, source in sorted(sources.items()):
        path = directory / name
        if hashlib.sha256(path.read_bytes()).hexdigest() != source['sha256']:
            raise SystemExit(f'Python core license checksum mismatch: {name}')
        result += [f'## {name}', '', f'Source: {source["source"]}', '',
                   '````', path.read_text().rstrip(), '````', '']
    return '\n'.join(result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Fail if committed notices are stale')
    arguments = parser.parse_args()
    outputs = npm_notices()
    outputs['swift-license-texts.md'] = swift_notices()
    outputs['python-core-license-texts.md'] = python_core_notices()
    for name, content in outputs.items():
        content = '\n'.join(line.rstrip() for line in content.splitlines()) + '\n'
        path = THIRD_PARTY / name
        if arguments.check:
            if not path.exists() or path.read_text() != content:
                raise SystemExit(f'Stale notices: {name}; run scripts/generate-third-party-notices.py')
        else:
            path.write_text(content)
    print('Third-party license texts and inventory verified.' if arguments.check else 'Generated third-party license texts and inventory.')


if __name__ == '__main__':
    main()
