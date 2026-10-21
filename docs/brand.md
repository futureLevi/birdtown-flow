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
  and nothing else: the pill's record light, the menu bar status while recording,
  onboarding's try-it moment. While listening it turns slowly (one turn per 9 s)
  and swells a little with your voice; while transcribing or polishing it hollows into a ring
  that spins with a comet tail. It is painted once by `LogoPainter.drawDisc` and then only
  turned, so it is the logo's disc, not an imitation of it.

## The app around it ("Handoff")

The window follows Levi's design handoff (a single-file HTML prototype plus screenshots).
`Sources/BirdtownFlow/UI/DesignSystem/Tokens.swift` holds the rules; in short:

- **Light first, paired dark.** Canvas `#F6F7FB`, white surfaces, a cool `#EDF1F8` rail
  (a faint diagonal wash), hairlines `#DCE2EF`, control outlines `#838CA5`. Dark mode is a
  paired set, not an inversion: canvas `#0B1026`, surface `#141A33`, rail `#10182F`, lines
  `#303B5B`. Text is navy `#0E183C` (`#EEF1FA` in dark); secondary `#4A5478`, tertiary
  `#626C89`, all at 4.5:1 or better.
- **Navy anchors, Signal blue marks.** Primary actions are navy capsules (porcelain in dark
  mode), at most one per view. Signal blue (`#4256F0`, `#93A0FF` in dark) is for interaction
  and selection: links, switches, the chosen nav row, the focus ring. Selection never relies on
  hue alone: a marker bar and heavier weight on nav, a check on chips, a radio mark on choices.
- **Two small accents with a job.** Violet (`#6945B5`) is tuning: the Lab, "Polished"
  badges, prompt variables. Teal (`#176B70`) is vocabulary: the Dictionary and what it
  knows. Both come with a soft wash for tiles. No full-spectrum decoration in the window: the
  colour-wheel sidebar icons and gradient stat badges are gone.
- **Big, legible type.** SF Pro. Page titles 34 pt, section titles 21-23, words you read
  (dictation, transcripts) 19 pt on a 1.6 line height, interface text 16-17, metadata never
  below 15. Home's Recent dictation card is a step smaller (17 / 15 / 14), a glance rather
  than the History page. Titles semibold with tight tracking.
- **Shape.** Rail 234 pt, toolbar 66 pt, content inset 40 pt. Controls have 8-9 pt corners,
  panels 14 pt, dialogs and the window 18-20 pt. Surfaces are a hairline and the faintest
  panel shadow.
- **Focus.** Keyboard focus is a 3 pt outline 4 pt outside the control (`Layout.Focus`,
  `flowFocusRing`). Dialogs trap focus and close on Esc.
- **Shell.** The sidebar carries the real app icon and wordmark, Home / History / Dictionary /
  Snippets / Style, a divider, "Workspace" (Lab), then Settings and a "fn  Hold to dictate"
  hint that shows the user's own shortcut. The toolbar shows the page title, **Search
  history** (opens History with its field focused) and the live status ("Ready to dictate",
  or what is missing).
- **The recording pill is not part of the redesign.** It keeps the icon's navy, the spectrum
  orb and its motion; the colour wheel stays there. The spectrum means "your voice is live"
  and appears nowhere else but the Home hero artwork.
- Onboarding and the menu bar window keep the old compact type (`Typography.Compact`); they
  take the new colours only.

## Home hero: open canvas

Home has no hero card. Its art sits on the canvas behind the toolbar and the content: a
cropped violet-blue-teal field with five white capsule bars, short, tall, tallest, tall,
short (the logo's bars). "Recent dictation" owns the main column; "Your setup" links and a
quiet "This week" summary sit in a right column. The art is `VoiceField`, drawn natively
from the handoff's voice field: flat (no depth shading), with the surface and its two pigments
drifting slowly (a 20 s cycle) around a fixed centre while the bars and halo stay still. It
rests under Reduce Motion, and its colours are `Palette.Field`. In a narrow window it gives up
its bars and fades.

## Later

macOS 26's layered icon format (Icon Composer) would add Liquid Glass and proper Dark, Clear
and Tinted variants. The layers already exist here: tile, ring, disc, bars.
