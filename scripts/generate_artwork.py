#!/usr/bin/env python3
"""Generate the OpenCodex artwork set.

The visual direction is "warm editorial": parchment surfaces, clay/sage
overlapping fields, one ink mark, paper grain. Everything here is authored as
SVG (resolution independent, easy to tune) and rendered to PNG with headless
Chrome, so the same masters produce the app icon layers and the in-app
illustrations.

Outputs (into the asset catalog):
  AppIcon.appiconset/AppIcon.png                     1024 flat icon
  AppIcon.solidimagestack/Back.../background.png     1024 back layer
  AppIcon.solidimagestack/Middle.../middle.png       1024 middle layer
  AppIcon.solidimagestack/Front.../foreground.png     1024 front layer
  EmptyChatArt.imageset/                             3x/2x/1x illustration
  PairingArt.imageset/                               3x/2x/1x illustration

Run:  python3 scripts/generate_artwork.py
"""

from __future__ import annotations

import json
import math
import pathlib
import random
import shutil
import subprocess
import sys
import tempfile

REPO = pathlib.Path(__file__).resolve().parent.parent
ASSETS = REPO / "OpenCodeClient" / "OpenCodeClient" / "Assets.xcassets"
MASTERS = REPO / "docs" / "design" / "artwork"

CHROME_CANDIDATES = [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    shutil.which("google-chrome") or "",
    shutil.which("chromium") or "",
]

# --- palette ---------------------------------------------------------------
# Warm paper and clay, the way the reference reads: flat fields, one ink.
PARCHMENT = "#F7F2EA"
IVORY = "#FBF8F2"
PAPER_DEEP = "#EFE6D8"
CLAY = "#CC785C"
CLAY_LIGHT = "#E0AE95"
TERRA = "#C96442"
GREY = "#C8C3BA"
BLUEGREY = "#B7C1C4"
SAGE = "#9AA084"
DUSK = "#2B59D1"
INK = "#1B1A18"

GRAIN_FILTER = """
  <filter id="soft" x="-40%" y="-40%" width="180%" height="180%">
    <feGaussianBlur stdDeviation="26"/>
  </filter>
  <filter id="soft2" x="-40%" y="-40%" width="180%" height="180%">
    <feGaussianBlur stdDeviation="12"/>
  </filter>
"""


def svg(body: str, size: int = 1024, extra_defs: str = "") -> str:
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">
  <defs>
    {GRAIN_FILTER}
    {extra_defs}
  </defs>
  {body}
