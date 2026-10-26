#!/usr/bin/env python3
"""Hand-drawn artwork scenes for OpenCodex.

Extends the drawing system in `generate_artwork.py` (rough strokes, the
doubled pen line, the open hand) with a family of scenes the app can use:
empty states, capability surfaces, settings gestures.

Every scene is a flat warm field with an ink drawing on top — the reference
language: paper, clay, grey, one black pen.

Run:  python3 scripts/generate_artwork_scenes.py
"""

from __future__ import annotations

import importlib.util
import math
import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
ASSETS = REPO / "OpenCodeClient" / "OpenCodeClient" / "Assets.xcassets"

# Borrow the drawing primitives from the icon generator (single source of
# truth for the pen language). The module is imported, not edited.
_spec = importlib.util.spec_from_file_location("generate_artwork", REPO / "scripts" / "generate_artwork.py")
gen = importlib.util.module_from_spec(_spec)
sys.modules["generate_artwork"] = gen
_spec.loader.exec_module(gen)

rough_path = gen.rough_path
rough_line = gen.rough_line
rough_circle = gen.rough_circle
ink = gen.ink
hand = gen.hand
svg = gen.svg
render = gen.render
validate = gen.validate

INK = gen.INK
PARCHMENT = gen.PARCHMENT
IVORY = gen.IVORY
PAPER_DEEP = gen.PAPER_DEEP
CLAY = gen.CLAY
CLAY_LIGHT = gen.CLAY_LIGHT
TERRA = gen.TERRA
GREY = gen.GREY
BLUEGREY = gen.BLUEGREY
SAGE = gen.SAGE


def scene(background: str, drawing: str, size: int = 1024) -> str:
    """One artwork tile: a flat warm field with an ink drawing on it."""
    return svg(f"""
  <rect width="{size}" height="{size}" fill="{background}"/>
  {drawing}
""")


def strokes(*paths: str, width: float = 7.0, offset: float = 2.6) -> str:
    """Several pen strokes, each with the reference's doubled line."""
    return "\n".join(ink(p, width=width, offset=offset) for p in paths)


# --- individual scenes ------------------------------------------------------

def sliders_art() -> str:
    """Three hand-drawn slider tracks — the settings gesture."""
    tracks = []
    knobs = [(566, 352), (438, 512), (642, 672)]
    for index, (kx, ky) in enumerate(knobs):
        tracks.append(rough_line(300, ky, 724, ky, seed=60 + index, jitter=4, segments=8, bow=3))
        tracks.append(rough_circle(kx, ky, 34, seed=70 + index, jitter=3, segments=16))
    return scene(GREY, strokes(*tracks, width=9, offset=3))


def search_art() -> str:
    """A magnifier, drawn in one breath."""
    lens = rough_circle(452, 420, 158, seed=80, jitter=6, segments=26)
    handle = rough_line(566, 534, 712, 680, seed=81, jitter=5, segments=8, bow=-6)
    return scene(PAPER_DEEP, strokes(lens, handle, width=10, offset=3))


def voice_art() -> str:
    """A microphone: capsule, cradle arc and stand."""
    capsule = rough_path(
        [(470, 250), (512, 236), (556, 252), (562, 380), (556, 470), (512, 486), (468, 470), (462, 380), (462, 262)],
        seed=90, jitter=5, close=True)
    cradle = rough_circle(512, 430, 150, seed=91, jitter=4, segments=22, start=0.35, end=2.79, close=False)
    stand = rough_line(512, 580, 512, 700, seed=92, jitter=4, segments=6)
    foot = rough_line(430, 702, 594, 702, seed=93, jitter=4, segments=6)
    return scene(CLAY_LIGHT, strokes(capsule, cradle, stand, foot, width=8, offset=3))


def health_art() -> str:
    """A pulse line through a circle — the Health capability."""
    pulse = rough_path(
        [(240, 512), (368, 512), (416, 404), (472, 616), (524, 470), (572, 512), (784, 512)],
        seed=100, jitter=4)
    ring = rough_circle(512, 512, 250, seed=101, jitter=7, segments=30)
    return scene(IVORY, strokes(ring, pulse, width=8, offset=3))


