---
title: Development & privacy
description: A native app with a small hardware bridge, local preferences, and inspectable source.
permalink: /development/
---

## Build from source

Use an Apple Silicon Mac with macOS 13 or later and Apple's Command Line Tools. The app uses SwiftUI, AppKit, CoreGraphics, IOKit, and ServiceManagement, plus a small C bridge. There are no third-party app packages, package-manager install steps, or background server.

```sh
git clone https://github.com/aiden0rchad/monitor-bar.git
cd monitor-bar
./scripts/build.sh
open "build/Monitor Bar.app"
```

The build creates an ad-hoc-signed app and a command-line probe. It does not notarize the app or register a Developer ID signature. Public binaries target arm64 and macOS 13; runtime testing so far is limited to an M3 Max Mac on macOS 26 with a generic USB-C panel and a Samsung Odyssey G91SD over HDMI.

## Source layout

The source includes unreleased saved-preset and input-protocol work described
below. The latest published binary remains v0.1.2.

| File | Responsibility |
|---|---|
| `Sources/MonitorBarApp.swift` | Menu bar scene, quick controls, staged display choices, mode preview, and settings-window lifecycle |
| `Sources/MonitorSettingsView.swift` | Picture controls, calibration, monitor information, diagnostics, and app preferences |
| `Sources/MonitorStore.swift` | Observable app state, saved ranges, queued writes, readback handling, dimming, and mode changes |
| `Sources/AbsoluteSlider.swift` | Native AppKit slider bridge with absolute-value actions and keyboard behavior |
| `Sources/Hardware.swift` | Display discovery, unique DDC matching, feature probing, capability parsing, and write verification |
| `Sources/DDCBridge.c` and `.h` | IOAVService access, DDC packet framing, checksums, and response statuses |
| `Sources/Models.swift` | Display and control models, HiDPI detection, safe mode filtering, and writable-control lists |
| `Sources/EDID.swift` | EDID parsing, preferred timings, extension information, and checksum validation |
| `Sources/SamsungInputState.swift` | Pure, strict input/PIP/PBP/audio codecs; no hardware traffic or enablement |

## Unreleased Samsung work

Saved hardware presets are limited to the selected, individually verified
Samsung unit. Saving takes fresh readings. Applying orders Picture Mode and
Color Tone before numeric controls, then verifies the final values. The same
per-unit, per-control, connection, and unavailable-state guards still apply.
Failure stops the operation without an automatic rollback; a partially applied
preset may leave accepted settings changed. Eye Saver, input, and power values
are excluded.

Presets also require the separate `samsungPIPReadEnabled` verification record
for that monitor. A preset snapshot adds one `0xE2` read before the existing
picture scan (at most 13 reads). It accepts the observed type `0` and maximum
`127`, then decodes the packed current value; `0x3500` is valid even though
it exceeds the maximum field. PIP/PBP must be Off. Enabled units also check
this state before each write. Normal refresh stays at its existing limit.
No source-assignment or audio queries are dependencies of picture controls.

The input codecs cover `0x60`, packed PIP/PBP status `0xE2`, two-screen source
assignments `0xE3`, and main/sub audio `0xE8`. They reject unknown inputs,
reserved fields, unsupported three-source formats, and inconsistent active
states. DDC type and maximum are not assumed to define a continuous range.
These are static mappings recovered from Samsung Display Manager and tested
offline, not verified G91SD write controls. A fresh 12-query baseline matched
the original picture settings. Three separate, single-attempt reads followed:

| Code | Result | Interpretation |
|---|---|---|
| `0xE2` | `ok`, current `0x3500`, maximum `127`, type `0` | PIP/PBP supported, off; three two-screen PBP layouts and two PIP sizes reported |
| `0x60` | `ok`, current `17`, maximum `18`, type `0` | HDMI 1 on this connection; the cause of the earlier different reply is unknown |
| `0xE3` | `invalid reply`, I/O return `0` | Not a valid source value or unsupported-feature response |

The invalid reply triggered a persistent pause before `0xE8` or any Set request.
Passive connection identity, 144 Hz mode, and AC-power state remained unchanged;
the user confirmed physical stability and authorized resuming verified picture controls. Input/PIP/audio transition
verification needs a second active source and recovery when the Mac loses DDC
access. No input, PIP/PBP, or audio-source writes have been tested.

## Run the checks

```sh
./scripts/test.sh
```

