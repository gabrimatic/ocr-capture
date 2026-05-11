# OCR Capture

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: macOS](https://img.shields.io/badge/platform-macOS-lightgrey.svg)]()
[![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-native-blue.svg)]()
[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)]()

**Select any region of your screen, or pass in an image file, extract the text, copy it to your clipboard. One keystroke.**

Uses Apple's Vision framework (the same engine behind Live Text) for accurate, on-device OCR. Supports automatic language detection across all languages Vision recognizes. No network calls, no dependencies, no temp files kept.

---

## Quick Start

```bash
git clone https://github.com/gabrimatic/ocr-capture.git
cd ocr-capture
./setup.sh
```

One command. Compiles the binary, installs [skhd](https://github.com/koekeishiya/skhd) for the global hotkey, starts the service.

| Action | Key |
|--------|-----|
| Capture and OCR | **⌘⇧E** |

Press the shortcut, drag to select a region, release. The recognized text is in your clipboard. A notification confirms success.

---

## What It Does

- **Screen region OCR** via Apple Vision. Select any area, get the text.
- **Automatic language detection**. English, German, Persian, Arabic, Chinese, Japanese, Korean, and every other language Vision supports.
- **Reading order preservation**. Text is sorted top-to-bottom, left-to-right, matching the visual layout.
- **Clipboard output**. Recognized text goes straight to the clipboard. No file saved.
- **File input and stdout output**. OCR existing screenshots from scripts without starting interactive capture.
- **Accurate mode** with language correction. Uses Vision Revision 3 for the best available recognition quality.
- **Feedback**. Sound and macOS notification on success, failure, or empty result.
- **Global hotkey** via skhd. Works from any app, any context.

---

## How It Works

1. ⌘⇧E triggers macOS `screencapture -i` (interactive region selection)
2. The captured image loads via `CGImageSource` (direct, no intermediate conversions)
3. Apple Vision `VNRecognizeTextRequest` runs OCR with a 15-second timeout
4. Results are sorted by bounding box position to match reading order
5. Extracted text is copied to the clipboard via `NSPasteboard`
6. The temporary file is deleted, a notification confirms the result

For `--file`, the pipeline starts from the supplied image path and skips screen capture.

The entire pipeline runs locally. Nothing touches the network.

---

## Requirements

- macOS 13+ (Ventura or later)
- Xcode Command Line Tools (`xcode-select --install`)
- [Homebrew](https://brew.sh) (for installing skhd)
- [skhd](https://github.com/koekeishiya/skhd) for the global keyboard shortcut (installed by `setup.sh`)
- Accessibility permission for skhd (System Settings > Privacy & Security > Accessibility)
- Screen Recording permission for interactive capture (System Settings > Privacy & Security > Screen Recording)

---

## Configuration

The keyboard shortcut is defined in `~/.skhdrc`. To change it:

```bash
# Default binding
cmd + shift - e : /path/to/ocr-capture/ocr-capture

# Example: change to Ctrl+Shift+O
ctrl + shift - o : /path/to/ocr-capture/ocr-capture
```

Restart skhd after changes: `skhd --restart-service`

See the [skhd documentation](https://github.com/koekeishiya/skhd) for key syntax.

---

## CLI Usage

Interactive capture:

```bash
./ocr-capture
```

OCR an existing image and print the text:

```bash
./ocr-capture --file screenshot.png --stdout --no-copy --quiet
```

Options:

```text
Usage: ocr-capture [options]

Select a screen region, run OCR, and copy the recognized text to the clipboard.
With --file, OCR an existing image instead of starting an interactive capture.

Options:
  -f, --file PATH       OCR an existing image file.
      --stdout          Print recognized text to stdout.
      --no-copy         Do not copy recognized text to the clipboard.
      --quiet           Suppress sounds and notifications.
      --timeout SECONDS OCR timeout in seconds. Default: 15.
  -h, --help            Show this help.
```

---

## Privacy

Zero network calls. Everything runs on-device.

| Component | Runs at |
|-----------|---------|
| Screen capture | macOS screencapture (local) |
| OCR | Apple Vision framework (in-process) |
| Clipboard | NSPasteboard (local) |

Temporary screenshots use `mkstemp` for safe file creation and are deleted immediately after OCR. No data is stored, logged, or transmitted.

---

## Architecture

```
ocr-capture (single Swift binary)
  ├── screencapture -i (interactive region selection)
  ├── CGImageSource (direct image loading)
  ├── VNRecognizeTextRequest (Vision OCR, Revision 3, 15s timeout)
  ├── Bounding box sort (reading order: top→bottom, left→right)
  ├── NSPasteboard (clipboard output)
  └── osascript notification + NSSound (feedback)

skhd (hotkey daemon)
  └── ~/.skhdrc → binds ⌘⇧E to the binary
```

---

## Troubleshooting

<details>
<summary><strong>Nothing happens when pressing ⌘⇧E</strong></summary>

1. Check skhd is running: `launchctl list | grep skhd`
2. If not running: `skhd --start-service`
3. Verify Accessibility permission: System Settings > Privacy & Security > Accessibility > skhd must be enabled
4. After granting permission: `skhd --restart-service`
5. Check for errors: `cat /tmp/skhd_$(whoami).err.log`

</details>

<details>
<summary><strong>No text detected</strong></summary>

Vision works best with clear, readable text. Very small text, heavy stylization, or low-contrast images may yield partial or empty results. Try selecting a tighter region around the text. A notification will tell you when no text was found.

</details>

<details>
<summary><strong>OCR timed out</strong></summary>

Very large screen regions (e.g., an entire 4K display) may take longer to process. The default timeout is 15 seconds. Try selecting a smaller region focused on the text you need, or use `--timeout SECONDS` for file-based OCR.

</details>

<details>
<summary><strong>Empty or black capture</strong></summary>

This usually means Screen Recording permission is missing. Grant it in System Settings > Privacy & Security > Screen Recording. The notification will suggest this if it detects an empty capture.

</details>

<details>
<summary><strong>Wrong language detected</strong></summary>

Vision's automatic language detection handles most cases. For mixed-language content, it prioritizes the dominant language. Single words or very short text may occasionally misidentify the language.

</details>

---

## Uninstall

```bash
./setup.sh --uninstall
```

Or manually:

```bash
skhd --stop-service
brew uninstall skhd
trash ~/Developer/Projects/ocr-capture  # or remove the folder manually
# Remove the ⌘⇧E binding from ~/.skhdrc if you have other bindings,
# or delete ~/.skhdrc entirely if ocr-capture was the only entry
```

---

## License

MIT. See [LICENSE](LICENSE).

---

Created by [Soroush Yousefpour](https://gabrimatic.info)

[!["Buy Me A Coffee"](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://www.buymeacoffee.com/gabrimatic)