def navigation_art() -> str:
    """A map pin with a route."""
    pin = rough_circle(512, 400, 150, seed=110, jitter=5, segments=24)
    tail = rough_path([(462, 512), (512, 640), (562, 512)], seed=111, jitter=4, close=False)
    route = rough_path([(210, 790), (330, 720), (430, 760), (520, 690), (640, 726), (760, 660)], seed=112, jitter=6)
    return scene(SAGE, strokes(pin, tail, route, width=8, offset=3))


def files_art() -> str:
    """A folder with a corner tab, and a sheet sliding out."""
    # Folder body: a rectangle whose top edge steps down at the tab.
    folder = rough_path(
        [(250, 400), (250, 690), (774, 690), (774, 400), (520, 400), (470, 336), (250, 336)],
        seed=120, jitter=5, close=True)
    # A sheet tucked behind the folder's top edge.
    sheet = rough_path([(430, 250), (640, 250), (640, 336), (430, 336)], seed=121, jitter=4, close=True)
    return scene(BLUEGREY, strokes(folder, sheet, width=8, offset=3))


def pairing_art() -> str:
    """A phone showing a code, about to meet a server."""
    # Phone: rounded body with a speaker slot.
    phone = rough_path(
        [(280, 210), (520, 210), (520, 730), (280, 730)], seed=180, jitter=5, close=True)
    slot = rough_line(360, 262, 440, 262, seed=184, jitter=2, segments=4)
    # The code: a square with corner marks.
    code = rough_path([(620, 300), (860, 300), (860, 540), (620, 540)], seed=181, jitter=4, close=True)
    corner_a = rough_path([(620, 360), (620, 300), (680, 300)], seed=185, jitter=2, close=False)
    corner_b = rough_path([(800, 300), (860, 300), (860, 360)], seed=186, jitter=2, close=False)
    corner_c = rough_path([(860, 480), (860, 540), (800, 540)], seed=187, jitter=2, close=False)
    corner_d = rough_path([(680, 540), (620, 540), (620, 480)], seed=188, jitter=2, close=False)
    # A dashed line between them.
    dashes = [rough_line(540, 430, 606, 430, seed=182, jitter=2, segments=4),
              rough_line(586, 486, 606, 486, seed=183, jitter=2, segments=3)]
    return scene(PARCHMENT, strokes(phone, slot, code, corner_a, corner_b, corner_c, corner_d,
                                    *dashes, width=8, offset=3))


def offline_art() -> str:
    """A plug pulled out of its socket."""
    # Socket: a box with a slot.
    socket = rough_path([(240, 380), (240, 620), (470, 620), (470, 380)], seed=130, jitter=4, close=True)
    slot = rough_line(300, 500, 410, 500, seed=134, jitter=3, segments=4)
    # Plug: body plus two prongs, pulled away to the right.
    plug = rough_path([(620, 400), (700, 430), (700, 570), (620, 600)], seed=132, jitter=5, close=True)
    prong_a = rough_line(700, 470, 790, 470, seed=135, jitter=3, segments=4)
    prong_b = rough_line(700, 530, 790, 530, seed=136, jitter=3, segments=4)
    # Gap marker between socket and plug.
    gap = rough_line(500, 420, 590, 420, seed=137, jitter=2, segments=4)
    return scene(CLAY, strokes(socket, slot, plug, prong_a, prong_b, gap, width=9, offset=3))


def permission_art() -> str:
    """A key, offered."""
    ring = rough_circle(360, 470, 118, seed=140, jitter=5, segments=22)
    shaft = rough_line(470, 545, 760, 700, seed=141, jitter=4, segments=8)
    tooth_a = rough_line(660, 648, 700, 588, seed=142, jitter=3, segments=4)
    tooth_b = rough_line(716, 678, 756, 618, seed=143, jitter=3, segments=4)
    return scene(PARCHMENT, strokes(ring, shaft, tooth_a, tooth_b, width=9, offset=3))


