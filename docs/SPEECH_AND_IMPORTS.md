# Speech and Import Behavior

[Overview](../README.md) | [Reader guide](READER_GUIDE.md) | [Development](DEVELOPMENT.md)

## Playback State

The reader distinguishes preparing, playing, paused, and stopped states. Newer transport commands supersede stale work. Headset, notification, and in-app actions use the same service; chapter transitions retain the media session, and chapter skipping while paused stays paused.

Speech respects [Android audio focus](https://developer.android.com/media/optimize/audio-focus). Temporary interruptions may pause spoken content and resume only if no subsequent user Pause or Stop has occurred. Permanent focus loss requires manual Play. Disconnecting headphones pauses narration; reconnecting alone does not resume through a different output.

Longer speech waits open a preparation popup after 700 ms. Hide leaves preparation running, and Stop cancels. It closes when audio starts and does not open while the app is in the background. Android TTS and model-loading waits use an indeterminate bar when the engine cannot provide real progress.

## Neural Preparation

Supertonic uses Quality mode at five synthesis steps. The experimental three-step Faster mode was removed following distorted-speech reports; saved Faster selections migrate to Quality without changing speech rate.

Default playback starts as soon as the first segment is ready, while a rolling window prepares up to eight future segments and 1,200 text characters. The first segment does not wait for the window. Matching future audio is retained across handoffs, and position persistence does not block the next paragraph. Decoder preparation and conservative near-silence trimming reduce handoff overhead without removing internal pauses or deliberately speeding up narration.

Narrator/language-specific Gaussian noise is repeatable. Each latent channel retains its prefix across different paragraph lengths, avoiding a new random initialization for every paragraph. Different text can still change delivery: this is not voice cloning or a guarantee of identical prosody.

Optional whole-chapter preparation is limited to 50,000 text characters, 400 speech segments, and 256 MB of temporary audio, with 64 MB free storage reserved. No entire chapter waveform is loaded into RAM. Stop deletes prepared audio. Pause during preparation cancels that job; Resume prepares it again. Voice, language, or rate changes prepare the remaining text at the next speech boundary. Chapter changes or selected sections prepare the new selection instead. Process death requires preparation again; this cache is not a permanent audiobook export.

CPU generation can be slower than real-time playback on some phones. Background preloading cannot remove all gaps in that case. Whole-chapter preparation trades startup time for fewer conversion waits; installed Android voices are an alternative for devices that cannot synthesize neural speech quickly enough.

The optional pack contains ten narrators and supports 31 languages. It downloads about 402 MB of verified model data; allow at least 850 MB free storage. Inference is local. The upstream [Supertonic 3 archive](https://huggingface.co/supertone-oss-archive/supertonic-3) is archived and uses OpenRAIL-M model terms with MIT inference-code notices. Read the bundled licenses before use or redistribution. Kokoro and unofficial free online demo endpoints are not integrated.

## Android Voice Metadata

Android's standard [Voice API](https://developer.android.com/reference/android/speech/tts/Voice) has no gender field. DhebeVoice accepts recognizable provider-supplied fields or explicit voice-name hints, but does not infer gender from opaque IDs, nicknames, or pitch. Missing data is displayed as **Gender not provided**.

Personal Female/Male/Child labels are display metadata, keyed by engine package, original voice ID, and language. **Your label** marks an annotation, and **Use provider label** removes it. Updating a label never changes transport state or the synthesis voice. Friendly nicknames also leave engine IDs unchanged.

Only installed voices are offered. Offline/online labels use provider metadata; unknown network requirements remain unknown. Online selection asks for consent before reading text may be sent to that provider. DhebeVoice includes no paid cloud TTS API integration; provider terms, connectivity, and data charges still apply.

## Import Limits

| Input | Limits and behavior |
| --- | --- |
| Web | Up to 200 chapters, 2 MB per page, and approximately 12.6 million text characters per import. Requests are sequential and spaced apart. |
| Local files | Up to 50 MB per file. Parsing runs on a worker. |
| TXT | UTF-8 and BOM-marked UTF-16. |
| EPUB | Expanded archive checks: 100 MB total, 20 MB per entry, and 5,000 entries; approximately 12.6 million extracted text characters. No DRM removal. |
| PDF | Embedded-text extraction, up to 1,500 pages and approximately 12.6 million text characters. No scanned-image OCR. |

Shared links wait for Start. Hiding the progress view keeps importing; Stop cancels a web request and retains completed chapters. Later failures retain completed chapters and allow retry. Re-imports merge overlaps without replacing saved chapters or interrupting the current book. Stopping local-file import discards its result after parsing finishes rather than killing the parser mid-operation.

Import depends on readable HTML and recognizable chapter links. JavaScript-only pages and unsupported layouts may fail. Authentication, browser verification, paywalls, and other access restrictions are not bypassed. Host lookup and access-denied errors are distinct and should be reported without private URL tokens or copyrighted book attachments.
