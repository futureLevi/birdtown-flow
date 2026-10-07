# Working on Birdtown Flow

Read `docs/ARCHITECTURE.md` first: layers, data flow, and the rules the code keeps. This
file is the list of things that look wrong but aren't, and things that look fine and bite.

## Build and verify

```bash
make install        # build, bundle, sign, copy to /Applications, launch
make test           # unit tests
make snapshots      # every screen to ./snapshots, light and dark
.build/debug/BirdtownFlow --transcribe file.wav [parakeetUltra|parakeetV3|parakeetV2|apple]
```

- `swift test` also runs on Linux: the manifest drops the app target there, and MurmurKit
  plus MurmurDictionary are Foundation-only. Put new pure logic in MurmurKit, with tests.
- CI (`.github/workflows/macos.yml`) builds every branch on macOS 26, renders snapshots, runs
  the speech smoke test, and force-pushes logs and PNGs to `snapshots/<branch>`. Review UI
  changes there; the renderer is `UI/Snapshots/SnapshotRenderer.swift` and each area
  registers screens in its own `SnapshotCatalog+*.swift`.
- Offscreen snapshots can't capture the macOS 26 glass sidebar (it renders as a white
  panel) and the runner has Reduce Motion on. Neither is a bug in the app.

## Rules

- **The HUD never takes focus.** It's a non-activating panel; if it became key, the user's
  text field would lose focus and there'd be nothing to type into.
- **Audio is written and a History row exists before transcription starts.**
- **Polish can only make things better.** Time limit, `PolishGuard`, and any error all fall
  back to the deterministic text.
- **The dictionary runs last**, after polish. `shared/dictionary-test-vectors.json` is the
  spec for correction behaviour (the upstream Windows app runs the same vectors); change the
  vectors first, then `cp shared/dictionary-test-vectors.json Tests/MurmurDictionaryTests/`.
- **No literal design values in views.** Everything comes from `UI/DesignSystem/Tokens.swift`.
  The spectrum (`SpectrumOrb`, `Spectrum`) means live and nothing else; primary actions are
  navy pills; Signal blue is for selection, focus and links. See `docs/brand.md`.
- **Every animation goes through `Motion`** so Reduce Motion is honoured.
- **Settings live in `Support/Settings.swift`.** Our `Settings` class shadows SwiftUI's
  scene of the same name; write `SwiftUI.Settings` for the scene.

## macOS traps

- **`MainActor.assumeIsolated` asserts, it doesn't check.** Only use it where the code
  provably runs on the main thread (event-tap callbacks on the main run loop, timers on
  `RunLoop.main`). Otherwise `await MainActor.run`.
- **TCC keys Accessibility to the code signature.** Ad-hoc signatures change every build, so
  the grant silently stops working while the toggle still shows on. `make` signs with a
  Developer ID when one exists. To reset one app only:
  `tccutil reset Accessibility com.birdtownlabs.flow` (never omit the bundle ID), then
  quit System Settings before reopening it.
- **Keep the checkout out of iCloud-synced folders**, or build with `make`, which puts build
  products in `~/Library/Caches/BirdtownFlowBuild`. Sync engines modify files mid-compile.
- **Secure Event Input** (password fields) hides key events from the tap. `HotkeyMonitor`
  polls the modifier state while it's on, so a hidden key-up can't leave the mic open.
- **AX calls into other apps need short timeouts**; an unresponsive app must never hang
  Birdtown Flow's main thread.
- **`log` may be shadowed in your shell.** Use `/usr/bin/log show --predicate
  'subsystem == "com.birdtownlabs.flow"'`.

## Before Birdtown Flow is sold

- **Remove the Claude Code polish provider** (`PolishProvider.claudeCode`,
  `Polish/ClaudeCodePolisher.swift`). It runs polish on the user's own Claude Pro or Max
  login through Claude Code, which is fine for the developer's personal builds and not
  allowed in an app others use: Anthropic's terms don't let third-party apps route
  requests through Free, Pro or Max credentials. Customers use the Anthropic option with
  their own API key.
- **Decide what the Lab is for customers.** It's an admin tool for tuning prompts. Either
  hide it behind an advanced setting or keep it to internal builds, and drop Claude Code
  from its provider list along with the provider itself.

## Not built yet

- **Command Mode**: select text, hold a key, say "make this more formal".
- **Auto-learning the dictionary** from edits you make after a dictation.
- **Notarization**, so downloads open without the Privacy & Security step.
