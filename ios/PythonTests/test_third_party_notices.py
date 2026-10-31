import importlib.util
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts/generate-third-party-notices.py'
spec = importlib.util.spec_from_file_location('third_party_notices', SCRIPT)
notices = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notices)


class ThirdPartyNoticeTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.runtime = self.root / 'ios/PiRuntime'
        self.package = self.runtime / 'node_modules/example'
        self.package.mkdir(parents=True)
        (self.package / 'package.json').write_text(json.dumps({'version': '1.0.0'}))
        (self.runtime / 'package-lock.json').write_text(json.dumps({'packages': {
            'node_modules/example': {'version': '1.0.0', 'license': 'MIT'},
        }}))
        supplemental = self.root / 'third_party/npm-license-sources'
        supplemental.mkdir(parents=True)
        (supplemental / 'sources.json').write_text(json.dumps({'files': {}, 'packages': {}}))
        context = patch.multiple(notices, ROOT=self.root, RUNTIME=self.runtime, THIRD_PARTY=self.root / 'third_party')
        context.start()
        self.addCleanup(context.stop)

    def test_preserves_copyright_text_and_nested_third_party_notices(self):
        (self.package / 'license.md').write_text('Copyright Example Authors\nPermission notice\n')
        nested = self.package / 'LICENSES'
        nested.mkdir()
        (nested / 'vendored.txt').write_text('Copyright Vendored Authors\nSeparate grant\n')
        output = notices.npm_notices()
        self.assertIn('Copyright Example Authors\nPermission notice', output['npm-license-texts.md'])
        self.assertIn('Copyright Vendored Authors\nSeparate grant', output['npm-license-texts.md'])
        self.assertIn('`example` | 1.0.0 | MIT', output['npm-licenses.md'])

    def test_spdx_identifier_does_not_replace_missing_license_text(self):
        with self.assertRaisesRegex(SystemExit, 'Missing upstream license text'):
            notices.npm_notices()

    def test_installed_version_must_match_lock(self):
        (self.package / 'package.json').write_text(json.dumps({'version': '2.0.0'}))
        with self.assertRaisesRegex(SystemExit, 'installed version mismatch'):
            notices.npm_notices()

    def test_tampered_supplemental_license_is_rejected(self):
        directory = self.root / 'third_party/npm-license-sources'
        (directory / 'upstream.txt').write_text('Changed license')
        (directory / 'sources.json').write_text(json.dumps({
            'files': {'upstream.txt': {'source': 'https://example.org/LICENSE', 'sha256': '0' * 64}},
            'packages': {'example@1.0.0': 'upstream.txt'},
        }))
        with self.assertRaisesRegex(SystemExit, 'License source checksum mismatch'):
            notices.npm_notices()

    def test_nested_node_modules_are_not_attributed_to_parent_package(self):
        nested = self.package / 'node_modules/other'
        nested.mkdir(parents=True)
        (nested / 'LICENSE').write_text('Other package grant')
        with self.assertRaisesRegex(SystemExit, 'Missing upstream license text'):
            notices.npm_notices()

    def test_package_license_is_retained_alongside_vendored_notices(self):
        directory = self.root / 'third_party/npm-license-sources'
        text = 'Copyright Package Authors\nPackage permission grant\n'
        (directory / 'upstream.txt').write_text(text)
        (directory / 'sources.json').write_text(json.dumps({
            'files': {'upstream.txt': {
                'source': 'https://example.org/LICENSE',
                'sha256': hashlib.sha256(text.encode()).hexdigest(),
            }},
            'packages': {'example@1.0.0': 'upstream.txt'},
        }))
        nested = self.package / 'LICENSES'
        nested.mkdir()
        (nested / 'vendor.txt').write_text('Copyright Vendor Authors\nVendor permission grant\n')
        output = notices.npm_notices()['npm-license-texts.md']
        self.assertIn('Copyright Package Authors', output)
        self.assertIn('Copyright Vendor Authors', output)


if __name__ == '__main__':
    unittest.main()
