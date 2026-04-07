# Security Policy

## Privacy by Design

- **All processing is local.** Screen capture and OCR run entirely on your Mac.
- **No network calls.** Apple Vision runs in-process, not via any API.
- **No data stored.** Temporary screenshots are deleted immediately after OCR. Nothing is logged.
- **No telemetry, no analytics, no cloud.**

## Permissions

| Permission | Why | Scope |
|------------|-----|-------|
| **Accessibility** | skhd needs this for global keyboard shortcuts | Hotkey daemon only |
| **Screen Recording** | macOS screencapture requires this for region selection | Single frame per invocation |

## Trust Boundaries

| Boundary | Trust Level | Notes |
|----------|-------------|-------|
| ocr-capture binary | Trusted | Compiled from source, runs locally |
| skhd | Third-party, open source | Hotkey daemon, no network access |
| Apple Vision | System framework | On-device, no data leaves the machine |

## Vulnerability Reporting

Report vulnerabilities responsibly:

1. **Do not open a public issue.**
2. Use [GitHub's private vulnerability reporting](https://github.com/gabrimatic/ocr-capture/security/advisories/new) to submit.
3. Include:
   - Steps to reproduce
   - Demonstrated impact
   - Suggested fix (if any)

Expect acknowledgment within 48 hours.

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.x     | Yes       |
