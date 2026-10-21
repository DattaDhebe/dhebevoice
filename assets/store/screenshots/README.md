# Store Screenshots

Seven real-device captures of the DhebeVoice 1.2.4 UI, taken on
October 17, 2026, using the separate DhebeVoice Test app on Android 16. They
show the 1.2.4 reading experience and replace the older 1.2.3 listing images.

All seven replacement phone screenshots were uploaded and saved as a Google
Play Console listing draft on October 17, 2026, then submitted together with
version 1.2.4 (12) to Closed testing - Alpha on the same day. On October 21,
Play Console confirmed that release was available to Alpha testers. This is not
public production availability. The icon, feature graphic, listing descriptions,
tester audience, and publishing mode were left unchanged.

## Upload Order

| File | Screen |
| --- | --- |
| [phone-01-reader.png](phone-01-reader.png) | Current book, chapter controls, and reading content |
| [phone-02-now-reading.png](phone-02-now-reading.png) | Actual Android TTS playback and highlighted paragraph |
| [phone-03-library.png](phone-03-library.png) | Searchable Book List with imported classics |
| [phone-04-full-reading.png](phone-04-full-reading.png) | Full Now reading view with fixed transport controls |
| [phone-07-voices.png](phone-07-voices.png) | Installed voice picker with offline/online labels |
| [phone-06-settings.png](phone-06-settings.png) | Full language names and voice settings |
| [phone-05-web-import.png](phone-05-web-import.png) | Web-link import confirmation and content-rights reminder |

Each file is a 1080 x 1920, 24-bit RGB PNG with no alpha and is smaller than
8 MB. Captures are not AI-generated, resized, composited, or retouched. Only a
lossless RGB export was performed to remove the redundant alpha channel.
Android status-bar demo mode hid notification icons during capture. Temporary
viewport and density changes were reset afterward. No private documents,
accounts, device dumps, or Test launcher labels appear in the published images.

The chapter-browser screen was excluded after capture testing revealed that
Roman-numeral EPUB headings can receive an incorrect numeric badge from a
digit in the local file identifier. This issue is fixed in current source;
these captures still represent the submitted 1.2.4 reading experience.

## Demonstration Books

- **Alice's Adventures in Wonderland**, Lewis Carroll (1865):
  [Project Gutenberg ebook 11](https://www.gutenberg.org/ebooks/11),
  [official EPUB download](https://www.gutenberg.org/ebooks/11.epub.noimages).
- **Pride and Prejudice**, Jane Austen (1813):
  [Project Gutenberg ebook 1342](https://www.gutenberg.org/ebooks/1342),
  [official EPUB download](https://www.gutenberg.org/ebooks/1342.epub.noimages).

Project Gutenberg identifies these editions as public domain in the USA.
Check applicable rights in other jurisdictions before redistribution. The full
EPUBs and their notices remain separate from the app and are not committed to
this repository. Local downloads used for capture are under the ignored
`build/device-test/` directory and on the test phone in `Download`.

**The Lantern Keeper** is original demonstration text created for this capture
session. **Getting Started with DhebeVoice** is the app's removable starter
sample. The Book List screenshot does not imply a bundled commercial catalog,
a partnership with the authors or Project Gutenberg, or a book-download service.

## Capture And Upload Checks

- Use the Test variant; do not clear or modify the Play-installed app's library.
- Import only shareable content and hide private notification previews.
- Verify real controls, titles, and playback state before each capture.
- Export PNGs without alpha and visually inspect every image.
- Restore temporary display/status-bar settings and stop test narration.
- Replace only phone screenshots in Play Console; preserve icon, feature
  graphic, tablet screenshots, descriptions, and the release already in review.
- Submit listing changes with the matching app release, not as a standalone
  update showing features absent from the submitted bundle.

See [Google Play preview asset guidance](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en)
for current upload requirements.
