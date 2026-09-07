# Changelog

## 0.1.0 — 2026-09-07

First public release.

- Native menu bar panel for external monitor controls.
- DDC brightness, contrast, volume, and supported color and input settings.
- Independent brightness and contrast range calibration, saved per monitor.
- Absolute slider values with queued writes and bounded readback checks.
- Resolution and HiDPI selection with aspect-ratio details and a 15-second revert timer.
- Software dimming, launch at login, and local diagnostic export.
- Read-only CLI for monitor capabilities and macOS display modes.
- Offline tests, synthetic panel previews, and an Apple Silicon release package.

The release targets macOS 13 and later on Apple Silicon. It is ad-hoc signed,
not notarized. Hardware compatibility is still limited to the displays and
connections that have been tested; numeric DDC replies do not measure image
brightness or contrast.
