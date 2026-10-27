#!/usr/bin/env python3
"""Generate the app's artwork assets in the warm editorial style.

The style: warm paper, flat colour fields, hand-drawn ink, one accent. The
drawings are authored as SVG (resolution independent) and rendered to PNG with
QuickLook (WebKit), which honours alpha — the app supplies the surface, the
artwork supplies the ink.

Assets:
  Artwork/EmptyChatArt   the empty chat (a horizon with a rising sun)
  Artwork/PairingArt     pairing (the lens mark)
  Artwork/SessionEmptyArt  a session list with nothing in it

Run:  python3 scripts/generate_app_artwork.py
"""

from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import tempfile

REPO = pathlib.Path(__file__).resolve().parent.parent
ASSETS = REPO / "OpenCodeClient" / "OpenCodeClient" / "Assets.xcassets" / "Artwork"
MASTERS = REPO / "docs" / "design" / "artwork" / "app"

PARCHMENT = "#F7F2EA"
IVORY = "#FBF8F2"
CLAY = "#E0AE95"
TERRA = "#C96442"
SAGE = "#9AA084"
INK = "#1B1A18"
GREY = "#C8C3BA"

GRAIN = """
  <filter id="grain" x="0" y="0" width="100%" height="100%">
    <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="4" stitchTiles="stitch"/>
    <feColorMatrix type="saturate" values="0"/>
  </filter>
  <filter id="soft" x="-40%" y="-40%" width="180%" height="180%">
    <feGaussianBlur stdDeviation="16"/>
  </filter>
"""


def doc(body: str, size: int = 1024) -> str:
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">
  <defs>{GRAIN}</defs>
  {body}
</svg>
"""


def empty_chat() -> str:
    """A horizon with a rising sun — the empty chat."""
    return doc(f"""
  <ellipse cx="512" cy="560" rx="430" ry="300" fill="{CLAY}" opacity="0.28" filter="url(#soft)"/>
  <path d="M104 640 A408 408 0 0 1 920 640 Z" fill="{SAGE}" opacity="0.55"/>
  <path d="M256 640 A256 256 0 0 1 768 640 Z" fill="{TERRA}" opacity="0.42"/>
  <path d="M388 640 A124 124 0 0 1 636 640 Z" fill="{CLAY}" opacity="0.85"/>
  <circle cx="512" cy="470" r="86" fill="{IVORY}" stroke="{INK}" stroke-opacity="0.22" stroke-width="4"/>
  <line x1="88" y1="642" x2="936" y2="642" stroke="{INK}" stroke-opacity="0.28" stroke-width="4"/>
  <g fill="{INK}" fill-opacity="0.34">
    <circle cx="196" cy="196" r="9"/><circle cx="318" cy="128" r="6"/>
    <circle cx="770" cy="216" r="8"/><circle cx="864" cy="140" r="5"/>
  </g>
""")


def pairing() -> str:
    """The lens mark: two overlapping fields, the slash, the orbit."""
    return doc(f"""
  <circle cx="512" cy="512" r="300" fill="{CLAY}" opacity="0.4" filter="url(#soft)"/>
  <circle cx="452" cy="452" r="228" fill="{CLAY}"/>
  <circle cx="596" cy="586" r="150" fill="{SAGE}" opacity="0.85"/>
  <circle cx="512" cy="512" r="330" fill="none" stroke="{INK}" stroke-opacity="0.22" stroke-width="4"/>
  <path d="M470 318 L556 706" stroke="{INK}" stroke-width="24" stroke-linecap="round"/>
  <circle cx="512" cy="512" r="30" fill="{IVORY}"/>
""")


def session_empty() -> str:
    """An empty session list: ruled lines with nothing written on them."""
    return doc(f"""
  <g stroke="{INK}" stroke-opacity="0.32" stroke-width="5" stroke-linecap="round">
    <line x1="288" y1="380" x2="736" y2="380"/>
    <line x1="288" y1="512" x2="736" y2="512"/>
    <line x1="288" y1="644" x2="736" y2="644"/>
  </g>
  <circle cx="196" cy="380" r="12" fill="{CLAY}"/>
  <circle cx="196" cy="512" r="12" fill="{SAGE}" opacity="0.7"/>
  <circle cx="196" cy="644" r="12" fill="{GREY}"/>
""")


# Distinct names: the catalog already ships the hand-drawn set
# (EmptyChatArt, PairingArt, ...). These are the flat-geometry pieces.
ASSETS_TO_RENDER = {
    "HorizonArt": empty_chat,
    "LensArt": pairing,
    "RulesArt": session_empty,
}

SIZES = (("3x", 1024), ("2x", 683), ("1x", 341))


def render(svg_text: str, out: pathlib.Path, size: int) -> None:
    with tempfile.TemporaryDirectory(dir=REPO / ".occlient" / "artwork-tmp") as tmp:
        tmp_path = pathlib.Path(tmp)
        svg_path = tmp_path / "art.svg"
        svg_path.write_text(svg_text)
        page = tmp_path / "art.html"
        page.write_text(
            f"""<!DOCTYPE html><html><head><meta charset="utf-8"><style>
html,body{{margin:0;padding:0;background:transparent}}
.art{{width:{size}px;height:{size}px}}
.art svg{{display:block;width:{size}px;height:{size}px}}
</style></head><body><div class="art">{svg_text}</div></body></html>"""
        )
        subprocess.run(
            ["qlmanage", "-t", "-s", str(size), "-o", str(tmp_path), str(svg_path)],
            check=True, capture_output=True,
        )
        produced = tmp_path / "art.svg.png"
        if not produced.exists():
            raise SystemExit(f"QuickLook produced no image for {svg_path}")
        out.write_bytes(produced.read_bytes())


def main() -> int:
    (REPO / ".occlient" / "artwork-tmp").mkdir(parents=True, exist_ok=True)
    MASTERS.mkdir(parents=True, exist_ok=True)
    for name, builder in ASSETS_TO_RENDER.items():
        markup = builder()
        (MASTERS / f"{name.lower()}.svg").write_text(markup)
        folder = ASSETS / f"{name}.imageset"
        folder.mkdir(parents=True, exist_ok=True)
        images = []
        for scale, px in SIZES:
            out = folder / f"{name}@{scale}.png"
            render(markup, out, px)
            images.append({"filename": out.name, "idiom": "universal", "scale": scale})
        (folder / "Contents.json").write_text(
            json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n"
        )
        print(f"  {name}")
    print(f"artwork written to {ASSETS}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
