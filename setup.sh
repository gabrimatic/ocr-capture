#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BINARY="$SCRIPT_DIR/ocr-capture"
SOURCE="$SCRIPT_DIR/ocr-capture.swift"
SKHDRC="$HOME/.skhdrc"
BINDING="cmd + shift - e : $BINARY"

echo "=== OCR Capture Setup ==="
echo

# 1. Check for Xcode Command Line Tools
if ! xcode-select -p &>/dev/null; then
    echo "Xcode Command Line Tools not found. Installing..."
    xcode-select --install
    echo "Run this script again after installation completes."
    exit 1
fi

# 2. Compile
echo "Compiling ocr-capture..."
swiftc -O -o "$BINARY" "$SOURCE" -framework Cocoa -framework Vision
echo "  Built: $BINARY"

# 3. Install skhd if needed
if ! command -v skhd &>/dev/null; then
    echo "Installing skhd..."
    brew install koekeishiya/formulae/skhd
fi

# 4. Add hotkey binding
if [ -f "$SKHDRC" ]; then
    if grep -qF "ocr-capture" "$SKHDRC"; then
        echo "  Hotkey already configured in $SKHDRC"
    else
        echo "" >> "$SKHDRC"
        echo "# OCR Capture: select screen region, OCR it, copy text to clipboard" >> "$SKHDRC"
        echo "$BINDING" >> "$SKHDRC"
        echo "  Added hotkey binding to $SKHDRC"
    fi
else
    echo "# OCR Capture: select screen region, OCR it, copy text to clipboard" > "$SKHDRC"
    echo "$BINDING" >> "$SKHDRC"
    echo "  Created $SKHDRC with hotkey binding"
fi

# 5. Start or restart skhd
if launchctl list | grep -q skhd; then
    skhd --restart-service
    echo "  Restarted skhd"
else
    skhd --start-service
    echo "  Started skhd"
fi

echo
echo "Done. Press ⌘⇧E to select a screen region and copy the text."
echo
echo "If the shortcut doesn't work, grant skhd Accessibility permission:"
echo "  System Settings > Privacy & Security > Accessibility > enable skhd"
echo "  Then: skhd --restart-service"
