# Birdtown Flow logo

The logo is drawn in code (`Sources/BirdtownFlow/UI/Brand/LogoPainter.swift`) from geometry
and colours measured off the approved concept, a 1254 px raster generated with the Codex CLI.
The same painter renders the `.icns` (`make icon`), the in-app artwork and the spectrum disc,
so they can't drift apart.

## Rules from the creative brief

- Perfect the generated geometry: true circles, a concentric ring centred on the tile,
  symmetrical continuous corners, equal bar widths and spacing, mirrored bar heights.
- Keep the look: the soft rainbow blend, warm-white bars, cool-white ring, navy tile and its
  subtle depth (top-edge highlight, ring shadow).
- Pixel comparison against the concept is a guide, not a target.

## Geometry (fractions of the tile side)

| Element | Full (≥ 96 px) | 64 px | 32 px | 16 px |
|---|---|---|---|---|
| Ring outer / inner radius | 0.3625 / 0.2853 | same | 0.372 / 0.307 | no ring; disc 0.39 |
| Bar width / pitch | 0.0547 / 0.0925 | 0.062 / 0.098 | 0.072 / 0.105 | 0.12 / 0.19 |
| Bar heights | 0.1149, 0.2193, 0.3332, 0.2193, 0.1149 | same | 0.13, 0.24, 0.36, 0.24, 0.13 | 0.24, 0.44, 0.24 |

Tile: Apple's macOS grid (824 px tile on a 1024 px canvas), continuous corners at 22.37 %.

## Colour

- **Tile:** linear light from the top, tilted 0.12 toward the left: `#263B6E` → `#203569`
  (10 %) → `#0E183B` (45 %) → `#091231`, plus a top-edge highlight in `#3A5794`.
- **Ring:** `#F8F9FD` at the top to `#F1F2F7` at the bottom, casting a soft `#000416` shadow
  (55 %, offset 0.008, blur 0.013).
- **Bars:** warm white `#FEFCF8` with a faint two-step navy shadow.
- **Disc:** 36 hue stops every 10° (green at 3 o'clock, yellow, orange at 12, pink, violet at
  9, blue at 6, cyan), blended toward a muted violet-grey `#827596` at the centre:
  `w(r) = 1 − (1 − r / 0.835R)^1.5`. Over the outer 16.5 % the hues deepen to a second set of
  rim stops. The measured fit is within 2–5 / 255 of the concept.

## Where it appears

- **App icon:** `make icon` → `Resources/AppIcon.iconset` → `AppIcon.icns`; CI exports it on
  every push.
- **In-app** (`AppIconArtwork`): picks the size variant from the rendered pixel size; in dark
  appearance it adds a faint light rim so the navy tile doesn't sink into a navy window.
- **Menu bar:** the five bars alone as a template image (`MenuBarGlyph`, `LogoBars`).
- **Dictation pill:** the spectrum disc (`LogoPainter.drawDisc`), turning slowly while you speak.

## Later

macOS 26's layered icon format (Icon Composer) would add Liquid Glass and proper Dark, Clear
and Tinted variants. The layers already exist here: tile, ring, disc, bars.
