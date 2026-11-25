"""Generate the Perroquet app icon as an Icon Composer bundle (.icon), like Tomate's.

Each part of the parrot is one layer PNG (1024x1024, the canvas is the whole
rounded square); icon.json carries the background, gradients, glass and shadow,
with the same settings as Tomate.icon so the apps share one look.

Writes Perroquet/Perroquet.icon (the app icon), the one-colour menu bar template
(Perroquet/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon.svg: head, beaks and
crest merged, the eye punched out) and Liquid Glass previews in
design/logo/preview/.

Usage: python3 -I design/logo/perroquet.py
Needs resvg, and Xcode's ictool for the previews (run outside the sandbox:
ictool needs the GPU).
"""

from __future__ import annotations

import json
import math
import re
import shutil
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path

HERE = Path(__file__).resolve().parent
ICON = HERE.parent.parent / "Perroquet" / "Perroquet.icon"
MENU_BAR_ICON = (
    HERE.parent.parent
    / "Perroquet"
    / "Assets.xcassets"
    / "MenuBarIcon.imageset"
    / "MenuBarIcon.svg"
)
PREVIEWS = HERE / "preview"
ICTOOL = "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"

BLUE, GREEN, YELLOW, WHITE = "#2F80ED", "#3DD17A", "#FFC83D", "#FFFFFF"

# The parrot is drawn in its own coordinates, then scaled and centred on the 1024 canvas.
# MOTIF_CENTRE is the centre of the bounding box of every layer (crest, head, beaks).
MOTIF_CENTRE = (419, 432)
MOTIF_SCALE = 1.4
EYE_CENTRE = (465, 448)

# Crest: one feather repeated three times. The tips sit on one arc (centred on
# CREST_PIVOT, through the yellow tip), CREST_STEP degrees apart; each feather leans back
# by CREST_LEAN of that angle, so the visible overlaps are about equal (132 vs 165 px).
FEATHER = "M320 355 C305 250, 365 150, 450 155 C410 222.5, 400 300, 415 350 Z"
FEATHER_TIP = (450, 155)
CREST_PIVOT = (401, 399)
CREST_STEP = -27  # degrees along the arc between two tips
CREST_LEAN = 0.55


def crest() -> str:
    """Return the three overlapping crest feathers, back to front."""
    px, py = CREST_PIVOT
    tx, ty = FEATHER_TIP
    radius = math.dist(CREST_PIVOT, FEATHER_TIP)
    start = math.degrees(math.atan2(ty - py, tx - px))
    paths = []
    for i, colour in enumerate((YELLOW, GREEN, BLUE)):  # back to front
        angle = start + i * CREST_STEP
        x = px + radius * math.cos(math.radians(angle))
        y = py + radius * math.sin(math.radians(angle))
        transform = f"translate({x:.2f} {y:.2f}) rotate({CREST_LEAN * i * CREST_STEP:.2f}) translate({-tx} {-ty})"
        paths.append(f'<path d="{FEATHER}" fill="{colour}" transform="{transform}"/>')
    return "".join(paths)


def eye() -> str:
    """Return the eye: white, yellow iris and an off-centre pupil."""
    cx, cy = EYE_CENTRE
    white, pupil = 64, 27
    iris = (white + pupil) / 2 + 3
    return (
        f'<circle cx="{cx}" cy="{cy}" r="{white}" fill="{WHITE}"/>'
        f'<circle cx="{cx}" cy="{cy}" r="{iris}" fill="{YELLOW}"/>'
        f'<circle cx="{cx + iris - pupil - 6}" cy="{cy}" r="{pupil}" fill="#0d1218"/>'
    )


# Layer name -> SVG fragment in motif coordinates.
LAYERS = {
    "eye": eye(),
    "head": '<circle cx="360" cy="500" r="210" fill="#E83A45"/>',
    "upper-beak": (
        '<path d="M465 375 C630 335, 730 420, 720 545 C716 590, 684 600, 676 565 '
        'C664 515, 630 495, 480 500 Z" fill="#FBC24A"/>'
    ),
    "lower-beak": '<path d="M480 560 C610 560, 660 590, 660 640 C620 672, 560 668, 480 645 Z" fill="#E08A12"/>',
    "crest": crest(),
}


def gradient(top: str, bottom: str) -> dict[str, object]:
    """Return a top-to-bottom linear gradient fill for icon.json."""
    return {
        "linear-gradient": [top, bottom],
        "orientation": {"start": {"x": 0.5, "y": 0}, "stop": {"x": 0.5, "y": 1}},
    }


