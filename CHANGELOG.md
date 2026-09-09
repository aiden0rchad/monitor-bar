# Changelog

## 0.1.2 — 2026-09-09

A smaller popup for everyday adjustments, a separate settings window, and
clearer display-mode choices. Samsung Color Tone and Black Equalizer join the
controls checked on the individually verified G91SD.

- Add a separate Monitor Settings window with Picture, Information, and App
  sections. Move sharpness, white balance, calibration, and diagnostics out of
  the quick popup; share the selected display and operation state between views.
- Add individually gated Samsung Eye Saver Mode, Color Tone, and Black Equalizer
  implementations. Color Tone (Warm 1 ↔ Warm 2) and Black Equalizer (5 ↔ 6)
  passed physical checks on the tested unit and were restored. Eye Saver
  writes remain disabled: neither a 150 ms nor a 1.5-second readback reliably
  confirmed the change. A later read after the first attempt reported Low,
  and the user restored Off through the OSD after the final test. Fresh readings
  matched the original settings afterward.
- Check Eye Saver before affected controls, serialize picture presets, and
  refresh related settings after a preset. No additional queries run without
  an advanced-control verification record.
- Split display-mode selection into Resolution, Scaling, and Refresh rate.
  List each workspace size once while preserving different rendering pixel sizes
  and exact reported refresh rates, including an Unspecified option when needed.
- Stage selections and HiDPI shortcuts until **Preview changes** is clicked.
  Keep the existing 15-second Keep/Revert preview before retaining a mode.
- Recheck the current display and mode before applying a preview. Verify display
  identity before Keep or Revert so a reconnected display is not mistaken for
  the original target.
- Stage and sign the app in a temporary directory outside the workspace, avoiding
  signing failures when File Provider restores Finder attributes during a build.

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
