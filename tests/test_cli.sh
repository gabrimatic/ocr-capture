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

assert_exact() {
    local file="$1"
    local expected="$2"

    if ! printf '%s\n' "$expected" | cmp -s - "$file"; then
        echo "--- $file (actual) ---" >&2
        cat "$file" >&2 || true
        fail "expected stdout to be exactly: $expected"
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

echo "test: --help"
status=0
run_with_timeout 5 "$TMP_DIR/help.out" "$TMP_DIR/help.err" "$BIN" --help || status=$?
[[ "$status" -eq 0 ]] || fail "--help exited with $status"
assert_contains "$TMP_DIR/help.out" "Usage: ocr-capture"
assert_contains "$TMP_DIR/help.out" "--file PATH"
assert_contains "$TMP_DIR/help.out" "--stdout"

echo "test: unknown option"
status=0
run_with_timeout 5 "$TMP_DIR/unknown.out" "$TMP_DIR/unknown.err" "$BIN" --bogus || status=$?
[[ "$status" -eq 2 ]] || fail "unknown option exited with $status (want 2)"
assert_contains "$TMP_DIR/unknown.err" "Unknown option: --bogus"

echo "test: --file without value"
status=0
run_with_timeout 5 "$TMP_DIR/file-missing-value.out" "$TMP_DIR/file-missing-value.err" \
    "$BIN" --file --stdout --quiet || status=$?
[[ "$status" -eq 2 ]] || fail "--file without a path exited with $status"
assert_contains "$TMP_DIR/file-missing-value.err" "Missing value for --file"

echo "test: --timeout validation"
for bad in 0 -3 abc 99999; do
    status=0
    run_with_timeout 5 "$TMP_DIR/timeout.out" "$TMP_DIR/timeout.err" \
        "$BIN" --file whatever.png --timeout "$bad" --quiet || status=$?
    [[ "$status" -eq 2 ]] || fail "--timeout $bad exited with $status (want 2)"
done
assert_contains "$TMP_DIR/timeout.err" "Timeout must be between"

echo "test: missing image file"
status=0
run_with_timeout 5 "$TMP_DIR/missing.out" "$TMP_DIR/missing.err" \
    "$BIN" --file "$TMP_DIR/missing.png" --stdout --no-copy --quiet || status=$?
[[ "$status" -ne 0 ]] || fail "missing image unexpectedly succeeded"
[[ "$status" -ne 124 ]] || fail "--file did not complete without interactive capture"
assert_contains "$TMP_DIR/missing.err" "Image file not found"

echo "test: directory as image file"
status=0
run_with_timeout 5 "$TMP_DIR/dir.out" "$TMP_DIR/dir.err" \
    "$BIN" --file "$TMP_DIR" --stdout --no-copy --quiet || status=$?
[[ "$status" -eq 1 ]] || fail "directory as --file exited with $status (want 1)"
assert_contains "$TMP_DIR/dir.err" "Image file not found"

echo "test: corrupt image file"
printf 'not a png' > "$TMP_DIR/corrupt.png"
status=0
run_with_timeout 10 "$TMP_DIR/corrupt.out" "$TMP_DIR/corrupt.err" \
    "$BIN" --file "$TMP_DIR/corrupt.png" --stdout --no-copy --quiet || status=$?
[[ "$status" -eq 1 ]] || fail "corrupt image exited with $status (want 1)"
assert_contains "$TMP_DIR/corrupt.err" "Failed to load image"

FIXTURE_TEXT="OCR CAPTURE TEST 4821"
FIXTURE_IMAGE="$TMP_DIR/text.png"
xcrun swift "$ROOT_DIR/tests/make_text_image.swift" "$FIXTURE_TEXT" "$FIXTURE_IMAGE"

# A freshly compiled binary can hit a one-time Vision model compile on newer
# macOS (30-60s), which the app absorbs by falling back to fast recognition
# after --timeout. Keep the app timeout short so the watchdog never wins.
echo "test: file OCR end to end"
status=0
run_with_timeout 40 "$TMP_DIR/ocr.out" "$TMP_DIR/ocr.err" \
    "$BIN" --file "$FIXTURE_IMAGE" --stdout --no-copy --quiet --timeout 8 || status=$?
[[ "$status" -eq 0 ]] || {
    cat "$TMP_DIR/ocr.err" >&2 || true
    fail "file OCR exited with $status"
}
assert_exact "$TMP_DIR/ocr.out" "$FIXTURE_TEXT"

echo "test: reading order for multi-line text"
MULTI_IMAGE="$TMP_DIR/multi.png"
xcrun swift "$ROOT_DIR/tests/make_text_image.swift" 'FIRST ROW 1111\nSECOND ROW 2222\nTHIRD ROW 3333' "$MULTI_IMAGE"
status=0
run_with_timeout 40 "$TMP_DIR/multi.out" "$TMP_DIR/multi.err" \
    "$BIN" --file "$MULTI_IMAGE" --stdout --no-copy --quiet --timeout 8 || status=$?
[[ "$status" -eq 0 ]] || {
    cat "$TMP_DIR/multi.err" >&2 || true
    fail "multi-line OCR exited with $status"
}
assert_exact "$TMP_DIR/multi.out" "FIRST ROW 1111
SECOND ROW 2222
THIRD ROW 3333"

echo "test: blank image reports no text"
BLANK_IMAGE="$TMP_DIR/blank.png"
xcrun swift "$ROOT_DIR/tests/make_text_image.swift" " " "$BLANK_IMAGE"
status=0
run_with_timeout 40 "$TMP_DIR/blank.out" "$TMP_DIR/blank.err" \
    "$BIN" --file "$BLANK_IMAGE" --stdout --no-copy --quiet --timeout 8 || status=$?
[[ "$status" -eq 0 ]] || fail "blank image exited with $status (want 0)"
[[ ! -s "$TMP_DIR/blank.out" ]] || fail "blank image produced stdout output"

# Clipboard copy is the tool's primary output, but the test overwrites the
# pasteboard, so it only runs where that is safe: CI, or when opted in.
if [[ "${CI:-}" == "true" || "${OCR_CAPTURE_TEST_CLIPBOARD:-}" == "1" ]]; then
    echo "test: default clipboard copy"
    status=0
    run_with_timeout 40 "$TMP_DIR/clip.out" "$TMP_DIR/clip.err" \
        "$BIN" --file "$FIXTURE_IMAGE" --quiet --timeout 8 || status=$?
    [[ "$status" -eq 0 ]] || {
        cat "$TMP_DIR/clip.err" >&2 || true
        fail "clipboard run exited with $status"
    }
    [[ "$(pbpaste)" == "$FIXTURE_TEXT" ]] || fail "clipboard content mismatch: $(pbpaste)"
else
    echo "skip: default clipboard copy (set OCR_CAPTURE_TEST_CLIPBOARD=1 to run locally)"
fi

echo "test: accurate timeout falls back to fast recognition"
status=0
run_with_timeout 30 "$TMP_DIR/fallback.out" "$TMP_DIR/fallback.err" \
    env OCR_CAPTURE_TEST_STALL_ACCURATE_MS=30000 \
    "$BIN" --file "$FIXTURE_IMAGE" --stdout --no-copy --quiet --timeout 1 || status=$?
[[ "$status" -eq 0 ]] || {
    cat "$TMP_DIR/fallback.err" >&2 || true
    fail "fallback run exited with $status"
}
assert_exact "$TMP_DIR/fallback.out" "$FIXTURE_TEXT"
assert_contains "$TMP_DIR/fallback.err" "fast recognition"

echo "test: hard timeout when recognition never completes"
status=0
run_with_timeout 30 "$TMP_DIR/hard-timeout.out" "$TMP_DIR/hard-timeout.err" \
    env OCR_CAPTURE_TEST_STALL_MS=30000 \
    "$BIN" --file "$FIXTURE_IMAGE" --stdout --no-copy --quiet --timeout 1 || status=$?
[[ "$status" -eq 1 ]] || fail "hard timeout exited with $status (want 1)"
assert_contains "$TMP_DIR/hard-timeout.err" "OCR timed out after 1 second"
[[ ! -s "$TMP_DIR/hard-timeout.out" ]] || fail "hard timeout produced stdout output"

echo "CLI tests passed"
