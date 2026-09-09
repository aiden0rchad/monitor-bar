# To do

The next additions focus on controlling the monitor itself over HDMI. These are
research and implementation tasks, not a list of features already supported by
Monitor Bar.

## Samsung G91SD: start here

Target: **LS49DG910SNXZA, firmware 1003.2**. Samsung Display Manager's Mac app
contains command mappings for these settings, but they still need testing on
this monitor. Support in Samsung's multi-model app does not guarantee support
on every Samsung display.

- [ ] **Eye Saver Mode** (`0x0A`): verify the supported levels and refresh any
  brightness or color controls that become unavailable when it is enabled.
- [ ] **Color Tone** (`0x14`): verify the Cool, Standard, Warm 1, Warm 2, and
  Natural presets against the OSD. Use Samsung's mapping rather than generic
  color-temperature assumptions.
- [ ] **Black Equalizer** (`0x2F`): verify the range, direction, and restrictions
  with Eye Saver Mode, PIP/PBP, and AV input timings.
- [ ] **Virtual Aim Point** (`0xED`–`0xEF`): decode and verify the built-in
  crosshair styles, position controls, and position reset. Samsung's app has
  model-specific handling here.

## Mac and Windows on the same monitor

These need connection and recovery checks as well as an OSD confirmation.

- [ ] **Input switching** (`0x60`): map the physical inputs and test what happens
  to control access when switching away from the Mac, including switching back.
- [ ] **PIP/PBP** (`0xE2`, `0xE3`): decode the complete commands for modes,
  sources, layout, size, and position. Check available resolutions and refresh
  rates after each change and restore the normal single-input setup.
- [ ] **Sound source** (`0xE8`): select which computer supplies audio in PIP/PBP.
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

- [ ] Add saved hardware presets and optional per-application Picture Mode
  switching using verified commands.
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