The automated suite checks DDC response framing, checksums and statuses; EDID parsing; capability parsing; display-mode grouping and filtering; writable-control restrictions; absolute slider actions; custom range mapping; rapid changes; and delayed or failed readbacks. Samsung tests also cover connection identity changes, strict per-unit opt-ins, PC/AV and Eye Saver prerequisites, categorical choices, and request limits. These tests do not change hardware settings.

Hardware integration checks are separate and opt-in. They require an explicitly selected display and a saved custom range. Numeric readback verifies command mapping, not measured luminance or contrast.

## Inspect a connected display

Use a DDC probe only on a stable connection. If hardware commands have caused flashing or disconnection, keep hardware control paused and use the mode-only report below. GetVCP queries send I2C request packets; they are not passive inspection.

Build first, then quit Monitor Bar and any other DDC utility before a full probe:

```sh
mkdir -p Diagnostics
.build/monitor-probe --full > Diagnostics/monitor-full.json
```

For other monitors, this reads all 256 GetVCP feature addresses without setting controls; the default probe reads advertised and common controls. The Samsung G91SD always uses the bounded path below, including with `--full`. A mode-only report uses CoreGraphics without DDC traffic and can run while the app is open:

```sh
.build/monitor-probe --modes > Diagnostics/display-modes.json
```

For a controlled single request, `--read-once DISPLAY_ID REGISTRY_ID HEX_CODE PROFILE` requires exactly one external display, an explicitly matched CoreGraphics display ID and external IORegistry service ID, a hexadecimal VCP code, and a profile from 0–3. IDs and profile are decimal. Match the service using cached IORegistry data first. This path does not enumerate DDC services or fetch EDID/capabilities; it sends at most one GetVCP request and reads at most one reply, with no retries. Profile 0 uses the standard request checksum and reply offset 0. The command honors the persistent hardware pause and never clears it. A returned `ok` validates the protocol reply; it does not establish that a value is within range or that writing it is safe. Invalid or conflicting command-line options exit without starting a probe.

`--step-brightness DISPLAY_ID REGISTRY_ID EXPECTED NEW` performs a guarded hardware test using decimal raw brightness values exactly one step apart. It first reads brightness once with profile 0. It sends one SetVCP only if the reply is valid, continuous, within range, matches `EXPECTED`, and allows `NEW`. It never retries or restores a value automatically. `writeStatus: "ok"` only means the transport accepted the write; `writeConfirmed` remains false. A separate readback and physical OSD check are needed to confirm the result. The same display-selection and persistent-pause rules apply. Close other monitor-control apps and supervise the connection before using this command.

`--set-brightness DISPLAY_ID REGISTRY_ID EXPECTED NEW` uses the same guarded read and single write, but allows a requested target anywhere within the monitor's reported range. Values are raw OSD units, not percentages.

`--step-contrast DISPLAY_ID REGISTRY_ID EXPECTED NEW` applies the adjacent-value test to contrast (VCP `0x12`, profile 0), with the same preconditions and persistent pause as `--step-brightness`. It sends one GetVCP request and at most one SetVCP, with no retries. Values are raw OSD units. Confirm each change separately before another test.

`--step-control DISPLAY_ID REGISTRY_ID HEX_CODE EXPECTED NEW` uses those same guards for hexadecimal codes `10`, `12`, `16`, `18`, `1A`, `62`, `87`, or `8A`. Values are decimal raw units exactly one step apart. It checks the selected control with profile 0 and requires a valid continuous range; inclusion in the allowlist does not establish monitor support. Save each original value before testing, and stop the batch on any failure or connection change.

Keep reports local unless you have reviewed and redacted identifying data. Generated diagnostics and build artifacts are excluded from version control.

## Samsung HDMI hardware path

Samsung G91SD controls require a verified per-unit opt-in, the Samsung as the only external display, and a uniquely matching cached HDMI connection. Discovery reads cached EDID and registry properties, without requesting EDID or capabilities from the monitor. The app checks the proxy, HDMI port, connection counter, UUID, and EDID around every I2C operation. A changed connection or failed confirmation persists a global hardware pause. Explicit resume acknowledges a new connection before rescanning.

Without additional control opt-ins, the base scan reads brightness, contrast, sharpness, RGB, and volume: seven profile-0 GetVCP exchanges without retries. Ordinary writes pre-read the control, reject stale values, send at most one SetVCP, and verify once.

