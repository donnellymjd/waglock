"""Readable names for already verified recovery staging; never parse archive paths here."""
import hashlib
import re
import unicodedata


class LayoutError(ValueError):
    pass


def component(value, fallback):
    value = ''.join('_' if char in '/\\:*?"<>|' or unicodedata.category(char) in ('Cc', 'Cs') else char for char in value)
    value = value.strip(' .')
    if not value:
        value = fallback
    if value.split('.')[0].upper() in {'CON', 'PRN', 'AUX', 'NUL', 'CLOCK$', *(f'COM{i}' for i in range(1, 10)), *(f'LPT{i}' for i in range(1, 10))}:
        value = '_' + value
    # macOS may store decomposed UTF-8; leave room for extensions and collision suffixes.
    while len(unicodedata.normalize('NFD', value).encode('utf-8')) > 180:
        value = value[:-1]
    return value.rstrip(' .') or fallback


def extension(value, source):
    value = value.lstrip('.')
    if re.fullmatch('[A-Za-z0-9]{1,16}', value):
        return '.' + value
    with source.open('rb') as stream:
        header = stream.read(32)
    if header.startswith(b'\xff\xd8\xff'): return '.jpg'
    if header.startswith(b'\x89PNG\r\n\x1a\n'): return '.png'
    if header.startswith((b'GIF87a', b'GIF89a')): return '.gif'
    if header.startswith(b'%PDF-'): return '.pdf'
    if header[4:8] == b'ftyp':
        brand = header[8:12]
        if brand == b'qt  ': return '.mov'
        if brand in (b'heic', b'heix', b'hevc', b'hevx', b'mif1'): return '.heic'
        if brand in (b'avif', b'avis'): return '.avif'
        return '.mp4'
    return '.bin'


def readable_layout(stage, domains, move):
    """Move verified payloads without copies/overwrites; map original archive names.

    Original metadata/manifests and nested ciphertext stay in their domain paths.
    Their paths describe the authenticated archive, while the report records the
    final readable locations. Call only after all requested domains verify.
    """
    library = stage / 'Library'
    library.mkdir(mode=0o700)
    occupied, mappings, folders = {}, [], {}

    def reserve(parent, title, suffix='', fallback='Untitled'):
        base = component(title, fallback)
        if suffix and base.lower().endswith(suffix.lower()):
            base = base[:-len(suffix)] or fallback
        used = occupied.setdefault(parent, set())
        number = 1
        while True:
            name = base + ('' if number == 1 else f' ({number})') + suffix
            key = unicodedata.normalize('NFD', name).casefold()
            if key not in used:
                used.add(key)
                return parent / name
            number += 1

    albums = {a['id']: a for _, meta in domains for a in meta['albums']}
    pending = dict(albums)
    if pending:
        album_root = library / 'Albums'; album_root.mkdir(mode=0o700)
    while pending:
        available = sorted(key for key, album in pending.items() if album['parentID'] is None or album['parentID'] in folders)
        if not available:
            raise LayoutError('Cannot reconstruct the verified album hierarchy')
        for key in available:
            album = pending.pop(key)
            parent = folders.get(album['parentID'], album_root)
            folder = reserve(parent, album['name'], fallback='Album-' + key)
            folder.mkdir(mode=0o700)
            folders[key] = folder

    def relocate(source, target, meta, path, record, kind):
        move(source, target)
        mappings.append({'domain': meta['domain'], 'archivePath': path,
            'recoveredPath': target.relative_to(stage).as_posix(), 'recordID': record, 'kind': kind})

    for target, meta in domains:
        for asset in meta['assets']:
            source = target / asset['payload']
            if asset['albumID'] is None:
                parent = library / 'Media'; parent.mkdir(mode=0o700, exist_ok=True)
            else:
                parent = folders[asset['albumID']]
            destination = reserve(parent, asset['name'], extension(asset['fileExtension'], source), 'File-' + asset['id'])
            relocate(source, destination, meta, asset['payload'], asset['id'], 'media')
            if asset['thumbnail'] is not None:
                source = target / asset['thumbnail']
                destination = source.with_name(source.name + extension('', source))
                relocate(source, destination, meta, asset['thumbnail'], asset['id'], 'thumbnail')
        for kind, records in (('Notes', meta['notes']), ('Drafts', meta['drafts'])):
            if not records:
                continue
            parent = library / kind; parent.mkdir(mode=0o700, exist_ok=True)
            for row in records:
                identifier = row.get('id', row.get('origin'))
                destination = reserve(parent, row['title'], '.md', kind[:-1] + '-' + identifier)
                data = row['content'].encode('utf-8')
                with destination.open('xb') as output:
                    destination.chmod(0o600); output.write(data)
                mappings.append({'domain': meta['domain'], 'archivePath': 'metadata.json',
                    'recoveredPath': destination.relative_to(stage).as_posix(), 'recordID': identifier,
                    'kind': kind.lower(), 'sha256': hashlib.sha256(data).hexdigest()})
    (stage / 'START-HERE.txt').write_text(
        'Your recovered files are in Library. Photos, videos and other files use their original names and extensions.\n'
        'Albums are arranged under Library/Albums. Notes and saved drafts are Markdown text files.\n'
        'Some unsafe, duplicate or very long names are adjusted for this computer. Original names and all recorded metadata remain in each domain metadata.json.\n'
        'recovery-report.json maps authenticated archive paths to recovered filenames. Manifests describe the archive before readable naming.\n'
        'Protected content appears here only after its separate password was accepted. Outer-only recovery can leave unopened child archives.\n', encoding='utf-8')
    return mappings
