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
- **Live states:** the spectrum disc on its own is `SpectrumOrb`. It means "your voice is live"
  and nothing else: the pill's record light, the sidebar and menu bar status while
  recording, onboarding's try-it moment. While listening it turns slowly (one turn per 9 s)
  and swells a little with your voice; while transcribing or polishing it hollows into a ring
  that spins with a comet tail. It is painted once by `LogoPainter.drawDisc` and then only
  turned, so it is the logo's disc, not an imitation of it.

## The app around it ("navy and spectrum")

`Sources/BirdtownFlow/UI/DesignSystem/Tokens.swift` holds the rules; in short:

- Navy ink (`#0E183C`) on porcelain (`#F6F7FB`); in dark mode, porcelain ink on midnight navy
  (`#0B1026`).
- Primary actions are navy pills (porcelain in dark mode), like the tile and ring.
- One solid accent, Signal blue (`#4256F0`, `#8291FF` in dark), for selection, focus, links
  and toggles.
- The spectrum only for live states: the orb, the thinking ring, model download progress.
  Never for static chrome, text or backgrounds. The one exception is Home's hero (below).
- SF Pro throughout: bold and semibold for titles and big numbers, regular for reading. (SF
  Pro Expanded, New York and SF Pro Rounded were tried for the large text; SF Pro won.)

## Home hero: Voiceprint

The top of Home is a navy band (the icon's tile ground, 150 pt tall, 18 pt corners) with the
greeting on its left and the **Voiceprint** on its right: a mirrored voice waveform of fine
tapered lines in the orb's colours, shaped by the pill's 18-bar rhythm. It rises out of the
navy in violet under the end of the greeting, burns cyan at its loudest and trails off in warm
gold. No birds, no pill, orb, microphone or meter: it is artwork, not a control.

- **Source:** `tools/voiceprint/gen.py` is the generator the design was made with;
  `tools/voiceprint/export_swift.py` turns it into `UI/Brand/VoiceprintData.swift`, which
  `VoiceprintArt` draws. Change the design there and re-export; never edit the data by hand.
- **Motion, "Shimmer":** the lines hold still while a soft band of light (a gaussian, sigma
  26 pt) glides left to right in 2.8 s, once every 7.5 s, lifting the lines it passes by 4.5 %.
  As Home appears the voice rises once from left to right (1.4 s). The numbers live in
  `MurmurKit/Brand/VoiceprintMotion.swift`.
- **Polite:** still with Reduce Motion, paused while the window is in the background or the
  hero is scrolled away, and nothing redraws between sweeps.
- **Width:** the art is designed at 660 pt and anchored right. A wider hero gives the words
  more calm room; a narrower one squeezes the art horizontally.

## Later

macOS 26's layered icon format (Icon Composer) would add Liquid Glass and proper Dark, Clear
and Tinted variants. The layers already exist here: tile, ring, disc, bars.
