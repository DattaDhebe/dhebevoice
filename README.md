# DhebeVoice

**Long-form reading, aloud.**

[Google Play closed testing](https://play.google.com/store/apps/details?id=com.dhebe.dhebevoice) · [Features](#highlights) · [Source code](lib)

<p align="center">
  <img src="assets/store/screenshots/screen-1-home.png" alt="DhebeVoice reading screen" width="30%">
  <img src="assets/store/screenshots/screen-3-library.jpg" alt="DhebeVoice saved book library" width="30%">
  <img src="assets/store/screenshots/screen-4-settings.png" alt="DhebeVoice settings screen" width="30%">
</p>

DhebeVoice is a Flutter-based Android text-to-speech reader for long-form reading. It helps users listen to pasted text, imported files, and readable web pages with chapter-aware playback, paragraph controls, and background media controls.

## Project Direction

This repository sits at the intersection of **accessible application development and speech AI** in my portfolio. It complements my model-training work in [tts_humanize](https://github.com/DattaDhebe/tts_humanize) and [personal-voice-tts](https://github.com/DattaDhebe/personal-voice-tts) by focusing on the user-facing reading experience.

## Highlights

- Read aloud pasted text with Android TTS voices
- Import `.txt`, `.epub`, and `.pdf` files
- Import readable web pages and shared web links
- Save imported books and reopen them from the in-app library
- Play from the current paragraph or jump to a specific paragraph
- Move chapter by chapter with autoplay support
- Continue playback with Android notification and media controls
- Choose voice, speech rate, pitch, volume, and theme

## Import Sources

DhebeVoice is designed for content the user owns, is licensed to access, or that is in the public domain.

Supported reading flows:

- Paste text directly into the editor
- Import local `.txt`, `.epub`, and `.pdf` files
- Share a readable web link into the app
- Start web import manually from inside the app

Import behavior and limits:

- Shared links wait for Start. Closing the progress popup keeps downloading; Stop cancels the web request and saves completed chapters.
- A later download failure keeps completed chapters and offers a retry. Re-imports merge overlapping books without replacing saved chapters or interrupting the current reader.
- Web imports are limited to 200 chapters, 2 MB per page, and about 12.6 million text characters per import. Requests are sequential and spaced apart. Access restrictions, sign-in pages, and browser verification are not bypassed.
- Local files are limited to 50 MB. TXT supports UTF-8 and BOM-marked UTF-16. PDF imports extract embedded text, not OCR, with a 1,500-page limit.
- EPUB imports check expanded size (100 MB total, 20 MB per entry, 5,000 entries) before parsing. Both EPUB and PDF have a text limit of about 12.6 million characters.
- Web import relies on readable HTML and chapter links. JavaScript-only sites and some site layouts may not be supported. File parsing runs on a worker; stopping a local import discards its result after parsing finishes.

## Main Features

### Reader

- Large editable reading area
- `View full` popup for reading content
- Text selection playback
- Paragraph-aware progress tracking
- Search paragraphs by text or number and play from the matching result
- Confirm before replacing open text from the clipboard

### Library

- Book List for imported books and web content
- Chapter browser with current chapter tracking
- Sample starter book for first-time users
- Search books and chapters; pickers open around the current reading position
- Confirm book deletion without leaving the Book List

### Playback

- Play, pause, stop, previous, and next controls
- Background playback support
- Lock-screen and notification media controls
- Paragraph and chapter handoff support
- Transient audio interruptions pause spoken content and resume only if the user has not paused or stopped it. Permanent focus loss requires manual Play, following [Android audio focus guidance](https://developer.android.com/media/optimize/audio-focus).
- Disconnecting Bluetooth or wired headphones pauses playback; reconnecting alone never starts speech through a different output.
- Headset, notification, and in-app controls share transport state. Newer Play/Pause/Stop commands cancel stale work; chapter transitions retain the media session, and skipping while paused stays paused.
- A 15, 30, 45, or 60-minute sleep timer pauses without resetting your place. It continues across chapters and manual pauses; Stop cancels it. The timer lasts for the current app session.
- Playback controls stay visible in both full-reading views
- The player distinguishes preparing, playing, paused, and stopped states. Longer startup, segment, or voice-change waits open a preparation popup after 700 ms; Hide keeps preparing and Stop cancels. The popup closes automatically when speech starts and never opens while the app is in the background.
- Neural preparation reports real text-encoding, refinement, and audio-writing stages, not an estimated completion time. Model loading and Android TTS waits use an indeterminate bar when measurable progress is unavailable.
- Supertonic defaults to starting playback when the first segment is ready and generating future audio in the background. A rolling window covers up to eight upcoming segments and 1,200 text characters, including runs of short paragraphs. The first segment never waits for that window to finish; matching future audio is retained across handoffs. Quality stays at five steps and speech rate is not changed. Generation slower than playback can still cause buffering on some phones.
- Whole-chapter preparation remains an optional Settings switch for users who prefer a longer initial wait over conversion gaps. Its popup reports completed speech segments and refinement stages. No whole chapter is loaded into RAM.
- Voice and language selections apply automatically at the next speech segment without pausing the reader. A language change keeps the same Supertonic narrator; it changes pronunciation, not the written text. A paused reader stays paused.
- Supertonic also prepares the next audio decoder ahead of playback and trims only near-silent segment edges, keeping short consonant margins and internal pauses. Separate model requests can still vary in prosody; this is not a guarantee of cloud-level continuous narration.
- Neural synthesis uses repeatable, narrator/language-specific Gaussian noise. Each latent channel keeps the same noise prefix across different paragraph lengths, removing per-request random rerolls without changing voice styles, speed, or refinement steps. Text-dependent delivery can still vary; this is not voice cloning or a promise of identical prosody.
- Neural narration uses Quality (5 synthesis steps). The experimental 3-step Faster mode was removed because of reported distorted speech; saved 3-step selections migrate to Quality without changing speech rate. Neural Speech rate shows an actual multiplier, independently of generation quality. Paragraph handoffs do not wait for reading-position disk writes.
- Chapter preparation is limited to 50,000 text characters, 400 speech segments, and 256 MB of temporary audio, with 64 MB free storage reserved. Stop deletes prepared audio. Pause during preparation cancels the job; Resume prepares it again. Voice, language, or rate changes prepare the remaining chapter at the next segment boundary. Selecting a different chapter or section prepares only that new selection. Preparation restarts after process death; this is not a persistent audiobook export.
- Android voice settings include an online-only shortcut showing voices actually exposed by the installed engine. Online selection requires consent before text can be sent to the provider; no paid API key is used by DhebeVoice.
- Choose voice uses distinct Supertonic nicknames (Asha, Mira, Clara, Iris, Nora, Arun, Theo, Rowan, Felix, Leo). Technical Android voice IDs get stable, gender-neutral friendly names, with duplicate names resolved within each language. Existing human-readable provider names are retained. Hold a card to see the original engine ID; saved selections and synthesis still use that ID, never the nickname. These are app display names, not new models or provider endorsements.

### Setup

- First-run guide
- Voice cards show Female, Male, or Child when the provider reports it. Android voices without gender metadata show "Gender not provided" instead of a guess. Select a voice and use the label icon to save your own local voice-type label; "Use provider label" clears it. Personal labels are scoped to the engine, original voice ID, and language and do not change audio or interrupt playback.
- Readable language/region names and a searchable avatar-card voice picker with explicit selection confirmation. Only installed voices are offered; online voices still require consent. Icons reflect known voice metadata, not invented voice identities.
- Light, dark, and follow-device theme options
- Consistent responsive layouts with narrow-screen and large-text widget tests

## Tech Stack

### Optional Neural Narration (Android)

In Settings, download the optional **Supertonic 3** pack (about 402 MB) and select it under Speech engine. Ten voices support 31 languages including English and Hindi. Inference runs on the device, off the UI thread; no TTS API key, subscription, or metered cloud API is used. Android TTS remains the default and switching back does not delete your books.

- Downloads require confirmation and SHA-256 verification. Cancel/retry and deletion are available. Allow at least 850 MB free storage; performance and memory use depend on the phone.
- Pause/resume retains the current generated segment while the app process lives. Saved book position is at segment boundaries, not individual neural speech words. Pitch is fixed; rate changes affect subsequent segments. Slower devices may have gaps between segments.
- The [official Supertonic archive](https://huggingface.co/supertone-oss-archive/supertonic-3) uses OpenRAIL-M model terms and MIT inference code. The upstream project is archived. Full notices are included in Settings > Open-source and voice model licenses.
- Android voices can be filtered by Offline/Online. Online voices are supplied by the installed TTS engine and may transmit reading text to its provider. DhebeVoice adds no paid cloud TTS API; provider terms and connectivity/data charges still apply. Engine-reported quality is not an independent naturalness assessment.
- Kokoro's Apache-2.0 model was evaluated as an alternative, but is **not integrated**: the mobile English pronunciation path needs further unknown-word and license validation. No unofficial cloud endpoints or public demo services are used.

Native inference smoke test (requires the verified Supertonic pack files in a local directory):

```powershell
$env:DHEBEVOICE_TEST_MODELS='F:\path\to\supertonic-3'
# Optional on Windows: use a newer JDK when Android Studio's bundled C++ runtime is too old.
# $env:DHEBEVOICE_TEST_JAVA='C:\path\to\newer-jdk\bin\java.exe'
cd android
.\gradlew.bat :app:testDebugUnitTest
```

The smoke test is skipped when this environment variable is absent. Device testing of neural narration, Bluetooth controls, and long background sessions is still required before a Play release.

For a controlled CPU comparison, build `:app:assembleDebugAndroidTest` with `-PdhebeVoiceTestBuild=true`, install its test APK alongside DhebeVoice Test, and run `adb shell am instrument -w -e threads 2,4,2,4 com.dhebe.dhebevoice.test.test/com.dhebe.dhebevoice.SpeechRuntimeBenchmark`. Add `-e provider xnnpack` before the runner name to measure the optimized mobile backend instead of the default CPU backend. Pause the reader first: instrumentation restarts only the Test process. The benchmark requires the downloaded model pack, uses fixed sample text, five steps, M2 and normal speed, excludes model loading/warm-up from generation timings, and writes `cache/speech-runtime-benchmark-cpu.json` (or `-xnnpack.json`) inside the Test app. It never plays audio or reads the user's book. The runner refuses to run against the production package and is not included in the reader APK.

### Dependencies

- Flutter
- Provider
- `flutter_tts`
- `audio_service`
- `audio_session`
- `receive_sharing_intent`

## Project Status

This repository contains the active source for the DhebeVoice Android app package:

- App name: `DhebeVoice`
- Android package: `com.dhebe.dhebevoice`

The Android app is in Google Play closed testing. The repository includes iOS targets, but the current validation and release workflow focus on Android. Some capabilities are still being developed.

## Local Development

Install Flutter, then run:

```bash
flutter pub get
flutter run
```

For platform-specific setup, see the [Flutter documentation](https://docs.flutter.dev/get-started/install).

To test alongside the Play-installed app without touching its books or settings:

```powershell
cd android
.\gradlew.bat :app:assembleDebug -PdhebeVoiceTestBuild=true
```

This opt-in debug build uses package `com.dhebe.dhebevoice.test` and label `DhebeVoice Test`. Release builds and normal debug builds keep the original package. Debug-only `DhebeVoiceTTS` log messages record generation and handoff timings, never reading text.

Run checks:

```bash
flutter analyze
flutter test
```

Build a release bundle:

```bash
flutter build appbundle --release
```

## Repository Metadata Suggestions

These are good GitHub "About" values for this repo:

- Description: `Android text-to-speech reader built with Flutter for text, EPUB, PDF, and readable web pages.`
- Website: `https://play.google.com/store/apps/details?id=com.dhebe.dhebevoice`
- Topics:
  - `flutter`
  - `android`
  - `text-to-speech`
  - `tts`
  - `epub-reader`
  - `pdf-reader`
  - `read-aloud`
  - `accessibility`
  - `web-reader`

## Notes

- Web import should only be used for content the user is authorized to access.
- Android TTS behavior can vary by device ROM, voice engine, and battery/background restrictions.
## Related projects

- [Personal Voice TTS](https://github.com/DattaDhebe/personal-voice-tts) — training and inference workflow for personalized VITS models
- [TTS Humanize](https://github.com/DattaDhebe/tts_humanize) — GPU-accelerated Coqui TTS experimentation

## License

See the repository for the current license and project configuration.
