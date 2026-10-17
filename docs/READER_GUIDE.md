# Reader Guide

[Back to the overview](../README.md)

## Import Text or Books

Paste text into the reader, import a TXT, EPUB, or text-based PDF file, or share a web link from your browser. Confirm before replacing an open book with clipboard text so its saved position is not accidentally lost.

Shared links open a review popup. Nothing downloads until you press **Start import**. The progress view identifies the current chapter when the source provides a title or a recognizable chapter link. Closing the popup hides it while downloading continues; the compact progress area can reopen it. Only **Stop import** cancels a web import. Completed chapters are kept when downloading is stopped or a later request fails.

An import cannot unlock paid content or pass a site's sign-in or browser-verification screen. A 403 response means the source refused access; a host-lookup error means the phone could not resolve or reach that host. Check the URL and your connection, or use a local file or readable text you are authorized to access.

PDF import extracts embedded text. Scanned pages need OCR in another tool first. EPUB support does not remove DRM. See [size limits and import safeguards](SPEECH_AND_IMPORTS.md#import-limits).

## Choose a Voice

Open Settings and select a language by its full name and region. **Choose voice** opens searchable cards. Selection is staged until you press **Use voice**; Cancel leaves the current voice unchanged. Search by name, language, or voice type. Offline/online information comes from the installed engine; missing metadata is not treated as proof that a voice works offline.

The Android engine may not report gender. Such cards say **Gender not provided** rather than guessing from an internal code or friendly name. To annotate a voice after listening:

1. Select its card in the voice picker.
2. Tap the **Label selected voice type** icon beside the picker title.
3. Choose Female, Male, or Child. **Your label** distinguishes it from provider metadata.
4. Choose **Use provider label** to remove your annotation.

Your annotation is stored separately for each engine, original voice ID, and language. It does not change the audio and can be edited while playback continues. If the engine cannot be identified, labeling is unavailable rather than attaching a label to the wrong provider.

Online Android voices require confirmation because text may be sent to their provider. DhebeVoice does not add a metered TTS API or require a paid API key. A voice's engine-reported quality label is not an independent test of naturalness.

## Optional Neural Speech

Download the Supertonic 3 pack in Settings after reviewing its size and model terms. The download is approximately 402 MB; keep at least 850 MB free for installation. Files are SHA-256 verified before use. Switch the Speech engine to Supertonic after installation; switching back to Android does not delete your books.

Ten narrators have friendly names. Their supported languages include English and Hindi; language selection changes pronunciation, not the text or its meaning. The pack runs on-device at five synthesis steps. Pitch is fixed for this engine, while Speech rate has an independent multiplier.

Default playback begins when the first segment is ready and prepares upcoming segments in the background. A preparation popup appears for longer waits and shows measurable stages when available. **Hide** keeps preparing; **Stop** cancels. Slower devices can still buffer between segments.

**Wait for the whole chapter (optional)** is the Settings switch for preparing chapter audio before playback. It trades a longer initial wait for having the current chapter's audio ready before playback. Prepared audio is temporary, not a saved audiobook export. See [neural speech limits](SPEECH_AND_IMPORTS.md#neural-preparation).

## Playback and Reading Position

Play, Pause, and Stop stay available while scrolling and in full reading views. Chapter controls move between chapters; paragraph controls move within the chapter. The current chapter and paragraph are tracked, and search results can start reading from a specific place.

The home screen groups the current book and chapter above the compact editable text. Now reading stays below it, with previous/next paragraph arrows, Play from paragraph, and View full. Tap the selected-voice row to open voice and playback settings. While typing, the screen prioritizes the editor and keeps the playback dock accessible.

Voice and language changes apply at the next speech segment without requiring manual Play. A paused reader stays paused. Neural reading positions are saved at segment boundaries, not at individual spoken words; reopening may repeat part of a segment.

Notification, lock-screen, and Bluetooth controls use the same transport state as the in-app controls. A headphone disconnect pauses playback. Reconnecting alone does not start speech. A temporary audio interruption may pause and later resume speech only if you have not paused or stopped it; permanent audio-focus loss requires manual Play.

The sleep timer pauses at its deadline without resetting your place. It spans chapters and manual pauses within the current app session. Stop cancels it.

## If Playback Stops

Check notification permissions, the installed Android TTS engine and voice download, and the phone's background/battery settings. Manufacturer restrictions can affect background operation. Neural generation speed depends on the device and available resources; a visible preparation state is not necessarily a crash.

If the problem persists, [report it](https://github.com/DattaDhebe/dhebevoice/issues/new/choose) with your app version, Android version, engine and voice, audio output, and whether the screen was locked. Do not attach private books, credentials, or unredacted device logs.
