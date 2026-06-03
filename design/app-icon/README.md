# App icon design

Source and archive for the Agendum Neo app icon. Nothing in `design/` is
compiled into the app bundle: the Xcode target's sources are `AgendumNeo/`
only and its sole bundled resource is `AgendumNeo/Assets.xcassets`, so this
directory is purely a design/build tool (same as the top-level `Resources/`
README art).

## Shipped icon (v0.5.7)

An eight-row inbox that fades and bleeds off the top and bottom edges. The
bright center pair is **Waiting** (amber `#ffaa00`) and **Changes requested**
(red `#f87171`); higher-chroma colors are placed at the dimmed top/bottom edges
so the fade reads cleanly instead of muddy. Every color is one of the seven
in-app status pill colors (`StatusPalette` in
`AgendumNeo/Views/InboxTable.swift`). The row card, colored left cap, and
grey/colored bar geometry are lifted verbatim from the prior shipping icon;
only the colors, row count, edge fade, and bleed are new.

## Regenerating

```sh
brew install librsvg            # provides rsvg-convert
python3 design/app-icon/generate.py
```

That rewrites `app-icon.svg` (the master), every size under
`AgendumNeo/Assets.xcassets/AppIcon.appiconset/`, and the 1024 README art at
`Resources/AppIcon-1024.png`. `generate.py` is the source of truth for the
parameters (colors, geometry, fade); edit it to change the icon. Re-run, then
`xcodegen generate` is not required (assets are picked up on build).

Note macOS applies its own squircle mask and drop shadow on top of the art at
display time, so the rendered PNGs (with their baked rounded corners) look
slightly boxier than what shows in the Dock.

## Archive — `drafts/`

SVG source for every iteration explored, in rough chronological order. PNGs are
omitted (regenerate any draft with `rsvg-convert -w 1024 -h 1024 drafts/NAME.svg
-o /tmp/NAME.png`).

| Draft | What it explored |
|-------|------------------|
| `A_recolor3` | Original 3-row layout, recolored to the exact palette |
| `B_rows5`, `C_rows7` | More rows |
| `D_fade7`, `E_fade5` | 3 bright rows + extra rows fading out toward the edges |
| `E1`–`E4` | Off-center focus placements (E1 = two rows straddling center) |
| `F1`, `F2` | Line-length / right-margin tuning |
| `G1_origbars` | Original bar geometry on the E1 layout (no row cards yet) |
| `H1_cards` | Row cards added back (6 rows) |
| `I1_8rows` | Eight rows; one extra faded row top & bottom |
| `J1`, `J2` | Square-right colored caps + darken-toward-black fade (rejected) |
| `K1_pad` | Gap between card edge and colored cap |
| `L1`, `L2` | Horizontal lines lengthened |
| `C1`–`C5` | Color arrangements; **`C3_warm-hero` shipped** |

`gallery/` holds a couple of comparison renders for quick visual reference.
