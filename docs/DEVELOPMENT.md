# Development

[Overview](../README.md) | [Architecture](ARCHITECTURE.md) | [Contributing](../CONTRIBUTING.md)

## Prerequisites

The current source was validated with Flutter 3.41.9, Dart 3.11.5, and the Android SDK on Windows. The Dart SDK constraint is defined in [pubspec.yaml](../pubspec.yaml). Android is the actively tested target.

The checked-in Android configuration uses Android Gradle Plugin 8.11.1, Kotlin 2.2.20, and Gradle 8.14. The Gradle runtime needs JDK 17 or later; the app's Java and Kotlin source targets are aligned to JVM 11. Prefer the checked-in wrapper rather than upgrading Gradle independently to solve a plugin target mismatch.

```bash
flutter doctor -v
flutter pub get
flutter devices
flutter run -d <android-device-id>
```

`publish_to: 'none'` prevents accidental publication of the Dart package to pub.dev; it does not prevent distributing the Android app on Google Play.

## Checks

```bash
flutter analyze
flutter test
```

The Flutter tests cover transport races, chapter continuation, interruptions, file/web imports, voice selection and annotations, storage, preparation progress, and responsive reader/picker layouts. They mock platform channels and do not replace physical-device tests of Bluetooth, audio focus, or long background sessions.

Run native JVM tests from the Android directory:

```powershell
cd android
.\gradlew.bat :app:testDebugUnitTest
```

Native tests cover PCM handling, audio buffers, chapter caches, repeatable latent noise, and the synthesizer. Real-model smoke tests are skipped unless a verified pack is available locally:

```powershell
$env:DHEBEVOICE_TEST_MODELS='F:\path\to\supertonic-3'
# If an older Android Studio JBR has an incompatible Windows C++ runtime:
# $env:DHEBEVOICE_TEST_JAVA='C:\path\to\newer-jdk\bin\java.exe'
cd android
.\gradlew.bat :app:testDebugUnitTest
```

Do not commit model downloads or native benchmark outputs. `build/` is ignored.

## Separate Test App

To test alongside a Play-installed app without replacing its data:

```powershell
cd android
.\gradlew.bat :app:assembleDebug -PdhebeVoiceTestBuild=true
```

The opt-in debug variant uses package `com.dhebe.dhebevoice.test` and label **DhebeVoice Test**. The APK is written to `build/app/outputs/flutter-apk/app-debug.apk` from the repository root. Normal debug and release builds keep `com.dhebe.dhebevoice`. Verify the package before installing; a Play-signed app cannot be updated with an unrelated debug/upload signature.

Debug-only `DhebeVoiceTTS` logs record generation and handoff timing, not reading text. Redact all logs before sharing them: system and third-party logs may contain sensitive details.

## Controlled Runtime Benchmark

Pause narration in the Test app first: instrumentation restarts the Test process. Install the verified voice pack in that app, build `:app:assembleDebugAndroidTest` with `-PdhebeVoiceTestBuild=true`, and install the generated instrumentation APK alongside it.

```powershell
adb shell am instrument -w -e threads 2,4,2,4 com.dhebe.dhebevoice.test.test/com.dhebe.dhebevoice.SpeechRuntimeBenchmark
```

Add `-e provider xnnpack` before the runner name to compare that experimental backend with the default CPU backend. This is a benchmark option, not an enabled reader setting. The runner uses fixed text, five steps, M2, and normal speed, excluding warm-up/model loading from generation timing. It writes `cache/speech-runtime-benchmark-cpu.json` or `cache/speech-runtime-benchmark-xnnpack.json` inside the Test app. It never reads a user's book or plays audio and refuses to target the production package. Instrumentation is not packaged in the reader release.

## Release Builds

Keep `android/key.properties`, keystores, and publishing credentials local and ignored. Do not paste their contents into issues or logs. Configure release signing privately before distribution; without `key.properties`, the current Gradle configuration falls back to debug signing, which is not appropriate for a Play upload.

```bash
flutter build appbundle --release
```

The bundle is written to `build/app/outputs/bundle/release/app-release.aab`. Verify its package, version, signing certificate, manifest permissions, and release-mode neural playback before upload. Release tasks also check that R8 has not renamed required ONNX JNI classes.

The version is `versionName+versionCode` in `pubspec.yaml`. Use a higher version code than every previous Play upload, regardless of how often you built locally. Building or pushing a Git commit does not submit anything to Google Play. See [release notes](../CHANGELOG.md); source changes under Unreleased are not included in an older uploaded bundle.

## Physical-Device Checklist

- Cold start, first-run guide, opening an existing large library, and both themes.
- Play, rapid Pause/Resume/Stop, chapter completion, paragraph jumps, and voice/language changes while playing and paused.
- Notification, lock-screen, wired/Bluetooth controls, disconnects, temporary interruptions, and permanent audio-focus loss.
- Background playback with screen off, reopening the activity, and manufacturer battery restrictions.
- Android offline and online voices, consent, missing voice metadata, and persisted personal labels.
- Neural model download cancellation/retry, generation progress, low storage, long chapters, and preparation cancellation.
- Shared-link confirmation, closing progress without cancellation, stopping imports, partial failures, and saved reading positions.
- TXT encodings, EPUB limits, text-based PDF, unsupported/scanned PDFs, and narrow-screen keyboard layouts.
