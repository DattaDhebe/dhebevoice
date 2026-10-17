# Changelog

This file distinguishes current source changes from previously uploaded app bundles. A Git commit is not a Google Play release or approval.

## Unreleased

- Refresh the home reader with clearer book/chapter hierarchy, a compact borderless editor, an uncluttered empty state, and a persistent playback dock.
- Add home-screen paragraph shortcuts and direct voice-settings access; preserve full reading views, imports, text selection, and existing playback behavior.
- Show explicit Android voice-type metadata, or **Gender not provided** when the provider does not supply it.
- Add reversible personal Female/Male/Child labels, stored separately for each engine, voice ID, and language without interrupting playback.
- Add persistence, playback, save-failure, and small-screen regression coverage for voice labeling.
- Refresh the repository overview, screenshots, feature documentation, development guidance, and issue templates.
- Align the GitHub repository name with the DhebeVoice brand and update repository links; the Android app identity is unchanged.

## 1.2.3 (11)

Prepared and submitted to the existing Google Play Closed testing - Alpha track. Submission is not a claim of review approval or public production availability.

- Add friendly narrator names, readable language names, and a searchable avatar-card voice picker.
- Apply voice and language changes at the next speech segment without a manual playback restart.
- Improve neural preparation progress, rolling background preloading, decoder handoffs, and narrator-noise consistency.
- Add optional whole-chapter audio preparation with bounded temporary storage.
- Retain five-step Quality synthesis and remove the distorted experimental Faster mode without changing speech rate.
- Improve playback controls and smaller-screen layouts, and fix the web-import dialog lifecycle error.

Generation speed still depends on the device. Buffering and text-dependent variation between segments may remain. [Uploaded release-note text](assets/store/release-notes/1.2.3-en-US.txt).

Earlier changes are recorded in [Git history](https://github.com/DattaDhebe/dhebevoice/commits/main/).
