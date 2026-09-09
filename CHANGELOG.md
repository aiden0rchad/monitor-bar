# Changelog

## 0.1.1 — 2026-09-09

Adds guarded HDMI control for an individually verified Samsung G91SD and a
persistent hardware pause. New Samsung units remain disabled until verified;
this release does not include a first-use enable workflow.

- Add an individually verified Samsung Odyssey G91SD HDMI path for brightness,
  contrast, sharpness, RGB gains, and volume. Verification stays in local preferences;
  other units are not enabled automatically.
- Add a native Samsung Picture Mode picker for separately verified units in PC mode.
  Ten PC presets are mapped from the official Display Manager app and the OSD;
  direct HDMI changes between Eco and Original have been physically confirmed.
  Check PC/AV state and the current preset before one write and readback, then
  refresh the sliders because presets can change other picture settings.
- Use cached HDMI identity and a single attempt with the verified DDC packet format
  for Samsung controls, with at most nine reads per refresh and no capabilities
  requests or deep scans. Pause on transport failure or connection changes;
  explicit resume accepts the current
  HDMI connection for a verified unit.
- Commit Samsung slider changes on release, refusing stale starting values before
  sending one write and one readback. Require the Samsung to be the only external
  display; mixed external-display setups skip hardware discovery for both monitors.
- Show Samsung brightness and contrast on their 0–50 OSD scale, and RGB gains with
  a display offset of 50. The RGB mapping is based on small confirmed changes,
  not a full-range calibration.
- Add a persistent pause for all hardware commands, including discovery, queries,
  queued writes, and retries. Software dimming and macOS mode information remain available.
- Allow explicit resume for ordinary external monitors or one previously verified
  Samsung. Unverified Samsung units and mixed Samsung setups remain blocked.
- Clarify that successful DDC replies do not establish safe hardware control.
- Add offline checks that paused discovery and control paths never reach the transport.
- Document the G91SD Save Power setting and recovery of missing 144 Hz modes
  after an HDMI reconnect. No general firmware fix is claimed.

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
