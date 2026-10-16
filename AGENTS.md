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
- The runner has Reduce Motion on, so moving things render at rest unless a shot pins a
  phase (`MainPreview.fieldPhase`, `orbPhase`). Not a bug in the app.
- The main window's sidebar is laid out by hand (`MainSidebar`), not a `NavigationSplitView`:
  macOS 26 would float it as a glass panel, and the design's sidebar is flat and flush. That
  also means View › Toggle Sidebar is ours (`AppModel.sidebarHidden`, ⌃⌘S). The 66 pt toolbar
  (`MainToolbar`) floats over the detail column: pages are inset below it, except Home, which
  starts at the top and insets its own content.

## Rules

- **The HUD never takes focus.** It's a non-activating panel; if it became key, the user's
  text field would lose focus and there'd be nothing to type into.
- **Audio is written and a History row exists before transcription starts.** Live windows
  decode during recording; the WAV append and placeholder row come first (see ARCHITECTURE).
- **Polish can only make things better.** Time limit, `PolishGuard`, and any error all fall
  back to the deterministic text.
- **The dictionary runs last**, after polish. `Tests/MurmurDictionaryTests/dictionary-test-vectors.json`
  is the spec for correction behaviour: change the vectors first, then the code.
- **No literal design values in views.** Everything comes from `UI/DesignSystem/Tokens.swift`.
  The spectrum (`SpectrumOrb`, `Spectrum`) means live and nothing else; primary actions are
  navy capsules; Signal blue is for selection, focus and links; violet and teal are small
  accents (tuning, vocabulary). Type is big: 19 pt for dictated words, 16-17 for the
  interface, nothing under 15. Onboarding and the menu bar use `Typography.Compact`. See
  `docs/brand.md`.
- **Every animation goes through `Motion`** so Reduce Motion is honoured.
- **Settings live in `Support/Settings.swift`.** Our `Settings` class shadows SwiftUI's
  scene of the same name. The app doesn't use that scene: the Settings screen is a modal in
  the main window, opened with `AppModel.showSettings(_:)`, so never `openSettings` or
  `SettingsLink`.

## macOS traps

- **`MainActor.assumeIsolated` asserts, it doesn't check.** Only use it where the code
  provably runs on the main thread (event-tap callbacks on the main run loop, timers on
  `RunLoop.main`). Otherwise `await MainActor.run`.
- **TCC keys Accessibility to the code signature.** Ad-hoc signatures change every build, so
  the grant silently stops working while the toggle still shows on. `make` signs with a
  Developer ID when one exists; CI signs the nightly with the self-signed identity in the
  `MACOS_SIGNING_P12` secret (`scripts/make-signing-identity.sh`), and falls back to ad-hoc
  without it. Replacing that certificate costs every user one re-grant. To reset one app only:
  `tccutil reset Accessibility com.birdtownlabs.flow` (never omit the bundle ID), then
  quit System Settings before reopening it.
- **Keep the checkout out of iCloud-synced folders**, or build with `make`, which puts build
  products in `~/Library/Caches/BirdtownFlowBuild`. Sync engines modify files mid-compile.
- **Secure Event Input** (password fields) hides key events from the tap. `HotkeyMonitor`
  polls the modifier state while it's on, so a hidden key-up can't leave the mic open.
- **Never free an `AVAudioEngine` straight after a hardware change.** AVFAudio may still have
  a property-listener block queued for its input unit, and the app crashes in Apple's code
  when it runs. `AudioRecorder.discardEngine()` retires engines instead; they're released
  once they've gone quiet (`QuietRelease`). Don't add a path that sets an engine to `nil`.
- **Selecting an input device leaves the input bus in the old device's format.**
  `kAudioOutputUnitProperty_CurrentDevice` changes the hardware under an input node that
  already exists, and the engine won't start while the bus's rate disagrees with it.
  `AudioRecorder.installTap` taps in the hardware's format when they differ; keep tapping
  through it. A chosen mic that still won't start falls back to the system default.
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
- **Decide the `polishWhileSpeaking` default for Anthropic/OpenAI-compatible:** text
  reaches the provider before key-up and Esc can't recall it.
- **Decide where customers' feedback goes.** The feedback shortcut files GitHub issues with
  a token the person pastes in, which suits the developer, not customers. Customers' notes
  need an endpoint of ours (and their consent to attach recent dictations), or the shortcut
  hidden.
- **Decide what the Lab is for customers.** It's an admin tool for tuning prompts. Either
  hide it behind an advanced setting or keep it to internal builds, and drop Claude Code
  from its provider list along with the provider itself.

## Not built yet

- **Command Mode**: select text, hold a key, say "make this more formal".
- **Auto-learning the dictionary** from edits you make after a dictation.
- **Notarization**, so downloads open without the Privacy & Security step.
