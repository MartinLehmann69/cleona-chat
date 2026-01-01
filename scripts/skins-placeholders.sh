#!/usr/bin/env bash
# Regenerates placeholder WebP skin assets using Python + Pillow.
# Usage: ./scripts/skins-placeholders.sh
# Idempotent — safe to re-run; overwrites existing placeholders.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$REPO_ROOT" <<'PYEOF'
import sys
from pathlib import Path
from PIL import Image

REPO_ROOT = Path(sys.argv[1])

SKINS = ['ocean', 'sunset', 'forest', 'amethyst', 'fire', 'storm', 'gold']
SIZES = {
    'hero':   (1200, 800),
    'avatar': (200,  200),
    'fab':    (200,  200),
}

GREY = (128, 128, 128)

for skin in SKINS:
    skin_dir = REPO_ROOT / 'assets' / 'skins' / skin
    skin_dir.mkdir(parents=True, exist_ok=True)
    for asset, (w, h) in SIZES.items():
        out_path = skin_dir / f'{asset}.webp'
        im = Image.new('RGB', (w, h), GREY)
        im.save(str(out_path), 'WEBP', quality=70)

print('Created placeholders for 7 skins × 3 assets = 21 WebPs')
PYEOF
