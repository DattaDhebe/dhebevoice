# DhebeVoice

DhebeVoice is a Flutter-based Android text-to-speech reader for long-form reading. It helps users listen to pasted text, imported files, and readable web pages with chapter-aware playback, paragraph controls, and background media controls.

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

## Main Features

### Reader

- Large editable reading area
- `View full` popup for reading content
- Text selection playback
- Paragraph-aware progress tracking

### Library

- Book List for imported books and web content
- Chapter browser with current chapter tracking
- Sample starter book for first-time users

### Playback

- Play, pause, stop, previous, and next controls
- Background playback support
- Lock-screen and notification media controls
- Paragraph and chapter handoff support

### Setup

- First-run guide
- Voice metadata labels
- Light and dark theme support

## Tech Stack

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

## Local Development

```bash
flutter pub get
flutter run
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
