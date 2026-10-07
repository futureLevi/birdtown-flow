# Birdtown Flow, architecture and working agreement

Birdtown Flow is push-to-talk dictation for macOS: hold a key, speak, release, and polished text
lands wherever you were typing. It is a fork of `per-simmons/murmur-youtube`, rebuilt to be
a product that can stand next to Wispr Flow.

## Product surface

| Area | What it does |
|---|---|
| **Dictation** | Hold the push-to-talk key (default **fn**) to record; release to transcribe and insert. Double-tap the key, or press **Space** while holding it, for hands-free; tap again to finish. Settings can make hands-free a tap of **⌃⌥** instead (`HandsFreeShortcut`), for a 🌐 key that macOS also answers. **Esc** cancels. **⌃⌥V** pastes the last dictation again. |
| **Engine** | Parakeet Ultra (FluidAudio, CoreML on the Neural Engine) by default. Parakeet v3/v2 and Apple Speech as alternatives. Dictionary words boost recognition (CTC vocabulary boosting). |
| **Pipeline** | raw text → fillers / stutters / spoken commands → optional AI polish → dictionary corrections → snippets → style rules → insert. |
| **Styles** | Per app category (personal messages, work messages, email, other): formal, casual, very casual, excited. Category comes from the frontmost app (and the window title, for web apps in browsers). |
| **AI polish** | Off, Apple Intelligence (on-device), Claude (Anthropic key) or any OpenAI-compatible endpoint. Hard timeout; any failure falls back to the deterministic text. |
| **Lab** | Admin tool in the main window. Named polish configurations (provider, model, effort, instructions with `{{style}}`, `{{destination}}`, `{{vocabulary}}` placeholders), run side by side on real dictations with timings, the guard's verdict and a word diff. A configuration can take over chosen writing styles; the rest follow Settings, and turning polish off in Settings turns it off for all of them. |
| **History** | Every dictation with its audio. Search, copy, paste again, play, retry transcription, see what the dictionary and polish changed. Failed dictations keep their audio so nothing said is ever lost. |
| **Dictionary** | Vocabulary terms and "hear X → write Y" corrections, also editable as a plain text file. |
| **Snippets** | Say a trigger phrase, get the expansion. |
| **HUD** | A small dark pill at the bottom of the screen: waveform while listening, shimmer while processing, a check when done. Never takes focus. |
| **Onboarding** | Microphone → Accessibility → model download → shortcut → try it. |

## Layers

```
Sources/MurmurDictionary   correction rules. Platform-neutral; shared contract with windows/.
Sources/MurmurKit          pure logic. Foundation only, builds and tests on Linux too.
  Models/                  shared value types (HistoryRecord, AppContext, Snippet, styles…)
  Text/                    TextPipeline, SnippetStore
  History/                 HistoryStore (JSON + recordings/)
  Stats/                   DictationStats
  Polish/                  prompts, PolishGuard, Anthropic + OpenAI-compatible clients,
                           the Lab's configurations (PolishLabStore → lab.json) and WordDiff
Sources/BirdtownFlow             the macOS app
  App/                     @main, AppDelegate, AppModel (composition root)
  Core/                    DictationController, HotkeyMonitor, AudioRecorder, TextInjector…
  Transcription/           TranscriptionEngine, ModelManager, Parakeet + Apple engines
  Polish/                  PolishService (routing, timeout, Lab runs), Apple Intelligence,
                           Keychain, Claude Code (personal builds only: a pre-started
                           `claude -p` session), LabBench (the Lab page's drafts and results)
  Stores/                  DictionaryStore
  Support/                 Settings, AppPaths, Log, Permissions
  UI/DesignSystem          Tokens.swift, the only place literal design values live
  UI/Brand                 the logo drawn in code (LogoPainter), icon export, SpectrumOrb
  UI/Components            shared controls
  UI/HUD                   floating pill
  UI/Main                  main window (Home, History, Dictionary, Snippets, Style, Lab)
  UI/Onboarding, UI/Settings, UI/MenuBar
  UI/Snapshots             `BirdtownFlow --render-snapshots <dir>` renders screens to PNG
```

## Data flow for one dictation

```
key down ─► DictationController.begin
              capture AppContext (frontmost app, window title → category)
              AudioRecorder.start  (16 kHz mono Float32, level meter, WAV on disk)
key up   ─► AudioRecorder.stop → samples
              HistoryStore.add(record: audio saved, outcome pending)
              silence? → outcome .empty, nothing typed
              engine.transcribe(samples, vocabulary)          [Transcription]
              TextPipeline.prepare                            [MurmurKit]
              PolishService.polish (timeout, PolishGuard)     [Polish]
                (Settings' provider, or the Lab configuration the style uses)
              TextPipeline.finalize (dictionary, snippets, style)
              TextInjector.insert                             [Core]
              HistoryStore.update(final text, timings, outcome)
```

## Rules for anyone changing this code

1. **The HUD never takes focus.** It is a non-activating `NSPanel`. If it became key, the
   user's text field would lose focus and there would be nothing to type into.
2. **Audio is saved before transcription.** A crash or engine failure must never lose what
   the user said. Failed records keep their audio and offer Retry.
3. **Polish can only make things better.** Hard timeout, `PolishGuard` rejection, and any
   error all fall back to the deterministic text, silently except for a note in History.
4. **The dictionary runs last** (after polish), so its guarantees hold whatever a model wrote.
5. **No literal design values in views.** Colours, type, spacing, radii, motion: `Tokens.swift`.
6. **Every animation honours Reduce Motion** through `Motion.resolve`.
7. **Swift 6 strict concurrency.** Never `MainActor.assumeIsolated` outside code that is
   provably on the main thread (event-tap callbacks on the main run loop, AppKit delegate
   callbacks). Prefer `await MainActor.run`.
8. **Settings live in `Settings`.** Don't read `UserDefaults` anywhere else.
9. **Platform-neutral logic goes in MurmurKit**, with tests. `swift test` runs on Linux.

## Building

```bash
make install        # build, bundle, sign, copy to /Applications, launch
make test           # unit tests (also: `swift test` on Linux for the logic layers)
make snapshots      # render every screen to ./snapshots
```

CI (`.github/workflows/macos.yml`) builds and tests every push on a macOS 26 runner, renders
snapshots, and pushes logs and images to the `snapshots/<branch>` branch. On `main` it also
publishes a zipped, ad-hoc signed `Birdtown Flow.app` as the `nightly` release.
