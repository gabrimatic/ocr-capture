# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [Unreleased]

### Added

- Non-interactive image OCR with `--file`, `--stdout`, `--no-copy`, `--quiet`, and `--timeout`
- Repeatable CLI tests that verify help output, missing-file handling, and end-to-end OCR from a generated image fixture
- `make build`, `make test`, `make install`, and `make uninstall` targets
- macOS GitHub Actions workflow for pull request and main-branch verification
- Automatic fast-recognition fallback when accurate OCR exceeds the timeout, so a capture degrades gracefully instead of failing (seen on newer macOS where Vision compiles its accurate model on first use)
- Interactive captures keep warming the accurate model in the background after a fallback, so the next capture succeeds in accurate mode
- Regression tests for reading order (multi-line fixture), the timeout fallback, hard timeouts, corrupt images, argument validation, exact `--stdout` output, and clipboard copy (CI or opt-in)
- CI: shellcheck lint job, least-privilege workflow token, concurrency cancellation, job timeouts, and an explicit build step

### Changed

- Setup now compiles through `xcrun swiftc` for a more reliable Command Line Tools path
- Notification text escaping now handles backslashes, quotes, and newlines on the existing `osascript` notification path
- Removed the explicit Vision Revision 3 pin: even though the default also resolves to revision 3, an explicitly pinned request takes a separate legacy initialization path whose model compilation is measurably slower on newer macOS
- `--timeout` now validates its range (1-3600 seconds), and duplicate image-path arguments produce a consistent usage error
- `setup.sh` preserves a user-customized hotkey when updating the binding after a project move, and only reports an update when the file actually changed

### Fixed

- OCR no longer fails permanently on macOS releases where Vision's accurate model needs a one-time on-device compile longer than the timeout
- Command execution via the skhd hotkey binding when the project path contains shell metacharacters: the binding is now shell-quoted (skhd runs bindings through `$SHELL -c`)
- `setup.sh --uninstall` no longer deletes unrelated `.skhdrc` lines that merely contain the text "ocr-capture"
- Interactive captures that find no text no longer leak the temporary screenshot (`exit()` was skipping cleanup)
- Failure and empty-result feedback sounds are no longer cut off by process exit
- Notifications can no longer crash the tool if `osascript` is unavailable
- `--stdout` output is now exactly the recognized text: Vision's internal model-loader diagnostics can no longer leak into stdout and corrupt scripted pipelines
- Reading order now uses deterministic row clustering; the previous sort comparator violated strict-weak-ordering and could produce unstable ordering
- Clipboard copy failures are now detected and reported instead of exiting successfully without copying

---

## [1.1.0] - 2026-04-07

### Added

- macOS notifications on success, failure, and empty results
- Sound feedback (Pop on success, Basso on failure)
- 15-second OCR timeout to prevent hangs on large captures
- Reading order sort (top-to-bottom, left-to-right) for multi-line text
- Empty/black capture detection with permission guidance
- `--uninstall` flag for setup.sh
- Homebrew availability check in setup.sh
- Hotkey conflict detection in setup.sh

### Changed

- Image loading switched from NSImage/TIFF pipeline to direct CGImageSource (faster, lower memory)
- Temp files now use mkstemp for safe creation (no race conditions)
- screencapture path resolved dynamically instead of hardcoded

---

## [1.0.0] - 2026-04-07

### Added

- Screen region selection with OCR text extraction to clipboard
- Apple Vision framework integration (Revision 3, accurate mode)
- Automatic multi-language detection
- Language correction
- Global keyboard shortcut (⌘⇧E) via skhd
- Automated setup script