@dataclass(frozen=True)
class LayerSpec:
    """One layer of the icon: its id, display name and optional gradient fill."""

    id: str
    name: str
    fill: dict[str, object] | None = None


# Front to back, as in Tomate.icon. Layers without a fill keep their PNG colours.
LAYER_SPECS = [
    LayerSpec("eye", "Eye"),
    LayerSpec(
        "head",
        "Head",
        gradient(
            "srgb:1.00000,0.26000,0.24000,1.00000",
            "srgb:0.88000,0.04000,0.16000,1.00000",
        ),
    ),
    LayerSpec(
        "upper-beak",
        "Upper beak",
        gradient(
            "srgb:1.00000,0.87843,0.47843,1.00000",
            "srgb:0.96078,0.65098,0.13725,1.00000",
        ),
    ),
    LayerSpec("lower-beak", "Lower beak"),
    LayerSpec("crest", "Crest"),
]


def build_icon() -> None:
    """Write the layer PNGs and icon.json of the .icon bundle."""
    shutil.rmtree(ICON, ignore_errors=True)
    (ICON / "Assets").mkdir(parents=True)
    cx, cy = MOTIF_CENTRE
    transform = f"translate(512 512) scale({MOTIF_SCALE}) translate({-cx} {-cy})"
    entries = []
    with tempfile.TemporaryDirectory() as tmp:
        for spec in LAYER_SPECS:
            src = Path(tmp) / f"{spec.id}.svg"
            src.write_text(
                f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">'
                f'<g transform="{transform}">{LAYERS[spec.id]}</g></svg>'
            )
            png = f"{spec.id}.png"
            subprocess.run(
                ["resvg", "-w", "1024", str(src), str(ICON / "Assets" / png)],
                check=True,
            )
            entry: dict[str, object] = {"image-name": png, "name": spec.name}
            if spec.fill is not None:
                entry["fill"] = spec.fill
            entries.append(entry)
    document = {
        "fill": "system-dark",
        "groups": [
            {
                "layers": entries,
                "shadow": {"kind": "neutral", "opacity": 0.5},
                "translucency": {"enabled": True, "value": 0.42},
            }
        ],
        "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
    }
    (ICON / "icon.json").write_text(json.dumps(document, indent=2) + "\n")


# Eye hole of the menu bar glyph, smaller than the app icon's eye so it stays light at 17pt.
MENU_BAR_EYE_RADIUS = 46
# Bounding box of the head, beaks and crest in motif coordinates: x, y, width, height.
MENU_BAR_BOX = (117, 150, 604, 560)
MENU_BAR_HEIGHT_PT = 17


def black(fragment: str) -> str:
    """Return `fragment` with every fill forced to black, for a template image."""
    return re.sub(r'fill="#[0-9A-Fa-f]{6}"', 'fill="#000"', fragment)


def build_menu_bar_icon() -> None:
    """Write the menu bar template: one black silhouette with the eye as a hole, cropped to the motif."""
    x, y, w, h = MENU_BAR_BOX
    eye_x, eye_y = EYE_CENTRE
    eye_hole = (
        f'<circle cx="{eye_x}" cy="{eye_y}" r="{MENU_BAR_EYE_RADIUS}" fill="#000"/>'
    )
    shapes = "".join(
        black(LAYERS[name]) for name in ("head", "upper-beak", "lower-beak", "crest")
    )
    width = round(MENU_BAR_HEIGHT_PT * w / h, 2)
    MENU_BAR_ICON.parent.mkdir(parents=True, exist_ok=True)
    MENU_BAR_ICON.write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}pt" height="{MENU_BAR_HEIGHT_PT}pt" '
        f'viewBox="{x} {y} {w} {h}">'
        f'<defs><mask id="eye" maskUnits="userSpaceOnUse" x="{x}" y="{y}" width="{w}" height="{h}">'
        f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="#fff"/>{eye_hole}</mask></defs>'
        f'<g mask="url(#eye)">{shapes}</g></svg>\n'
    )


def build_previews() -> None:
    """Render Liquid Glass previews of the icon with ictool."""
    PREVIEWS.mkdir(exist_ok=True)
    for size in (512, 128, 64, 32):
        subprocess.run(
            [
                ICTOOL,
                str(ICON),
                "--export-image",
                "--output-file",
                str(PREVIEWS / f"perroquet-{size}.png"),
                "--platform",
                "macOS",
                "--rendition",
                "Default",
                "--width",
                str(size),
                "--height",
                str(size),
                "--scale",
                "1",
            ],
            check=True,
            capture_output=True,
        )


if __name__ == "__main__":
    build_icon()
    build_menu_bar_icon()
    build_previews()
    print(f"built {ICON}")
