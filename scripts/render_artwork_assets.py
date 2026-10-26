#!/usr/bin/env python3
"""Render the app's artwork assets as transparent ink drawings.

The scene masters paint a warm colour field so they read as tiles in the
design contact sheet. Inside the app that field would show up as a hard
square block, so the shipped imagesets drop the background rect: only the ink
drawing remains, floating on the app's own parchment surface.

The tinted versions stay available by rendering the master unchanged.

Run:  python3 scripts/render_artwork_assets.py
"""

from __future__ import annotations

import importlib.util
import json
import subprocess
import pathlib
import re
import sys
import tempfile

REPO = pathlib.Path(__file__).resolve().parent.parent
ASSETS = REPO / "OpenCodeClient" / "OpenCodeClient" / "Assets.xcassets"
MASTERS = REPO / "docs" / "design" / "artwork"

_spec = importlib.util.spec_from_file_location("generate_artwork", REPO / "scripts" / "generate_artwork.py")
gen = importlib.util.module_from_spec(_spec)
sys.modules["generate_artwork"] = gen
_spec.loader.exec_module(gen)

BACKGROUND_RECT = re.compile(r'\s*<rect width="1024" height="1024" fill="#[0-9A-Fa-f]{6}"/>')

SIZES = (("3x", 1024), ("2x", 683), ("1x", 341))


# The masters are named in lower case; the asset names are the camel-cased
# ones the app refers to.
ASSET_NAMES = {
    "agentart": "AgentArt",
    "empty-chat": "EmptyChatArt",
    "filesart": "FilesArt",
    "healthart": "HealthArt",
    "historyart": "HistoryArt",
    "navigationart": "NavigationArt",
    "nosessionsart": "NoSessionsArt",
    "offlineart": "OfflineArt",
    "pairingart": "PairingArt",
    "permissionart": "PermissionArt",
    "searchart": "SearchArt",
    "slidersart": "SlidersArt",
    "terminalart": "TerminalArt",
    "toolsart": "ToolsArt",
    "voiceart": "VoiceArt",
}


def asset_name(stem: str) -> str:
    """`filesart` -> `FilesArt`, `scene-agentart` -> `AgentArt`."""
    stem = stem.replace("scene-", "")
    if stem in ASSET_NAMES:
        return ASSET_NAMES[stem]
    raise SystemExit(f"no asset name for master {stem!r} — add it to ASSET_NAMES")


def transparent(markup: str) -> str:
    """The same drawing without its background field."""
    return BACKGROUND_RECT.sub("", markup, count=1)


def render_png(markup: str, out: pathlib.Path, size: int) -> None:
    """Render an SVG to a transparent PNG.

    QuickLook paints an opaque white canvas, which would show up in the app as
    a white square behind every drawing. Chrome with a transparent default
    background keeps only the ink.
    """
    with tempfile.TemporaryDirectory(dir=REPO / ".occlient" / "artwork-tmp") as tmp:
        tmp_path = pathlib.Path(tmp)
        svg_path = tmp_path / "art.svg"
        svg_path.write_text(markup)
        gen.validate(svg_path)
        page = tmp_path / "art.html"
        page.write_text(
            f"""<!DOCTYPE html><html><head><meta charset="utf-8"><style>
html,body{{margin:0;padding:0;background:transparent}}
.art{{width:{size}px;height:{size}px}}
.art svg{{display:block;width:{size}px;height:{size}px}}
</style></head><body><div class="art">{markup}</div></body></html>"""
        )
        subprocess.run(
            [
                gen.chrome(), "--headless", "--disable-gpu", "--hide-scrollbars",
                "--default-background-color=00000000", "--virtual-time-budget=2000",
                f"--screenshot={out}", f"--window-size={size},{size}",
                f"file://{page}",
            ],
            check=True, capture_output=True,
        )


def ensure_exact_case(path: pathlib.Path) -> None:
    """Give the file the exact case of its path.

    macOS's filesystem is case-insensitive by default and keeps the name a
    file was first created with: rendering over "filesArt@3x.png" through the
    path "FilesArt@3x.png" leaves the old spelling on disk. actool then
    cannot find the file the Contents.json names, the imageset compiles
    empty, and the artwork renders as nothing at runtime. Renaming through a
    staging name is what actually changes the directory entry.
    """
    if path.name in {entry.name for entry in path.parent.iterdir()}:
        return
    staging = path.with_name(f".{path.name}.renaming")
    path.rename(staging)
    staging.rename(path)


def render_imageset(name: str, markup: str) -> None:
    folder = ASSETS / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=REPO / ".occlient" / "artwork-tmp") as tmp:
        tmp_path = pathlib.Path(tmp)
        master = tmp_path / f"{name}.svg"
        master.write_text(markup)
        gen.validate(master)
        images = []
        for scale, px in SIZES:
            out = folder / f"{name}@{scale}.png"
            render_png(markup, out, px)
            ensure_exact_case(out)
            images.append({"filename": out.name, "idiom": "universal", "scale": scale})
        (folder / "Contents.json").write_text(
            json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n"
        )


def main() -> int:
    (REPO / ".occlient" / "artwork-tmp").mkdir(parents=True, exist_ok=True)
    written = []
    for master in sorted(MASTERS.glob("*.svg")):
        if master.stem.replace("scene-", "") not in ASSET_NAMES:
            continue
        name = asset_name(master.stem)
        render_imageset(name, transparent(master.read_text()))
        written.append(name)
    # The empty-chat scene ships with its own soft halo; keep the field off too.
    print(f"{len(written)} assets rendered transparent: {', '.join(written)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
