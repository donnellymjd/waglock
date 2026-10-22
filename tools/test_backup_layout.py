import json
from pathlib import Path
import tempfile
import unicodedata
import unittest
from unittest.mock import patch

from backup_recovery import InvalidBackup, recover
import test_backup_recovery as fixtures
from test_backup_recovery import ASSET, ALBUM, NOTE, archive, asset_record, metadata


class ReadableRecoveryTests(unittest.TestCase):
    def run_recovery(self, root, data, **kwargs):
        source = root / 'source.age'; source.write_bytes(data)
        destination = root / 'recovered'
        with patch('backup_recovery.subprocess.run', side_effect=fixtures.BackupRecoveryTests.fake_age):
            result = recover(source, destination, 'fixture-age', **kwargs)
        return destination, result

    def test_original_names_extensions_notes_drafts_and_mapping(self):
        meta = metadata(); item = asset_record(); item.update(name='Summer photo', fileExtension='jpg')
        meta['assets'] = [item]
        meta['notes'] = [{'id': NOTE, 'title': 'Shopping', 'content': '# List\n- tea', 'createdAt': 42, 'modifiedAt': 43, 'isFavorite': False, 'tags': []}]
        meta['drafts'] = [{'origin': 'keychain', 'title': 'Unfinished', 'content': 'Saved draft', 'updatedAt': 44}]
        payload = b'\xff\xd8\xffpublic fixture'; thumb = b'\x89PNG\r\n\x1a\npublic fixture'
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            output, report = self.run_recovery(root, archive(meta, {'media/' + ASSET: payload, 'thumbnails/' + ASSET: thumb}))
            self.assertEqual(report['layout'], 'readable')
            self.assertEqual((output / 'Library/Media/Summer photo.jpg').read_bytes(), payload)
            self.assertEqual((output / 'Library/Notes/Shopping.md').read_text(), '# List\n- tea')
            self.assertEqual((output / 'Library/Drafts/Unfinished.md').read_text(), 'Saved draft')
            self.assertTrue((output / 'root/thumbnails' / (ASSET + '.png')).is_file())
            self.assertEqual(json.loads((output / 'root/metadata.json').read_text()), meta)
            self.assertTrue((output / 'root/manifest.json').is_file())
            self.assertTrue((output / 'START-HERE.txt').is_file())
            mapping = next(row for row in report['files'] if row['kind'] == 'media')
            self.assertEqual(mapping['archivePath'], 'media/' + ASSET)
            self.assertEqual(mapping['recordID'], ASSET)
            self.assertEqual((output / mapping['recoveredPath']).read_bytes(), payload)
            self.assertFalse((output / 'root/media' / ASSET).exists())

    def test_unsafe_duplicate_unicode_and_reserved_names_never_escape_or_overwrite(self):
        names = ['../escape', '/absolute', 'a/b', 'a\\b', 'CON', 'photo.jpg', 'PHOTO.jpg', 'café.jpg', 'cafe\u0301.jpg', '.hidden', 'x' * 400]
        meta = metadata(); files = {}
        for index, name in enumerate(names):
            item = asset_record(); item.update(id=f'12345678-1234-4321-ABCD-{index:012X}', name=name, fileExtension='.jpg', thumbnail=None)
            item['payload'] = 'media/' + item['id']; meta['assets'].append(item)
            files[item['payload']] = ('payload-' + str(index)).encode()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); output, report = self.run_recovery(root, archive(meta, files))
            paths = [row['recoveredPath'] for row in report['files'] if row['kind'] == 'media']
            self.assertEqual(len(paths), len(names))
            self.assertEqual(len({unicodedata.normalize('NFD', path).casefold() for path in paths}), len(names))
            for index, path in enumerate(paths):
                target = output / path
                self.assertEqual(target.parent, output / 'Library/Media')
                self.assertFalse(target.name.startswith('.'))
                self.assertTrue(target.name.endswith('.jpg'))
                self.assertLess(len(unicodedata.normalize('NFD', target.name).encode()), 255)
                self.assertEqual(target.read_bytes(), ('payload-' + str(index)).encode())
            self.assertFalse((root / 'escape').exists())
            self.assertEqual([r['name'] for r in json.loads((output / 'root/metadata.json').read_text())['assets']], names)

    def test_protected_and_inherited_album_names_form_nested_folders(self):
        inherited = '34567890-3456-4321-ABCD-123456789ABC'
        child = metadata(ALBUM, 'root')
        child['albums'] = [{'id': ALBUM, 'parentID': None, 'name': 'Private trip', 'protection': 'password', 'createdAt': 42},
            {'id': inherited, 'parentID': ALBUM, 'name': 'Beach', 'protection': 'inherited', 'createdAt': 43}]
        item = asset_record(); item.update(name='clip.mp4', fileExtension='.mp4', thumbnail=None, albumID=inherited)
        child['assets'] = [item]
        outer = metadata(); outer['children'] = [ALBUM]
        child_data = archive(child, {item['payload']: b'public video fixture'})
        with tempfile.TemporaryDirectory() as folder:
            output, report = self.run_recovery(Path(folder), archive(outer, {'protected/' + ALBUM + '.tar.age': child_data}))
            self.assertTrue(report['allProtectedDomainsRecovered'])
            self.assertEqual((output / 'Library/Albums/Private trip/Beach/clip.mp4').read_bytes(), b'public video fixture')
            self.assertTrue((output / 'root/protected' / (ALBUM + '.tar.age')).exists())
        with tempfile.TemporaryDirectory() as folder:
            output, report = self.run_recovery(Path(folder), archive(outer, {'protected/' + ALBUM + '.tar.age': child_data}), outer_only=True)
            self.assertFalse(report['allProtectedDomainsRecovered'])
            self.assertFalse((output / 'Library/Albums/Private trip').exists())

    def test_raw_layout_preserves_previous_archive_paths(self):
        meta = metadata(); item = asset_record(); meta['assets'] = [item]
        with tempfile.TemporaryDirectory() as folder:
            output, report = self.run_recovery(Path(folder), archive(meta, {item['payload']: b'raw', item['thumbnail']: b'thumb'}), raw_layout=True)
            self.assertEqual(report['layout'], 'raw')
            self.assertEqual((output / 'root' / item['payload']).read_bytes(), b'raw')
            self.assertFalse((output / 'Library').exists())

    def test_naming_failure_cleans_only_owned_stage_and_preserves_backup(self):
        meta = metadata(); item = asset_record(); item['thumbnail'] = None; meta['assets'] = [item]
        data = archive(meta, {item['payload']: b'public'})
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); source = root / 'source.age'; source.write_bytes(data)
            output = root / 'recovered'
            with patch('backup_recovery.subprocess.run', side_effect=fixtures.BackupRecoveryTests.fake_age), patch('backup_recovery.publish', side_effect=OSError('simulated file naming failure')):
                with self.assertRaises(OSError): recover(source, output, 'fixture-age')
            self.assertEqual(source.read_bytes(), data)
            self.assertFalse(output.exists())
            self.assertFalse((root / 'recovered.partial').exists())


if __name__ == '__main__':
    unittest.main()
