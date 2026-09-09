# To do

The next additions focus on controlling the monitor itself over HDMI. Checked
items are included in v0.1.3; unchecked items need further research or verification.

Version 0.1.3 adds saved hardware presets for verified Samsung controls and
offline-tested input/PIP/PBP/audio codecs. Hardware transition testing remains
open below.

## Samsung G91SD: start here

Target: **LS49DG910SNXZA, firmware 1003.2**. Samsung Display Manager's Mac app
contains command mappings for these settings. Testing status is recorded below. Support in Samsung's multi-model app does not guarantee support
on every Samsung display.

- [x] Add a separate **Monitor Settings** window for picture adjustments,
  monitor information, and app preferences. Keep everyday controls in the popup.
  Released in v0.1.2.

- [x] **Color Tone** (`0x14`): add the five OSD choices in the settings window.
  The v0.1.2 check covered Warm 1 → Warm 2 and restoration. The v0.1.3
  checks confirmed Cool, Standard, and Natural, restoring Warm 1 after each.
  All five choices are physically confirmed on this tested setup; other reported
  picture values stayed unchanged. Other units, firmware, and input modes are
  outside that verification.
- [x] **Black Equalizer** (`0x2F`): add a hardware slider using the reported
  0–10 range. OSD values 0, 5, 6, and 10 have been physically confirmed with a
  stable image and other picture readings unchanged immediately after each
  change. Black Equalizer was restored to 5 after the endpoint checks.
  Intermediate levels and the direction of the visual change remain unverified.
- [ ] **Eye Saver Mode** (`0x0A`): the read path matches the OSD, and its
  Off/Low/High choices are mapped. Off → Low tests failed to confirm at both
  150 ms and 1.5 seconds. The app paused without retrying. A later read after
  the first attempt reported Low. The user restored Off through the OSD after
  the final test, and fresh readings matched the originals. Leave writes disabled until settling time and physical behavior
  are verified; this is not a proven unsupported feature.
- [ ] Extend verification beyond the successful tests: Black Equalizer
  intermediate levels and visual direction, and Color Tone behavior with Eye Saver,
  PIP/PBP, and AV timings. Do not treat the initial tests as complete range or
  connection-mode coverage.

- [ ] **Virtual Aim Point** (`0xED`–`0xEF`): decode and verify the built-in
  crosshair styles, position controls, and position reset. Samsung's app has
  model-specific handling here.

## Mac and Windows on the same monitor

These need connection and recovery checks as well as an OSD confirmation.

- [ ] **Input switching** (`0x60`): map the physical inputs and test what happens
  to control access when switching away from the Mac, including switching back.
  One fresh read returned HDMI 1 (`17`), matching SDM's map on the current
  connection. The cause of the earlier different value is unknown. No switch
  command has been tested.
- [ ] **PIP/PBP** (`0xE2`, `0xE3`): verify the decoded status, mode, layout,
  size, position, and source commands against the physical OSD. Check available
  resolutions and refresh rates after each change and restore the normal
  single-input setup. One `0xE2` read reported PIP and PBP support with the mode
  off. One `0xE3` read returned **invalid reply**, causing a persistent pause;
  that is not a valid unsupported-feature response. No PIP/PBP writes were sent.
- [ ] **Sound source** (`0xE8`): verify the decoded main/sub audio selection
  with both sources connected and producing distinguishable sound. No mixing
  is documented. Audio was not queried after the `0xE3` failure. Input/PIP/audio
  transition testing needs a second connected, active source.
- [ ] **Adaptive-Sync** (`0xF2`): decode its type/status handling, verify the
  toggle, and check link stability and interaction with PIP/PBP.

## Further hardware research

- [ ] Verify **PC/AV mode** (`0xE4`), **OSD language** (`0xCC`), and
  **white-balance reset** (`0xE0`) before exposing them as controls. PC/AV mode
  changes the Picture Mode value mapping.
- [ ] Find reliable remote mappings for **Color/saturation, Tint, Gamma,
  Shadow Detail, Contrast Enhancer, HDR Tone Mapping, Color Space, Peak
  Brightness, Save Energy, VRR Control, and aspect ratio**. These OSD settings
  are not proven HDMI controls. Standard saturation `0x8A` returned unsupported
  on the tested unit; the separate Color slider is not RGB white balance.
- [ ] Investigate whether **panel-care operations** have a documented remote
  interface. Keep this to research until the command and its effects are known.

## Once the controls are verified

- [x] Add saved hardware presets for verified Samsung controls. The v0.1.3
  implementation saves fresh readings, applies Picture Mode and Color Tone
  before numeric values, and checks the result. It requires verified Picture
  Mode and PIP/PBP readers with PIP/PBP Off. It excludes Eye Saver, input, and
  power and does not automatically roll back a partial failure. Saving, applying
  an unchanged preset, and a Black Equalizer 5 → 6 → 5 round trip passed on the
  tested unit, with physical confirmation and other readings unchanged.
- [ ] Add optional per-application Picture Mode switching using verified commands.
- [ ] For each new control, save fresh original values, make one bounded
  change, compare readback with the physical OSD, and restore the originals.
  Check affected settings too. Keep connection checks, command limits, and
  persistent pause behavior; add offline validation before enabling the UI.

## Scope

The G91SD does not inherit every feature shown in Samsung's shared software.
The family manual reserves rear lighting/CoreSync, response-time adjustment,
Low Input Lag, USB-source/KVM switching, Local Dimming, Clear Motion, and
Best/Minimum Brightness for other models.

Window tiling and Dock/menu-bar dimming are outside this hardware-control work.
Samsung's documented firmware-update workflow also uses USB data, not HDMI alone.

## References

Research checked September 9, 2026:

- [Samsung Display Manager feature guide](https://www.samsung.com/hk_en/support/displays/what-is-samsung-display-manager/)
- [G91SD model downloads](https://www.samsung.com/latin/support/model/LS49DG910SNXZA/)
- [Samsung G91SD family manual](https://downloadcenter.samsung.com/content/UM/202505/20250511042212001/BN81-26440B-02_WUG_G95NC%20G93SC%20G93SD%20G91SD_NA%20LATIN_ENG_250509.0.pdf)

The command candidates also come from offline inspection of Samsung Display
Manager for macOS 1.0.0. Its presence in the app is evidence for investigation,
not a reason to send an unverified command to a monitor.
