# DhebeVoice

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
- A 15, 30, 45, or 60-minute sleep timer pauses without resetting your place. It continues across chapters and manual pauses; Stop cancels it. The timer lasts for the current app session.
- Playback controls stay visible in both full-reading views

### Setup

- First-run guide
- Voice metadata labels
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