Picture Mode has a separate strict boolean opt-in, `samsungPictureModeEnabled.<display.identity>`, in addition to the base hardware opt-in. It defaults off. With this opt-in alone, a scan reads PC/AV (`0xE4`) after the seven controls, then Picture Mode (`0x2D`) only for a valid PC response: at most nine reads. An AV or unsupported response disables Picture Mode while retaining the base controls; transport or malformed-response failures pause all hardware controls.

Samsung Display Manager's PC Picture Mode map is: 0 Entertain, 1 Graphic, 2 Eco, 3 Game Standard, 4 RPG, 5 RTS, 6 FPS, 7 Sports, 8 Original, and 9 Custom. The mode is categorical. A reported maximum of 10 does not make PC value 10 valid. The app requires type 0, maximum 10, and a current value in this PC map. The PC/AV maximum is not interpreted as a continuous range.

A Picture Mode write checks PC input again, reads the current mode and rejects stale state, sends at most one `0x2D` SetVCP, then reads `0x2D` once to confirm. No automatic retry or restoration occurs. The feature remains gated per unit; the map recovered from Samsung's app does not establish that every mode is available in every monitor configuration. Picture presets may also change brightness, contrast, and color settings.

Color Tone (`0x14`) and Black Equalizer (`0x2F`) have separate strict per-unit opt-ins keyed as `samsungAdvancedEnabled.<display.identity>.<HEX_CODE>`. Both default off. Color Tone uses Samsung's categorical map: 0 Cool, 1 Standard, 2 Warm 1, 3 Warm 2, 4 Natural. It is not the generic MCCS color-temperature map. Black Equalizer uses the unit's validated 0–10 raw range. Physical verification covered Warm 1 ↔ Warm 2 and Black Equalizer 5 ↔ 6, followed by restoration; it did not cover every setting.

When an additional control is enabled, the scan first reads Eye Saver (`0x0A`). If its state is active or unusable, it skips affected brightness, RGB, Picture Mode, Color Tone, and Black Equalizer reads and marks those controls unavailable. It does not apply that restriction to contrast, sharpness, or volume. The maximum is 12 reads with all verified controls enabled: the seven base features, PC/AV, Picture Mode, Eye Saver, Color Tone, and Black Equalizer. Eye Saver's prerequisite reply stays in the snapshot even when its write control is disabled.

Affected writes recheck Eye Saver before the current target value. Presets run serially and refresh related settings before another write is accepted. An explicit unsupported reply or a valid but unusable value disables the feature; transport, framing, and connection failures pause hardware commands. A numeric readback still needs a physical check when verifying a new control.

Eye Saver writes remain unverified and disabled. Off → Low was not confirmed by either a 150 ms or a 1.5-second readback interval. A later read after the first attempt reported Low without another Set. The user restored Off through the OSD after the final test, and fresh readings matched the original settings. These results do not establish a reliable settling time or justify retrying automatically.

## Opt-in hardware range check

`Tests/DDCControlRange.swift` exercises one real brightness or contrast control through the native slider action and app write queue. It sends targets of 0, 25, 50, 75, and 100% within the saved custom range, verifies reported raw values, and attempts to restore the starting raw value. **This test changes the selected monitor's hardware settings.**

This range-exercise diagnostic rejects Samsung G91SD monitors; it does not use their guarded production control path.

First save a suitable custom range in Monitor Bar, then quit the app and other DDC utilities. Build the probe and test executable:

```sh
./scripts/build.sh
swiftc -target arm64-apple-macos13.0 -swift-version 5 \
    -import-objc-header Sources/DDCBridge.h \
    Sources/Models.swift Sources/EDID.swift Sources/Hardware.swift \
    Sources/MonitorStore.swift Sources/AbsoluteSlider.swift \
    Tests/DDCControlRange.swift .build/DDCBridge.o \
    -framework IOKit -framework AppKit -framework ServiceManagement \
    -framework UniformTypeIdentifiers -o .build/ddc-control-range
.build/monitor-probe --modes
```

Find the selected display's top-level decimal `id` in that report, not an individual mode's `id`. Enter it when prompted below, then run the brightness check:

```sh
printf 'Decimal display ID from the report: '
read -r monitor_display_id
.build/ddc-control-range --display-id "$monitor_display_id" --brightness --exercise
```

To check contrast instead, use the same explicit display ID with `--contrast`:

```sh
.build/ddc-control-range --display-id "$monitor_display_id" --contrast --exercise
```