</svg>
"""


def svg_parts(parts: list[str], size: int = 1024, extra_defs: str = "") -> str:
    """Compose several layer bodies into one document with shared defs."""
    body = "\n".join(parts)
    return svg(body, size=size, extra_defs=extra_defs)



# --- hand-drawn vocabulary -------------------------------------------------
# The reference draws with one thin, slightly imperfect pen stroke. These
# helpers turn straight geometry into that: points are jittered (seeded, so
# the output is reproducible) and smoothed through midpoints.
def _points(pts, seed, jitter):
    rng = random.Random(seed)
    return [(x + rng.uniform(-jitter, jitter), y + rng.uniform(-jitter, jitter)) for x, y in pts]


def rough_path(pts, seed=1, jitter=6.0, close=False):
    """A hand-drawn stroke through `pts`: jittered, then smoothed."""
    p = _points(pts, seed, jitter)
    if close:
        p = p + [p[0]]
    d = [f"M {p[0][0]:.1f} {p[0][1]:.1f}"]
    for i in range(1, len(p) - 1):
        mx = (p[i][0] + p[i + 1][0]) / 2
        my = (p[i][1] + p[i + 1][1]) / 2
        d.append(f"Q {p[i][0]:.1f} {p[i][1]:.1f} {mx:.1f} {my:.1f}")
    d.append(f"L {p[-1][0]:.1f} {p[-1][1]:.1f}")
    return " ".join(d)


def rough_line(x1, y1, x2, y2, seed=1, jitter=5.0, segments=6, bow=0.0):
    """A hand-drawn line, optionally bowed like a wrist-drawn stroke."""
    pts = []
    dx, dy = x2 - x1, y2 - y1
    norm = math.hypot(dx, dy) or 1.0
    px, py = -dy / norm, dx / norm
    for i in range(segments + 1):
        t = i / segments
        off = math.sin(t * math.pi) * bow
        pts.append((x1 + dx * t + px * off, y1 + dy * t + py * off))
    return rough_path(pts, seed=seed, jitter=jitter)


def rough_circle(cx, cy, r, seed=1, jitter=5.0, segments=30, start=0.0, end=2 * math.pi, close=True):
    """A hand-drawn circle or arc."""
    span = end - start
    n = max(3, int(segments * abs(span) / (2 * math.pi)))
    pts = []
    for i in range(n + 1):
        a = start + span * i / n
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return rough_path(pts, seed=seed, jitter=jitter, close=close)


def ink(d, width=7.0, offset=2.6):
    """One pen stroke plus a faint second pass — the reference's doubled line.

    `width` and `offset` are in the current user units, so a drawing authored
    in local units (the hand) stays proportional.
    """
    return (
        f'<path d="{d}" fill="none" stroke="{INK}" stroke-width="{width:.3f}" '
        f'stroke-linecap="round" stroke-linejoin="round"/>'
        f'<path d="{d}" fill="none" stroke="{INK}" stroke-width="{width * 0.36:.3f}" '
        f'stroke-linecap="round" stroke-linejoin="round" opacity="0.30" '
        f'transform="translate({offset} {offset})"/>'
    )


def hand(cx, cy, scale=1.0, flip=False, seed=11):
    """An open hand, drawn the way the reference draws them: one continuous
    line that runs up the palm, out around the thumb, over each finger and
    back down to the wrist. One stroke, not a fist of separate parts."""
    outline = [
        (-0.10, 0.44),                                   # wrist
        (-0.15, 0.28), (-0.17, 0.12), (-0.15, 0.02),     # up the palm
        (-0.28, -0.06), (-0.20, -0.10),                  # the thumb
        (-0.27, -0.31), (-0.18, -0.34), (-0.12, -0.02),   # index
        (-0.11, -0.02), (-0.11, -0.45), (-0.03, -0.47),   # middle
        (-0.02, -0.43), (0.00, -0.02),
        (0.02, -0.39), (0.09, -0.40), (0.10, -0.02),      # ring
        (0.16, -0.28), (0.22, -0.28), (0.19, -0.01),       # pinky
        (0.19, 0.14), (0.16, 0.30), (0.10, 0.44),          # down to the wrist
    ]
    stroke = ink(rough_path(outline, seed=seed, jitter=0.008), width=0.014, offset=0.005)
    mirror = " scale(-1 1)" if flip else ""
    return f'<g transform="translate({cx} {cy}) scale({scale}){mirror}">{stroke}</g>'


# --- icon layers ------------------------------------------------------------
def icon_back_body() -> str:
    """Warm paper ground: flat, one soft wash in the corner, paper grain."""
    return f"""
  <defs>
    <linearGradient id="wash" x1="0" y1="0" x2="0.4" y2="1">
      <stop offset="0" stop-color="{IVORY}"/>
      <stop offset="0.6" stop-color="{PARCHMENT}"/>
      <stop offset="1" stop-color="{PAPER_DEEP}"/>
    </linearGradient>
  </defs>
  <rect width="1024" height="1024" fill="url(#wash)"/>
  <rect width="1024" height="1024" filter="url(#grain)" opacity="0.06"/>
"""


def icon_back() -> str:
    return svg(icon_back_body())


def icon_middle_body() -> str:
    """The colour fields: a clay shape and a warm grey one, hand-drawn edges.

    Flat fills, no gradients — the reference reads as flat paper, and an app
    icon has to survive 60pt without turning to mud.
    """
    clay_shape = rough_path(
        [(470, 250), (700, 330), (760, 560), (640, 780), (420, 790), (300, 600), (320, 360)],
        seed=21, jitter=26, close=True)
    grey_shape = rough_path(
        [(620, 470), (790, 520), (800, 680), (680, 760), (560, 700), (555, 560)],
        seed=22, jitter=20, close=True)
    return f"""
  <path d="{clay_shape}" fill="{CLAY}" opacity="0.92"/>
  <path d="{grey_shape}" fill="{GREY}" opacity="0.95"/>
