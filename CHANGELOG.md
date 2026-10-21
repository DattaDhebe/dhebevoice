# Changelog

This file distinguishes current source changes from previously uploaded app bundles. A Git commit is not a Google Play release or approval.

## 1.3.0 (13)

Prepared on October 21, 2026, for the existing Google Play Closed testing -
Alpha track. This bundle has not yet been submitted or approved.

- Add offline paragraph bookmarks with editable, searchable notes and jump/play actions; store small metadata separately from full books.
- Add remembered Book List sorting by date, title, or chapter count.
- Fix Roman-numeral chapter badges and prevent local file hashes or unrelated URL digits from being mistaken for chapter numbers.
- Protect existing empty library files from accidental sample-book replacement.
- Reduce repeated chapter parsing and library scans during import merges; cache sorted library views.
- Handle missing temporary audio directories safely during native chapter preparation.
- Add persistence, corruption, playback-preservation, Unicode, and responsive UI regressions. No paid API or cloud service was added.
- See the [product and reliability review](docs/PRODUCT_REVIEW_2026-10-21.md) for market sources, tradeoffs, and validation limits.

## 1.2.4 (12)

Submitted on October 17, 2026, to the existing Google Play Closed testing -
Alpha track together with the updated phone screenshots. Play Console shows
**Changes in review**; automated quick checks run before review. This is not a
claim of approval or public production availability.

- Refresh the home reader with clearer book/chapter hierarchy, a compact borderless editor, an uncluttered empty state, and a persistent playback dock.
- Add home-screen paragraph shortcuts and direct voice-settings access; preserve full reading views, imports, text selection, and existing playback behavior.
- Show explicit Android voice-type metadata, or **Gender not provided** when the provider does not supply it.
- Add reversible personal Female/Male/Child labels, stored separately for each engine, voice ID, and language without interrupting playback.
- Add persistence, playback, save-failure, and small-screen regression coverage for voice labeling.
- Refresh the repository overview, screenshots, feature documentation, development guidance, and issue templates.
- Align the GitHub repository name with the DhebeVoice brand and update repository links; the Android app identity is unchanged.

The sample classics shown in the screenshots are not bundled with the app.
Roman-numeral EPUB chapter badges can still display an incorrect number;
narration generation can still buffer on slower devices.
[Submitted release-note text](assets/store/release-notes/1.2.4-en-US.txt).

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
