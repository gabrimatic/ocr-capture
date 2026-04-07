#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BINARY="$SCRIPT_DIR/ocr-capture"
SOURCE="$SCRIPT_DIR/ocr-capture.swift"
SKHDRC="$HOME/.skhdrc"
BINDING="cmd + shift - e : $BINARY"

# --- Uninstall ---

if [[ "${1:-}" == "--uninstall" ]]; then
    echo "=== OCR Capture Uninstall ==="
    echo

    # Remove binding from skhdrc
    if [ -f "$SKHDRC" ]; then
        sed -i '' '/ocr-capture/d' "$SKHDRC"
        sed -i '' '/# OCR Capture:/d' "$SKHDRC"
        # Remove trailing blank lines
        sed -i '' -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$SKHDRC"
        echo "  Removed hotkey binding from $SKHDRC"

        # Restart skhd if it has other bindings, otherwise stop it
        if grep -qE '^[^#]' "$SKHDRC" 2>/dev/null; then
            skhd --restart-service 2>/dev/null || true
            echo "  Restarted skhd (other bindings remain)"
        else
            echo "  No other bindings in $SKHDRC"
        fi
    fi

    # Remove compiled binary
    rm -f "$BINARY"
    echo "  Removed binary"

    echo
    echo "Done. Source files are untouched. To fully remove:"
    echo "  rm -rf $SCRIPT_DIR"
    echo "  brew uninstall skhd  # only if nothing else uses it"
    exit 0
fi

# --- Install ---

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
    if ! command -v brew &>/dev/null; then
        echo "Error: Homebrew is required to install skhd."
        echo "  Install Homebrew: https://brew.sh"
        echo "  Then run this script again."
        exit 1
    fi
    echo "Installing skhd..."
    brew install koekeishiya/formulae/skhd
fi

# 4. Add hotkey binding
if [ -f "$SKHDRC" ]; then
    if grep -qF "ocr-capture" "$SKHDRC"; then
        # Update existing binding path in case the project moved
        sed -i '' "s|cmd + shift - e : .*ocr-capture.*|$BINDING|" "$SKHDRC"
        echo "  Updated hotkey binding in $SKHDRC"
    else
        # Check for conflicting cmd+shift+e binding
        if grep -qE '^cmd \+ shift - e' "$SKHDRC"; then
            echo "  Warning: ⌘⇧E is already bound to something else in $SKHDRC"
            echo "  Current binding:"
            grep -E '^cmd \+ shift - e' "$SKHDRC" | sed 's/^/    /'
            echo "  OCR Capture was NOT added. Edit $SKHDRC manually to resolve."
        else
            echo "" >> "$SKHDRC"
            echo "# OCR Capture: select screen region, OCR it, copy text to clipboard" >> "$SKHDRC"
            echo "$BINDING" >> "$SKHDRC"
            echo "  Added hotkey binding to $SKHDRC"
        fi
    fi
else
    echo "# OCR Capture: select screen region, OCR it, copy text to clipboard" > "$SKHDRC"
    echo "$BINDING" >> "$SKHDRC"
    echo "  Created $SKHDRC with hotkey binding"
fi

# 5. Start or restart skhd
if launchctl list 2>/dev/null | grep -q skhd; then
    skhd --restart-service 2>/dev/null || true
    echo "  Restarted skhd"
else
    skhd --start-service 2>/dev/null || true
    echo "  Started skhd"
fi

echo
echo "Done. Press ⌘⇧E to select a screen region and copy the text."
echo
echo "If the shortcut doesn't work, grant skhd Accessibility permission:"
echo "  System Settings > Privacy & Security > Accessibility > enable skhd"
echo "  Then: skhd --restart-service"