The selected control must have its own saved custom range and a unique DDC connection. With maximum 25, the requested percentages map to raw values 0, 6, 13, 19, and 25. Read the result of the final `RESTORE` check and observe the physical screen. A disconnection or interrupted process can prevent restoration. Passing confirms reported values and mapping, not a measured physical response or compatibility with other monitors.

## Render the interface locally

The default preview uses the synthetic fixture in `Tests/Fixtures/demo-monitor.json`:

```sh
./scripts/preview.sh
```

It writes light and dark images to `.build/preview/` without taking a screen capture or sending hardware commands. These renders check layout, not live menu bar interaction or physical monitor behavior. The documentation's example images use this demo data.

The display controls can also be rendered with a staged selection.
Pass a selectable mode ID from the fixture to show the **Preview changes** footer:

```sh
./scripts/preview.sh Tests/Fixtures/samsung-monitor.json 2
```

This only changes the offline preview; it does not apply a display mode.

Render the separate settings window with synthetic advanced-control values:

```sh
./scripts/preview.sh Tests/Fixtures/samsung-advanced-monitor.json settings
```

This writes `monitor-settings-light.png` and `monitor-settings-dark.png`. The
fixture enables controls only in an isolated preview preference suite; it
does not enable or change a connected monitor. Use `demo-monitor.json` to check
the generic monitor's calibration and software-dimming layout.

To preview your own monitor, close other DDC utilities and create a report first:

```sh
.build/monitor-probe > Diagnostics/ui-monitor.json
./scripts/preview.sh Diagnostics/ui-monitor.json
```

The probe reads hardware. The preview script then renders from the saved report. Review images for identifying information before sharing them.

## Documentation site

This site lives in `docs/` and uses GitHub Pages' built-in Jekyll support with a custom layout and stylesheet. It has no external theme, remote font, JavaScript, or analytics. The publishing source is **main → /docs**, with the project base URL `/monitor-bar`.

If Jekyll is already installed in your development environment, run these commands from the repository root:

```sh
jekyll build --source docs --config docs/_config.yml --destination .build/docs
jekyll serve --source docs --config docs/_config.yml --destination .build/docs --baseurl /monitor-bar
```

Then open [the local documentation preview](http://127.0.0.1:4000/monitor-bar/). A local Jekyll installation is optional for building the app and is not included in this repository. For Ruby and Jekyll setup, use the [official Jekyll installation guide](https://jekyllrb.com/docs/installation/) and [GitHub's local preview guide](https://docs.github.com/en/pages/setting-up-a-github-pages-site-with-jekyll/testing-your-github-pages-site-locally-with-jekyll).

Internal documentation links and assets use Jekyll's `relative_url` filter so they work under the project base URL.

## Privacy

Monitor Bar has no account system, telemetry, analytics, network requests, background web service, or automatic update checks. Display discovery and control happen on the Mac. The app does not need administrator access, Accessibility permission, or Screen Recording permission for its implemented controls.

Custom brightness and contrast limits are stored in local preferences, keyed by monitor vendor/product/serial identity. Launch-at-login registration uses macOS ServiceManagement. A normal refresh does not upload a report or automatically export one.

Exported JSON may include monitor serials, display IDs, registry paths, EDID data, DDC capabilities, and raw settings. You choose the save location. The app does not transmit that file; sharing it is a separate action you control.

This documentation and release downloads are hosted by GitHub, whose services have their own privacy practices. The site adds no tracking scripts. Its support button loads an image from Buy Me a Coffee and links to that service.

## Implementation boundaries

The hardware bridge dynamically loads undocumented `IOAVService` APIs on Apple Silicon. Apple can change those APIs, and a successful build does not guarantee DDC support on a particular Mac, monitor, or adapter. The app is not sandboxed and is not distributed through the Mac App Store.

CoreGraphics provides the reported modes and display configuration. The app does not install system EDID overrides, custom timings, a privileged helper, or a driver. Input/power commands and resolution changes have different failure modes; their safeguards do not establish support for every firmware implementation.

## License and contributions

Monitor Bar is free software under the [MIT license]({{ site.repository_url }}/blob/main/LICENSE). Source and release history are available in the [repository]({{ site.repository_url }}). Include a focused description and relevant validation when opening a pull request; see the [troubleshooting guide]({{ '/troubleshooting/' | relative_url }}#collect-useful-diagnostics) for useful issue details.

The interface takes visual inspiration from [WhatCable](https://github.com/darrylmorley/whatcable). No WhatCable code or assets are included in the app.
