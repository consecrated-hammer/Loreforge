#!/usr/bin/env python3
"""Check the pinned transport sources and shipped licence notices."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / 'Libs/transport-vendor.json').read_text())
for name, expected in manifest['sha256'].items():
    actual = hashlib.sha256((root / name).read_bytes()).hexdigest()
    if actual != expected:
        raise SystemExit(f'{name}: does not match the pinned upstream file')
pkgmeta = (root / '.pkgmeta').read_text()
plain_copy = pkgmeta.split('plain-copy:', 1)[1].split('ignore:', 1)[0]
for directory in ['Libs/LibStub', 'Libs/ChatThrottleLib', 'Libs/LibDeflate', 'Libs/LibSerialize']:
    if f'  - {directory}\n' not in plain_copy:
        raise SystemExit(f'{directory}: missing packager plain-copy protection')
print(f'Transport vendor: all {len(manifest["sha256"])} hashes and packaging protections match')
