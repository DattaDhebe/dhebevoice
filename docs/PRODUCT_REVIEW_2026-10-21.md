# Product And Reliability Review

Date: October 21, 2026. This is a directional feature benchmark using official
product documentation, not market-size research or a claim of hands-on testing
of competing apps. Plan-specific availability can vary.

## Market Signals

| Product | Relevant documented capability | Implication for DhebeVoice |
| --- | --- | --- |
| [@Voice Aloud Reader](https://www.hyperionics.com/atvoice/AppFeatures.html) | Bookmarks with notes/search, sortable reading lists, broad document support | Navigation and local content management matter alongside voice quality. |
| [NaturalReader](https://help.naturalreaders.com/en/articles/11543218-working-with-text-and-audio-personal-version) | Document bookmarks and highlighted reading locations | Saved passages are a useful complement to automatic resume. |
| [Speechify](https://speechify.com/news/back-to-school-2025/) | Note-taking, highlighting, and bookmarking tools | Support revisiting ideas without adding a paid generative service. |

The practical positioning is a local-first long-form reader: readable imports,
reliable transport, installed Android voices, and optional on-device neural
speech without requiring a paid TTS API. Feature overlap is evidence for a
useful baseline, not proof of demand, adoption, or voice-quality parity.

## Implemented In This Pass

- Save the current paragraph as an offline bookmark without restarting speech.
- Add, edit, search, and delete notes; open a saved passage or explicitly play
  from it. Chapter URLs preserve navigation when an earlier chapter is imported.
- Keep bookmark metadata separate from chapter text, serialize overlapping
  writes, retain old data on save failure, and prevent corrupt metadata from
  being silently overwritten. Notes support emoji-aware character limits.
- Sort the Book List by newest import, title, or chapter count, remembering
  the preference and retaining search and deletion confirmation.
- Correct Arabic/Roman chapter labels without treating file hashes, hostnames,
  query values, or unrelated title years as chapter numbers.
- Treat an existing empty library file as corruption, not a fresh installation;
  this prevents sample-book seeding from overwriting that file.
- Cache chapter numbers before merge sorting and index books once for merge
  reconciliation instead of scanning the library for each book.
- Check temporary audio directories explicitly instead of dereferencing a
  nullable parent during chapter preparation.

## Deliberately Deferred

Cloud voice APIs, cloud sync, and generative summaries were not added: they
introduce costs, service dependencies, and additional data handling. Local OCR,
pronunciation rules, a listening queue, and backup/export are candidates for a
separate scoped iteration. Neural synthesis can still buffer on slower phones;
there is no claim of gapless playback or faster inference from this work.

## Validation Scope

The final automated pass reports 254 passing Flutter tests, 36 passing native
tests with no skips, and four passing real-font UI capture checks. The separate
Test APK build succeeds. Static analysis is checked separately before handoff.

The regression suite covers persistence failures, corruption, duplicate marks,
chapter reordering, playback-state preservation, sorting, narrow screens, large
text, and both themes. Native tests include real-model checks when the verified
local pack is available. The separate Test APK is built without modifying the
Play-installed app. No phone was connected for this pass, so Bluetooth,
lock-screen behavior, interruption handling, and long background sessions still
need device testing. These source changes have not been submitted to Play.
