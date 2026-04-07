# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
