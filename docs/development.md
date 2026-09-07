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

The build creates an ad-hoc-signed app and a command-line probe. It does not notarize the app or register a Developer ID signature. Public binaries target arm64 and macOS 13; runtime testing so far is limited to an M3 Max Mac on macOS 26 with a generic USB-C panel.

## Source layout

| File | Responsibility |
|---|---|
| `Sources/MonitorBarApp.swift` | Menu bar scene, control popover, calibration interface, mode preview, and diagnostics |
| `Sources/MonitorStore.swift` | Observable app state, saved ranges, queued writes, readback handling, dimming, and mode changes |
| `Sources/AbsoluteSlider.swift` | Native AppKit slider bridge with absolute-value actions and keyboard behavior |
| `Sources/Hardware.swift` | Display discovery, unique DDC matching, feature probing, capability parsing, and write verification |
| `Sources/DDCBridge.c` and `.h` | IOAVService access, DDC packet framing, checksums, and response statuses |
| `Sources/Models.swift` | Display and control models, HiDPI detection, safe mode filtering, and writable-control lists |
| `Sources/EDID.swift` | EDID parsing, preferred timings, extension information, and checksum validation |

## Run the checks

```sh
./scripts/test.sh
```

The automated suite checks DDC response framing, checksums and statuses; EDID parsing; capability parsing; display-mode filtering; writable-control restrictions; absolute slider actions; custom range mapping; rapid changes; and delayed or failed readbacks. These tests do not change hardware settings.

Hardware integration checks are separate and opt-in. They require an explicitly selected display and a saved custom range. Numeric readback verifies command mapping, not measured luminance or contrast.

## Inspect a connected display

Build first, then quit Monitor Bar and any other DDC utility before a full probe:

```sh
mkdir -p Diagnostics
.build/monitor-probe --full > Diagnostics/monitor-full.json
```

This reads all 256 GetVCP feature addresses without setting controls. The default probe reads advertised and common controls. A mode-only report uses CoreGraphics without DDC traffic and can run while the app is open:

```sh
.build/monitor-probe --modes > Diagnostics/display-modes.json
```

Keep reports local unless you have reviewed and redacted identifying data. Generated diagnostics and build artifacts are excluded from version control.

## Opt-in hardware range check

`Tests/DDCControlRange.swift` exercises one real brightness or contrast control through the native slider action and app write queue. It sends targets of 0, 25, 50, 75, and 100% within the saved custom range, verifies reported raw values, and attempts to restore the starting raw value. **This test changes the selected monitor's hardware settings.**

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

This documentation and release downloads are hosted by GitHub, whose services have their own privacy practices. The site adds no tracking scripts or third-party assets.

## Implementation boundaries

The hardware bridge dynamically loads undocumented `IOAVService` APIs on Apple Silicon. Apple can change those APIs, and a successful build does not guarantee DDC support on a particular Mac, monitor, or adapter. The app is not sandboxed and is not distributed through the Mac App Store.

CoreGraphics provides the reported modes and display configuration. The app does not install system EDID overrides, custom timings, a privileged helper, or a driver. Input/power commands and resolution changes have different failure modes; their safeguards do not establish support for every firmware implementation.

## License and contributions

Monitor Bar is free software under the [MIT license]({{ site.repository_url }}/blob/main/LICENSE). Source and release history are available in the [repository]({{ site.repository_url }}). Include a focused description and relevant validation when opening a pull request; see the [troubleshooting guide]({{ '/troubleshooting/' | relative_url }}#collect-useful-diagnostics) for useful issue details.

The interface takes visual inspiration from [WhatCable](https://github.com/darrylmorley/whatcable). No WhatCable code or assets are included in the app.
