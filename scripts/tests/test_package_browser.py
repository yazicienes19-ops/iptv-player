import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("package_browser", ROOT / "scripts/package_browser.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class BrowserPackageTests(unittest.TestCase):
    def test_runtime_is_included_but_personal_data_and_caches_are_not(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for file in module.FILES:
                path = root / file
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('{}' if file.endswith('.json') else 'runtime')
            for file in ('webos/tv/index.html', 'webos/tv/js/recommendations.js',
                         'webos/tv/data/imdb.json', 'webos/tv/.env', 'build/private.txt'):
                path = root / file
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('fixture')
            output = module.package(root, root / 'out.zip', '1.2.3', '4')
            with zipfile.ZipFile(output) as archive:
                names = archive.namelist()
                self.assertIn('IpFlix-browser-v1.2.3/webos/tv/js/recommendations.js', names)
                self.assertIn('IpFlix-browser-v1.2.3/webos/service/setup.js', names)
                self.assertFalse(any('imdb.json' in name or '.env' in name or 'private.txt' in name for name in names))
                self.assertEqual(json.loads(archive.read('IpFlix-browser-v1.2.3/webos/service/package.json'))['version'], '1.2.3')
                self.assertEqual(json.loads(archive.read('IpFlix-browser-v1.2.3/release-info.json')), {'version': '1.2.3', 'build': 4})
                self.assertIn(b'node webos/dev/start.js', archive.read('IpFlix-browser-v1.2.3/STARTEN.txt'))

    def test_symlinked_runtime_cannot_include_files_outside_the_package(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            outside = root / 'secret'
            outside.write_text('not for release')
            first = root / module.FILES[0]
            first.parent.mkdir(parents=True)
            first.symlink_to(outside)
            with self.assertRaisesRegex(ValueError, 'Symlinks'):
                module.package(root, root / 'out.zip', '1.2.3', '4')


if __name__ == '__main__':
    unittest.main()
