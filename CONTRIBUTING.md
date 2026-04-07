# Contributing

Bug reports, improvements, and ideas are welcome.

## Dev Setup

```bash
git clone https://github.com/gabrimatic/ocr-capture.git
cd ocr-capture
swiftc -O -o ocr-capture ocr-capture.swift -framework Cocoa -framework Vision
```

## Project Structure

```
ocr-capture/
├── ocr-capture.swift    # Single-file source
├── setup.sh             # Install script (compile + skhd + hotkey)
├── README.md
├── LICENSE
├── CHANGELOG.md
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
└── SECURITY.md
```

## Testing

Run the binary directly:

```bash
./ocr-capture
```

Select a screen region. Check the clipboard (`pbpaste`) for the extracted text.

## PR Checklist

- Code compiles cleanly with `swiftc -O`
- Binary runs and produces correct clipboard output
- No credentials or personal data in any file
- PR description explains what changed and why

## Reporting Issues

Include:

- macOS version
- Xcode/Swift version (`swift --version`)
- Full terminal output including any error
- Steps to reproduce
- What you expected vs. what happened
