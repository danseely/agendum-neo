#!/usr/bin/env python3
"""Reproduce the shipped Agendum Neo app icon.

This is the source of truth for the icon. It builds the master SVG and
rasterizes it to every `AppIcon.appiconset` size plus the 1024 README art.
Nothing here is compiled into the app bundle — `design/` lives outside the
Xcode target (target sources are `AgendumNeo/` only), so this is purely a
design/build tool.

The shipped design (v0.5.7, the "C3 / warm-hero" arrangement) is an eight-row
inbox that fades and bleeds off the top and bottom edges. The bright center
pair is Waiting (amber) and Changes requested (red); higher-chroma colors sit
at the dimmed edges so the fade reads cleanly. Every color comes from the app's
`StatusPalette` (AgendumNeo/Views/InboxTable.swift). Row card / left cap /
grey+colored bar geometry is lifted from the prior shipping icon; only the
colors, row count, edge fade, and bleed are new.

Usage (from anywhere):
    python3 design/app-icon/generate.py          # write icon assets into the repo
    python3 design/app-icon/generate.py --svg-only   # just emit app-icon.svg

Requires `rsvg-convert` (brew install librsvg). See README.md. Earlier drafts
are archived as SVGs in ./drafts/.
"""
import subprocess, sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
APPICONSET = os.path.join(REPO, "AgendumNeo/Assets.xcassets/AppIcon.appiconset")
README_ART = os.path.join(REPO, "Resources/AppIcon-1024.png")
MASTER_SVG = os.path.join(HERE, "app-icon.svg")

SIZE = 1024
# StatusPalette (kept in sync with AgendumNeo/Views/InboxTable.swift)
PAL = {"open": "#60a5fa", "approved": "#4ade80", "waiting": "#ffaa00",
       "changes": "#f87171", "commented": "#94a3b8", "review": "#a78bfa",
       "assigned": "#2dd4bf"}
# background squircle
MARGIN, R = 48, 205
BG, CARD, GREY = "#161b22", "#21262d", "#30363d"
# row bar geometry (lifted verbatim from the prior shipping icon)
BAR_X0, GREY_H, PILL_H, GREY_DY, PILL_DY = 172, 39, 31, -27, 27
TICK_X, TICK_W = 96, 33                      # colored left cap (gap before card)
LENS = [(421, 281), (511, 341), (365, 239)]  # (grey_len, pill_len) per row, cycled
LEN_SCALE = 1.276
CARD_X0, CARD_X1, CARD_RX = 140, 900, 36
# layout
CARD_H, PITCH = 120, 142
TICK_H = int(CARD_H * 0.94)
CENTERS = [15, 157, 299, 441, 583, 725, 867, 1009]   # rows 441 & 583 straddle center
FOCUS, PLATEAU, FALLOFF, MINA = 3.5, 0.5, 0.42, 0.08
# shipped color order, top -> bottom (i0/i7 most dimmed, i3/i4 full bright)
SEQ = ["assigned", "open", "review", "waiting", "changes", "approved", "open", "assigned"]

# appiconset filename -> pixel size
TARGETS = {
    "icon_16x16@1x.png": 16, "icon_16x16@2x.png": 32,
    "icon_32x32@1x.png": 32, "icon_32x32@2x.png": 64,
    "icon_128x128@1x.png": 128, "icon_128x128@2x.png": 256,
    "icon_256x256@1x.png": 256, "icon_256x256@2x.png": 512,
    "icon_512x512@1x.png": 512, "icon_512x512@2x.png": 1024,
}


def alpha_for(i):
    return max(MINA, 1.0 - FALLOFF * max(0.0, abs(i - FOCUS) - PLATEAU))


def row_svg(yc, color, a, glen, plen):
    return "\n  ".join([
        f'<rect x="{CARD_X0}" y="{yc-CARD_H/2:.1f}" width="{CARD_X1-CARD_X0}" height="{CARD_H}" rx="{CARD_RX}" fill="{CARD}" opacity="{a:.3f}"/>',
        f'<rect x="{TICK_X}" y="{yc-TICK_H/2:.1f}" width="{TICK_W}" height="{TICK_H}" rx="{TICK_W/2}" fill="{color}" opacity="{a:.3f}"/>',
        f'<rect x="{BAR_X0}" y="{yc+GREY_DY-GREY_H/2:.1f}" width="{round(glen*LEN_SCALE)}" height="{GREY_H}" rx="{GREY_H/2}" fill="{GREY}" opacity="{a:.3f}"/>',
        f'<rect x="{BAR_X0}" y="{yc+PILL_DY-PILL_H/2:.1f}" width="{round(plen*LEN_SCALE)}" height="{PILL_H}" rx="{PILL_H/2}" fill="{color}" opacity="{a:.3f}"/>'])


def build_svg():
    body = []
    for i, yc in enumerate(CENTERS):
        glen, plen = LENS[i % len(LENS)]
        body.append(row_svg(yc, PAL[SEQ[i]], alpha_for(i), glen, plen))
    rows = "".join(b + "\n  " for b in body)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" viewBox="0 0 {SIZE} {SIZE}">
  <defs><clipPath id="sq"><rect x="{MARGIN}" y="{MARGIN}" width="{SIZE-2*MARGIN}" height="{SIZE-2*MARGIN}" rx="{R}" ry="{R}"/></clipPath></defs>
  <rect x="{MARGIN}" y="{MARGIN}" width="{SIZE-2*MARGIN}" height="{SIZE-2*MARGIN}" rx="{R}" ry="{R}" fill="{BG}"/>
  <g clip-path="url(#sq)">
  {rows}</g>
</svg>'''


def main():
    svg = build_svg()
    with open(MASTER_SVG, "w") as f:
        f.write(svg)
    print(f"wrote {os.path.relpath(MASTER_SVG, REPO)}")
    if "--svg-only" in sys.argv:
        return
    if not subprocess.run(["which", "rsvg-convert"], capture_output=True).returncode == 0:
        sys.exit("rsvg-convert not found — `brew install librsvg`")
    for fn, px in TARGETS.items():
        out = os.path.join(APPICONSET, fn)
        subprocess.run(["rsvg-convert", "-w", str(px), "-h", str(px), MASTER_SVG, "-o", out], check=True)
        print(f"  {fn} ({px}px)")
    subprocess.run(["rsvg-convert", "-w", "1024", "-h", "1024", MASTER_SVG, "-o", README_ART], check=True)
    print(f"wrote {os.path.relpath(README_ART, REPO)}")


if __name__ == "__main__":
    main()
