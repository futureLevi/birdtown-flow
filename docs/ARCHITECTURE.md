# Birdtown Flow, architecture and working agreement

Birdtown Flow is push-to-talk dictation for macOS: hold a key, speak, release, and polished text
lands wherever you were typing. It is a fork of `per-simmons/murmur-youtube`, rebuilt to be
a product that can stand next to Wispr Flow.

## Product surface

| Area | What it does |
|---|---|
| **Dictation** | Hold the push-to-talk key (default **fn**) to record; release to transcribe and insert. Double-tap the key, or press **Space** while holding it, for hands-free; tap again to finish. Settings can make hands-free a tap of **⌃⌥** or a recorded chord instead (`HandsFreeShortcut`), for a 🌐 key that macOS also answers. Push-to-talk can be any single modifier key (either side) or a recorded chord; hands-free and paste-last chords can be recorded too (`MurmurKit/Input`: `KeyShortcut`, `ShortcutRules`, `ShortcutCapture`). **Esc** cancels. **⌃⌥V** (by default) pastes the last dictation again. |
| **Engine** | Parakeet Ultra (FluidAudio, CoreML on the Neural Engine) by default. Parakeet v3/v2 and Apple Speech as alternatives. Dictionary words boost recognition (CTC vocabulary boosting), tuned for precision: a word is only rewritten to a dictionary term when it sounds like it, and every rewrite is listed under Replacements in History. While the selected Parakeet model downloads or loads, Apple Speech (or the previously loaded model) stands in and History names it (`ModelManager.standInName`, `MurmurKit.EngineFallback`); it switches over automatically. |
| **Pipeline** | raw text → fillers / stutters / spoken commands → optional AI polish → dictionary corrections → snippets → style rules → insert. |
| **Styles** | Per app category (personal messages, work messages, email, other): formal, casual, very casual, excited. Category comes from the frontmost app (and the window title, for web apps in browsers). |
| **AI polish** | Off, Apple Intelligence (on-device), Claude (Anthropic key) or any OpenAI-compatible endpoint. Hard timeout; any failure falls back to the deterministic text. |
| **Lab** | Admin tool in the main window. Named polish configurations (provider, model, effort, instructions with `{{style}}`, `{{destination}}`, `{{vocabulary}}` placeholders), run side by side on real dictations with timings, the guard's verdict and a word diff. A configuration can take over chosen writing styles; the rest follow Settings, and turning polish off in Settings turns it off for all of them. |
| **History** | Every dictation with its audio. Search, copy, paste again, play, retry transcription, see what the dictionary and polish changed. Failed dictations keep their audio so nothing said is ever lost. Deletes can be undone for 5 s (`HistoryDeletion`). Retention runs at launch, hourly, on wake and when either setting changes (`AppModel.keepApplyingRetention`). |
| **Dictionary** | Vocabulary terms and "hear X → write Y" corrections, also editable as a plain text file. |
| **Snippets** | Say a trigger phrase, get the expansion. |
| **HUD** | A small dark pill at the bottom of the screen: waveform while listening, shimmer while processing, a check when done, a distinct shape while polishing. Failures and notices (no speech heard, no words, copied instead of typed, polish skipped) appear as a message pill that can be clicked once the pointer moves to it: it opens the History row, the microphone picker or System Settings (`DictationFeedback`, `DictationController.FollowUp`). Never takes focus. |
| **Onboarding** | Microphone → Accessibility → model download → shortcut → try it. |

## Layers

```
Sources/MurmurDictionary   correction rules. Platform-neutral; shared contract with windows/.
Sources/MurmurKit          pure logic. Foundation only, builds and tests on Linux too.
  Models/                  shared value types (HistoryRecord, AppContext, Snippet, styles…)
  Text/                    TextPipeline, SnippetStore
  History/                 HistoryStore (JSON + recordings/)
  Stats/                   DictationStats, TimingLine (the per-dictation timing summary),
                           TimingRollup (the p50/p90 line atop History's Timings view)
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
  UI/Onboarding, UI/MenuBar
  UI/Settings              Settings, a modal over the main window (⌘, or the sidebar)
  UI/Snapshots             `BirdtownFlow --render-snapshots <dir>` renders screens to PNG
```

