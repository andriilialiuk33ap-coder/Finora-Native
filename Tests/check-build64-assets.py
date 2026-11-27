#!/usr/bin/env python3
import json
import struct
from pathlib import Path
root = Path(__file__).resolve().parent.parent / 'Finora' / 'Assets.xcassets'
for brand in 'pumb mono privat abank spotify netflix silpo atb youtube icloud'.split():
    folder = root / f'Brand-{brand}.imageset'
    meta = json.loads((folder / 'Contents.json').read_text())
    assert meta['info']['version'] == 1
    assert len(meta['images']) == 1 and meta['images'][0]['idiom'] == 'universal'
    data = (folder / meta['images'][0]['filename']).read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    assert struct.unpack('>II', data[16:24]) == (192, 192)
    print(f'PASS: bundled graphic asset {brand}')
