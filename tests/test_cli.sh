#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"

cleanup() {
    [ -d "$TMP_DIR" ] || return 0

    if command -v trash &>/dev/null; then
        trash "$TMP_DIR" 2>/dev/null || rm -rf "$TMP_DIR"
    else
        rm -rf "$TMP_DIR"
    fi
}

trap cleanup EXIT

BIN="$TMP_DIR/ocr-capture"

xcrun swiftc -O -o "$BIN" "$ROOT_DIR/ocr-capture.swift" -framework Cocoa -framework Vision

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_contains() {
    local file="$1"
    local expected="$2"

    if ! grep -Fq -- "$expected" "$file"; then
        echo "--- $file ---" >&2
        cat "$file" >&2 || true
        fail "expected to find: $expected"
    fi
}

run_with_timeout() {
    local seconds="$1"
    local stdout_file="$2"
    local stderr_file="$3"
    shift 3

    set +e
    "$@" >"$stdout_file" 2>"$stderr_file" &
    local pid=$!

    (
        sleep "$seconds"
        if kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null
            sleep 1
            kill -KILL "$pid" 2>/dev/null
        fi
    ) &
    local watchdog=$!

    wait "$pid"
    local status=$?
    kill "$watchdog" 2>/dev/null
    wait "$watchdog" 2>/dev/null
    set -e

    if [[ "$status" -eq 143 || "$status" -eq 137 ]]; then
        return 124
    fi

    return "$status"
}

status=0
run_with_timeout 5 "$TMP_DIR/help.out" "$TMP_DIR/help.err" "$BIN" --help || status=$?
[[ "$status" -eq 0 ]] || fail "--help exited with $status"
assert_contains "$TMP_DIR/help.out" "Usage: ocr-capture"
assert_contains "$TMP_DIR/help.out" "--file PATH"
assert_contains "$TMP_DIR/help.out" "--stdout"

status=0
run_with_timeout 5 "$TMP_DIR/file-missing-value.out" "$TMP_DIR/file-missing-value.err" \
    "$BIN" --file --stdout --quiet || status=$?
[[ "$status" -eq 2 ]] || fail "--file without a path exited with $status"
assert_contains "$TMP_DIR/file-missing-value.err" "Missing value for --file"

status=0
run_with_timeout 5 "$TMP_DIR/missing.out" "$TMP_DIR/missing.err" \
    "$BIN" --file "$TMP_DIR/missing.png" --stdout --no-copy --quiet || status=$?
[[ "$status" -ne 0 ]] || fail "missing image unexpectedly succeeded"
[[ "$status" -ne 124 ]] || fail "--file did not complete without interactive capture"
assert_contains "$TMP_DIR/missing.err" "Image file not found"

FIXTURE_TEXT="OCR CAPTURE TEST 4821"
FIXTURE_IMAGE="$TMP_DIR/text.png"
xcrun swift "$ROOT_DIR/tests/make_text_image.swift" "$FIXTURE_TEXT" "$FIXTURE_IMAGE"

status=0
run_with_timeout 15 "$TMP_DIR/ocr.out" "$TMP_DIR/ocr.err" \
    "$BIN" --file "$FIXTURE_IMAGE" --stdout --no-copy --quiet || status=$?
[[ "$status" -eq 0 ]] || {
    cat "$TMP_DIR/ocr.err" >&2 || true
    fail "file OCR exited with $status"
}
assert_contains "$TMP_DIR/ocr.out" "$FIXTURE_TEXT"

echo "CLI tests passed"