## Data flow for one dictation

```
key down ─► DictationController.begin
              capture AppContext (frontmost app, window title → category)
              AudioRecorder.start  (16 kHz mono Float32, level meter, WAV on disk)
key up   ─► AudioRecorder.stop → samples
              HistoryStore.add(record: audio saved, outcome pending)
              too short or silent under 1 s? → dropped; silent ≥ 1 s → "no speech" pill
              engine.transcribe(samples, vocabulary)          [Transcription]
              TextPipeline.prepare                            [MurmurKit]
              PolishService.polish (timeout, PolishGuard)     [Polish]
                (Settings' provider, or the Lab configuration the style uses)
              TextPipeline.finalize (dictionary, snippets, style)
              TextInjector.insert                             [Core]
              HistoryStore.update(final text, timings, outcome)
```

## Long dictations

Short recordings take the path above unchanged. A long one does most of its work before
the key comes up, so key-up only waits for the last few seconds of speech and the last part
of the text. Three settings switch each piece off (`liveTranscription`, `polishInParts`,
`polishWhileSpeaking`); off, a dictation behaves as above.

```
key down ─► Session.id is the record id from now on; LiveDictation starts (Parakeet only)
recording, every second, once 20 s of audio exist:
              SegmentPlanner cuts at a pause: ≤ 12 s kept, + 2 s before and 0.96 s after
              1. the window's audio is appended to the record's WAV (IncrementalWAVWriter)
              2. first window only: a hidden placeholder History row is saved
              3. only then is the window decoded and boosted (SegmentedTranscriber)
              committed text (boosted, the start of key-up's transcript) →
                ProgressivePolisher: finished parts polished and cached
key up   ─► LiveDictation.stop; the WAV is rewritten whole, atomically, at the same URL;
              the placeholder row is replaced (HistoryStore.update)
              LongTranscription: in-flight window, then only the tail (≤ 15 s), stitched
              TextPipeline.prepare
              PolishService.polishLong: ≥ 250 words → sentence-safe parts of ~150 words,
                cached ones reused, the rest in parallel under one deadline
              TextPipeline.finalize, once, on the joined text (dictionary last)
```

- **Thresholds.** The segmented path is used only for recordings longer than 30 s at key-up;
  live work starts at 20 s. Polish works in parts only from 250 prepared words.
- **Same cuts on Retry.** Cuts are planned on WAV-round-tripped samples, so a Retry of the
  saved WAV cuts the same windows and decodes the same input.
- **The placeholder row** is hidden while recording (`HistoryStore.inProgress`) and deleted,
  with its WAV, on Esc. After a crash it stays as an "Interrupted" row with a playable
  partial WAV, and Retry works on it.
- **Fallbacks.** Any doubt goes back to the whole-buffer path and logs
  `live discarded: <reason>`: a short recording, the engine or dictionary changed while
  recording, a backlog too large to catch up, a window that failed, live audio that doesn't
  match the final buffer, a WAV append that failed. A polish part that times out, errors or
  is rejected by `PolishGuard` keeps its dictated text; the note says how many parts did.
- **Timing.** Every dictation and Retry logs one summary line to the `timing` category:
  `/usr/bin/log show --last 1h --predicate 'subsystem == "com.birdtownlabs.flow" AND category == "timing"'`.
  Per-window and per-part lines are `.info` on `speech` and `polish`. History's Timings
  measure from key-up too, so a dictation transcribed while it was recorded
  (`DictationTimings.transcribedWhileRecording`) shows no real-time factor: key-up only
  waited for its last few seconds.

## Rules for anyone changing this code

1. **The HUD never takes focus.** It is a non-activating `NSPanel`. If it became key, the
   user's text field would lose focus and there would be nothing to type into.
2. **Audio is saved before transcription.** A crash or engine failure must never lose what
   the user said. Failed records keep their audio and offer Retry. Live windows of a long
   recording obey it too: each window's audio is appended to the WAV and the placeholder
   row exists before that window is decoded.
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
