# Contributing

Thank you for helping improve DhebeVoice. Android is the actively tested target. Start with the [development guide](docs/DEVELOPMENT.md) and [architecture map](docs/ARCHITECTURE.md).

## Report an Issue

Use the [issue templates](https://github.com/DattaDhebe/dhebevoice/issues/new/choose) and include reproducible steps, app version/build, Android version, device, speech engine and original voice ID, audio output, and whether the app was backgrounded or locked. For imports, specify the file type or a safe public URL and the exact error.

Use the removable sample book or text you may share. Do not attach private books, copyrighted chapters without permission, keystores, service-account JSON, passwords, or unredacted logs. Report security-sensitive details privately to the maintainer using an available private contact route rather than opening a public issue with secrets.

## Make a Change

1. Discuss changes that add engines, change playback semantics, introduce a backend, or affect content/privacy behavior before implementing them.
2. Keep patches focused, preserve existing user data, and add a regression test for the behavior being changed.
3. Run `flutter analyze` and `flutter test`. Run native tests for Kotlin, audio-buffer, model, or runtime changes.
4. Test layout changes with both themes, large text, narrow screens, and the keyboard. Test playback changes on a physical Android device using the separate Test app.
5. Describe the change, test results, known limits, and device-only checks in the pull request.

No paid TTS API, hidden online fallback, access-control bypass, or undocumented transmission of reading text should be introduced. Free model terms still need review and bundled notices. Unknown voice metadata must stay unknown unless a user explicitly labels it.

Do not commit build outputs, downloaded models, test-device dumps, IDE-only settings, or signing/publishing secrets. Do not change release version codes or publishing state as a side effect of an unrelated fix.

The repository does not currently declare a project-wide source license. Do not assume that public visibility or third-party notices grant a license to redistribute the application; discuss licensing with the maintainer first.
