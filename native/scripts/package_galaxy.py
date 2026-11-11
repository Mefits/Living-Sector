"""Create the portable build from the two compiled native binaries and the source tree."""
from pathlib import Path
import os
import sys
import zipfile

root = Path(__file__).resolve().parents[1]
output = Path(sys.argv[1]).resolve()
base = 'Living-Sector-Galaxy-0.2'
for binary in ('Genesis-Server.exe', 'genesis-server-linux'):
    if not (root / binary).is_file():
        raise SystemExit(f'Missing compiled binary: {binary}')
with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    for directory, subdirectories, files in os.walk(root):
        subdirectories[:] = sorted(d for d in subdirectories if d not in {'target', '.git', 'node_modules', '__pycache__'})
        for filename in sorted(files):
            if filename.startswith('.') or filename.endswith(('.db', '.db-wal', '.db-shm', '.sqlite', '.log')):
                continue
            path = Path(directory) / filename
            if not path.is_file():
                continue
            entry = f'{base}/{path.relative_to(root).as_posix()}'
            if path.suffix.lower() == '.cmd':
                # cmd.exe expects Windows line endings.
                archive.writestr(entry, path.read_text().replace('\n', '\r\n'))
            else:
                archive.write(path, entry)
with zipfile.ZipFile(output) as archive:
    if bad := archive.testzip():
        raise SystemExit(f'Invalid archive entry: {bad}')
    print(f'{output.name}: {len(archive.namelist())} files, {output.stat().st_size:,} bytes')