"""


def icon_middle() -> str:
    return svg(icon_middle_body())


def icon_front_body() -> str:
    """The ink mark, redrawn by hand: the slash, the hairline orbit, the dot."""
    orbit = rough_circle(512, 512, 332, seed=31, jitter=13, segments=44)
    slash = rough_line(466, 292, 560, 734, seed=32, jitter=7, segments=8, bow=10)
    return f"""
  <path d="{orbit}" fill="none" stroke="{INK}" stroke-width="4" stroke-opacity="0.24" stroke-linecap="round"/>
  {ink(slash, width=26, offset=3.2)}
  <circle cx="512" cy="512" r="26" fill="{IVORY}"/>
"""


def icon_front() -> str:
    return svg(icon_front_body())


# --- in-app illustrations ---------------------------------------------------
def empty_chat_art() -> str:
    """An open hand reaching out, in the reference's line language."""
    arc = rough_circle(512, 540, 392, seed=42, jitter=17, segments=40, start=3.45, end=6.05, close=False)
    arc2 = rough_circle(512, 540, 268, seed=43, jitter=13, segments=30, start=0.30, end=2.45, close=False)
    arc3 = rough_circle(512, 540, 330, seed=44, jitter=15, segments=34, start=3.9, end=5.1, close=False)
    return svg(f"""
  <defs>
    <radialGradient id="halo" cx="50%" cy="46%" r="58%">
      <stop offset="0" stop-color="{CLAY_LIGHT}" stop-opacity="0.22"/>
      <stop offset="1" stop-color="{PARCHMENT}" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <ellipse cx="512" cy="540" rx="430" ry="330" fill="url(#halo)"/>
  <path d="{arc}" fill="none" stroke="{INK}" stroke-width="5" stroke-opacity="0.22" stroke-linecap="round"/>
  <path d="{arc2}" fill="none" stroke="{INK}" stroke-width="4" stroke-opacity="0.15" stroke-linecap="round"/>
  <path d="{arc3}" fill="none" stroke="{INK}" stroke-width="3.5" stroke-opacity="0.13" stroke-linecap="round"/>
  {hand(512, 580, scale=360, flip=False, seed=51)}
  <g fill="{INK}" fill-opacity="0.34">
    <circle cx="196" cy="214" r="7"/><circle cx="286" cy="146" r="5"/>
    <circle cx="748" cy="222" r="6"/><circle cx="846" cy="158" r="4"/>
    <circle cx="614" cy="112" r="5"/>
  </g>
""")


def pairing_art() -> str:
    """Pairing: a hand reaching for the ring that links phone and server."""
    ring = rough_circle(536, 470, 196, seed=61, jitter=12, segments=38)
    blob = rough_path(
        [(300, 250), (520, 210), (730, 300), (780, 520), (630, 700), (380, 690), (250, 500)],
        seed=63, jitter=16, close=True)
    arc = rough_circle(536, 470, 286, seed=64, jitter=15, segments=34, start=3.6, end=5.9, close=False)
    return svg(f"""
  <defs>
    <radialGradient id="halo" cx="48%" cy="46%" r="58%">
      <stop offset="0" stop-color="{CLAY_LIGHT}" stop-opacity="0.26"/>
      <stop offset="1" stop-color="{PARCHMENT}" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <ellipse cx="512" cy="500" rx="430" ry="330" fill="url(#halo)"/>
  <path d="{blob}" fill="{CLAY}" opacity="0.15"/>
  <path d="{arc}" fill="none" stroke="{INK}" stroke-width="4" stroke-opacity="0.16" stroke-linecap="round"/>
  <path d="{ring}" fill="none" stroke="{INK}" stroke-width="7" stroke-opacity="0.70" stroke-linecap="round"/>
  <circle cx="536" cy="470" r="24" fill="{CLAY}"/>
  {hand(368, 700, scale=300, flip=True, seed=71)}
  <rect width="1024" height="1024" filter="url(#grain)" opacity="0.05"/>
""")