def tools_art() -> str:
    """A gear: the agent runs tools."""
    ring = rough_circle(512, 512, 170, seed=170, jitter=5, segments=24)
    teeth = []
    for index in range(8):
        angle = index * (2 * math.pi / 8) + 0.2
        inner = 170
        outer = 250
        teeth.append(rough_line(
            512 + math.cos(angle) * inner, 512 + math.sin(angle) * inner,
            512 + math.cos(angle) * outer, 512 + math.sin(angle) * outer,
            seed=180 + index, jitter=3, segments=4))
    hub = rough_circle(512, 512, 62, seed=190, jitter=4, segments=14)
    return scene(BLUEGREY, strokes(ring, *teeth, hub, width=8, offset=3))


def no_sessions_art() -> str:
    """An empty session list: ruled lines with nothing on them."""
    rules = [rough_line(280, 380, 744, 380, seed=150, jitter=4, segments=7),
             rough_line(280, 512, 744, 512, seed=151, jitter=4, segments=7),
             rough_line(280, 644, 744, 644, seed=152, jitter=4, segments=7)]
    return scene(IVORY, strokes(*rules, width=7, offset=2.5))


def history_art() -> str:
    """A loop of time: a circle with an arrow head."""
    loop = rough_circle(512, 500, 210, seed=160, jitter=6, segments=28, start=-1.9, end=2.6, close=False)
    head = rough_path([(690, 250), (742, 214), (700, 290)], seed=161, jitter=4, close=True)
    hand_line = rough_line(512, 500, 512, 368, seed=162, jitter=3, segments=5)
    hand_line2 = rough_line(512, 500, 620, 552, seed=163, jitter=3, segments=5)
    return scene(GREY, strokes(loop, head, hand_line, hand_line2, width=8, offset=3))


def terminal_art() -> str:
    """A terminal window: the code the agent writes."""
    window = rough_path([(240, 260), (784, 260), (784, 740), (240, 740)], seed=200, jitter=5, close=True)
    title = rough_line(240, 340, 784, 340, seed=201, jitter=3, segments=6)
    prompt = rough_path([(320, 430), (360, 470), (320, 510)], seed=202, jitter=2, close=False)
    caret = rough_line(420, 512, 620, 512, seed=203, jitter=3, segments=5)
    caret2 = rough_line(420, 580, 540, 580, seed=204, jitter=3, segments=4)
    return scene(IVORY, strokes(window, title, prompt, caret, caret2, width=8, offset=3))


def agent_art() -> str:
    """A spark: the agent."""
    rays = []
    for index in range(8):
        angle = index * (2 * math.pi / 8) + 0.35
        rays.append(rough_line(
            512 + math.cos(angle) * 210, 512 + math.sin(angle) * 210,
            512 + math.cos(angle) * 320, 512 + math.sin(angle) * 320,
            seed=210 + index, jitter=4, segments=4))
    core = rough_circle(512, 512, 150, seed=220, jitter=6, segments=22)
    return scene(SAGE, strokes(core, *rays, width=8, offset=3))


# The icon generator owns the first set of scenes; this script adds the ones
# it does not cover yet. Both draw from the same primitives, so the pen
# language stays identical.
SCENES = {
    "TerminalArt": terminal_art,
    "AgentArt": agent_art,
}


def write_imageset(folder: pathlib.Path, name: str, svg_source: str,
                   sizes=(("3x", 1024), ("2x", 683), ("1x", 341))) -> None:
    import json
    import shutil
    import tempfile

    folder.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=REPO / ".occlient" / "artwork-tmp") as tmp:
        tmp_path = pathlib.Path(tmp)
        master = tmp_path / f"{name}.svg"
        master.write_text(svg_source)
        validate(master)
        images = []
        for scale, px in sizes:
            out = folder / f"{name}@{scale}.png"
            render(master, out, px)
            images.append({"filename": out.name, "idiom": "universal", "scale": scale})
        (folder / "Contents.json").write_text(
            json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")


def main() -> int:
    (REPO / ".occlient" / "artwork-tmp").mkdir(parents=True, exist_ok=True)
    masters = REPO / "docs" / "design" / "artwork"
    masters.mkdir(parents=True, exist_ok=True)
    group = ASSETS
    for name, builder in SCENES.items():
        markup = builder()
        (masters / f"scene-{name.lower()}.svg").write_text(markup)
        write_imageset(group / f"{name}.imageset", name, markup)
        print(f"  {name}")
    print(f"{len(SCENES)} scenes written to {group}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
