#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BINARY="$SCRIPT_DIR/ocr-capture"
SOURCE="$SCRIPT_DIR/ocr-capture.swift"
SKHDRC="$HOME/.skhdrc"
# skhd runs bindings via `$SHELL -c`, so the path must be shell-quoted, not
# just double-quoted -- double quotes still allow $(...) / `...` to execute.
BINARY_Q="$(printf '%q' "$BINARY")"
BINDING="cmd + shift - e : $BINARY_Q"

remove_path() {
    local path="$1"
    [ -e "$path" ] || return 0

    if command -v trash &>/dev/null; then
        trash "$path" 2>/dev/null || rm -f "$path"
    else
        rm -f "$path"
    fi
}

# --- Uninstall ---

if [[ "${1:-}" == "--uninstall" ]]; then
    echo "=== OCR Capture Uninstall ==="
    echo

    # Remove binding from skhdrc
    if [ -f "$SKHDRC" ]; then
        # Two passes, both precise about what they touch:
        #  1) our exact marker comment plus the line right after it (how
        #     this script always writes the binding).
        #  2) any remaining non-comment line whose command (text after the
        #     last ':', quotes stripped) is exactly the ocr-capture binary --
        #     covers older/custom-hotkey installs without the marker comment.
        # Never matches on a bare substring, so a binding like
        # `alt - r : open "/Users/me/notes/ocr-capture-ideas.md"` survives.
        tmp_skhdrc="$(mktemp)"
        awk '
            skip_next { skip_next = 0; next }
            /^# OCR Capture: select screen region, OCR it, copy text to clipboard$/ { skip_next = 1; next }
            { print }
        ' "$SKHDRC" | awk -v sq="'" -v dq='"' '
            /^[[:space:]]*#/ { print; next }
            {
                n = length($0); pos = 0
                for (i = 1; i <= n; i++) if (substr($0, i, 1) == ":") pos = i
                if (pos > 0) {
                    cmd = substr($0, pos + 1)
                    gsub(/^[ \t]+/, "", cmd)
                    gsub(/[ \t]+$/, "", cmd)
                    if ((substr(cmd, 1, 1) == sq && substr(cmd, length(cmd), 1) == sq) ||
                        (substr(cmd, 1, 1) == dq && substr(cmd, length(cmd), 1) == dq)) {
                        cmd = substr(cmd, 2, length(cmd) - 2)
                    }
                    if (cmd ~ /(^|\/)ocr-capture$/) next
                }
                print
            }
        ' > "$tmp_skhdrc"
        mv "$tmp_skhdrc" "$SKHDRC"
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
    remove_path "$BINARY"
    echo "  Removed binary"

    echo
    echo "Done. Source files are untouched. To fully remove:"
    echo "  trash \"$SCRIPT_DIR\"  # or remove the folder manually"
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
xcrun swiftc -O -o "$BINARY" "$SOURCE" -framework Cocoa -framework Vision
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
        # Update existing binding path in case the project moved, preserving
        # a user-customized hotkey (everything before the last ':'). Only
        # touches a line whose command is exactly the ocr-capture binary
        # (quotes stripped) -- never a line that merely mentions the string
        # "ocr-capture" elsewhere. The new path is read from the environment
        # (not -v) because awk's -v reprocesses backslash escapes, which
        # would mangle the %q-quoted path.
        tmp_skhdrc="$(mktemp)"
        BINARY_PATH="$BINARY_Q" awk -v sq="'" -v dq='"' '
            /^[[:space:]]*#/ { print; next }
            {
                n = length($0); pos = 0
                for (i = 1; i <= n; i++) if (substr($0, i, 1) == ":") pos = i
                if (pos > 0) {
                    cmd = substr($0, pos + 1)
                    gsub(/^[ \t]+/, "", cmd)
                    gsub(/[ \t]+$/, "", cmd)
                    bare = cmd
                    if ((substr(bare, 1, 1) == sq && substr(bare, length(bare), 1) == sq) ||
                        (substr(bare, 1, 1) == dq && substr(bare, length(bare), 1) == dq)) {
                        bare = substr(bare, 2, length(bare) - 2)
                    }
                    if (bare ~ /(^|\/)ocr-capture$/) {
                        print substr($0, 1, pos) " " ENVIRON["BINARY_PATH"]
                        next
                    }
                }
                print
            }
        ' "$SKHDRC" > "$tmp_skhdrc"

        if cmp -s "$SKHDRC" "$tmp_skhdrc"; then
            rm -f "$tmp_skhdrc"
            echo "  Hotkey binding already up to date"
        else
            mv "$tmp_skhdrc" "$SKHDRC"
            echo "  Updated hotkey binding in $SKHDRC"
        fi
    else
        # Check for conflicting cmd+shift+e binding (tolerate loose whitespace)
        if grep -qE '^cmd[[:space:]]*\+[[:space:]]*shift[[:space:]]*-[[:space:]]*e' "$SKHDRC"; then
            echo "  Warning: ⌘⇧E is already bound to something else in $SKHDRC"
            echo "  Current binding:"
            grep -E '^cmd[[:space:]]*\+[[:space:]]*shift[[:space:]]*-[[:space:]]*e' "$SKHDRC" | sed 's/^/    /'
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