# --- rendering --------------------------------------------------------------
def chrome() -> str:
    for candidate in CHROME_CANDIDATES:
        if candidate and pathlib.Path(candidate).exists():
            return candidate
    raise SystemExit("No Chrome/Chromium found for SVG rendering")


def validate(svg_path: pathlib.Path) -> None:
    """Chrome screenshots its own error page for malformed SVG — catch it first."""
    import xml.etree.ElementTree as ET

    try:
        ET.parse(svg_path)
    except ET.ParseError as error:
        raise SystemExit(f"invalid SVG {svg_path}: {error}") from error


def render(svg_path: pathlib.Path, png_path: pathlib.Path, size: int) -> None:
    """Render an SVG to PNG with macOS QuickLook (WebKit).

    Chrome's headless screenshots are unreliable here: it paints some pages
    through its standalone-image viewer, which drops a blurred, dimmed copy of
    the artwork behind it. QuickLook renders the SVG as WebKit would.
    """
    validate(svg_path)
    with tempfile.TemporaryDirectory(dir=REPO / ".occlient" / "artwork-tmp") as out_dir:
        subprocess.run(
            ["qlmanage", "-t", "-s", str(size), "-o", out_dir, str(svg_path)],
            check=True,
            capture_output=True,
        )
        produced = pathlib.Path(out_dir) / f"{svg_path.name}.png"
        if not produced.exists():
            raise SystemExit(f"QuickLook produced no image for {svg_path}")
        shutil.copyfile(produced, png_path)


def write_imageset(folder: pathlib.Path, name: str, svg_source: str, sizes=(("3x", 1024), ("2x", 683), ("1x", 341))) -> None:
    folder.mkdir(parents=True, exist_ok=True)
    work = REPO / ".occlient" / "artwork-tmp"
    work.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=work) as tmp:
        tmp_path = pathlib.Path(tmp)
        master = tmp_path / f"{name}.svg"
        master.write_text(svg_source)
        images = []
        for scale, px in sizes:
            out = folder / f"{name}@{scale}.png"
            render(master, out, px)
            images.append({"filename": out.name, "idiom": "universal", "scale": scale})
        (folder / "Contents.json").write_text(
            json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n"
        )


def main() -> int:
    MASTERS.mkdir(parents=True, exist_ok=True)
    masters = {
        "icon-back.svg": icon_back(),
        "icon-middle.svg": icon_middle(),
        "icon-front.svg": icon_front(),
        "empty-chat.svg": empty_chat_art(),
        "pairing.svg": pairing_art(),
    }
    for name, content in masters.items():
        (MASTERS / name).write_text(content)

    work = REPO / ".occlient" / "artwork-tmp"
    work.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=work) as tmp:
        tmp_path = pathlib.Path(tmp)

        def render_named(svg_text: str, filename: str, size: int = 1024) -> pathlib.Path:
            master = tmp_path / f"{filename}.svg"
            master.write_text(svg_text)
            out = tmp_path / filename
            render(master, out, size)
            return out

        # flat icon: the same three layers composed into one document
        flat_svg = svg(icon_back_body() + icon_middle_body() + icon_front_body())
        flat = render_named(flat_svg, "AppIcon.png")
        appicon = ASSETS / "AppIcon.appiconset"
        appicon.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(flat, appicon / "AppIcon.png")

        # layered icon
        stack = ASSETS / "AppIcon.solidimagestack"
        for layer, source, filename in (
            ("Back.solidimagestacklayer", icon_back(), "background.png"),
            ("Middle.solidimagestacklayer", icon_middle(), "middle.png"),
            ("Front.solidimagestacklayer", icon_front(), "foreground.png"),
        ):
            imageset = stack / layer / "Content.imageset"
            imageset.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(render_named(source, filename), imageset / filename)

        # in-app illustrations
        write_imageset(ASSETS / "EmptyChatArt.imageset", "EmptyChatArt", empty_chat_art())
        write_imageset(ASSETS / "PairingArt.imageset", "PairingArt", pairing_art())

    print("artwork written to", ASSETS)
    return 0


if __name__ == "__main__":
    sys.exit(main())
