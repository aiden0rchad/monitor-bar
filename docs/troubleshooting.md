---
title: Troubleshooting
description: Start with the connection, then compare the visible result with what the monitor reports.
permalink: /troubleshooting/
---

## I cannot find the app

Monitor Bar lives in the menu bar, without a Dock icon. Open it from Applications and look for the monitor symbol near the clock. If macOS blocks launch, follow the [first-open instructions]({{ '/installation/' | relative_url }}#first-open-security-prompt).

## No external display appears

Check whether the display appears in **System Settings → Displays**. Confirm that it has power and an active video connection, then reconnect it and click Monitor Bar's refresh button. The app lists external screens supplied by macOS; it does not control the built-in Mac screen.

## Brightness or contrast says Not supported

A working picture does not guarantee a working DDC/CI connection. Try these checks in order:

1. If the monitor has a DDC/CI option in its own menu, enable it.
2. Quit other display-control utilities so only one app is sending DDC commands.
3. Try a direct connection instead of a dock or adapter, if possible.
4. Click refresh. Open **Show details** to inspect reply statuses.

Firmware may omit a control, report an invalid range, or fail to answer. Monitor Bar cannot safely turn every readable address into a writable control. Software dimming and resolution selection can still be available when hardware control is unavailable.

## The screen flashes, goes white, or disconnects

Stop using hardware controls and quit Monitor Bar. A successful query or numeric readback does not establish that further commands are safe. Do not run a full DDC scan against a connection that is already resetting: queries also send packets to the monitor.

Version **0.1.1** adds **Gear menu → Pause hardware controls**. This pause is saved across launches and blocks DDC discovery, reads, writes, and retries for **all monitors**. It does not automatically resume after reconnection. **Resume hardware controls** is available for connected monitors other than the Samsung, or for a single, previously verified Samsung G91SD. Mixed Samsung/external-display setups and unverified Samsung units remain blocked. Version 0.1.0 does not have these protections; leave that version closed on an affected setup.

Use the monitor's physical controls for hardware brightness and contrast. Software dimming changes only the displayed image. If the connection or charging still drops with display-control apps closed, investigate the cable, monitor, and Mac connection separately; another brightness test cannot establish the cause safely.

## Brightness is greyed out in the monitor's own menu

Check the monitor's power-saving and picture settings first. On the tested Samsung Odyssey G91SD after a firmware update, turning off **Save Power** restored the physical Brightness control. The HDMI brightness reply also changed from an out-of-range value to the value shown in the OSD. This does not establish that every greyed-out control has the same cause; available controls depend on the monitor and its current mode.

## Samsung G91SD hardware controls

Version **0.1.1** includes Samsung support with individual verification required. Seven slider controls have been checked on one G91SD running firmware 1003.2 over direct HDMI: brightness, contrast, sharpness, red gain, green gain, blue gain, and volume. Picture Mode is enabled separately after verification, as described below.

The app enables this path only for an individually verified monitor saved in local preferences. Another G91SD does not inherit that verification. If the app has no verification record for your unit, hardware controls remain unavailable until the connection and individual controls have been checked. The Samsung must also be the Mac's only external display; the built-in screen can remain active. A Samsung connected alongside another external display disables hardware discovery for both, avoiding the generic EDID scan.

There is no automatic verification or first-use enable button in v0.1.1. Resolution selection can still use the modes macOS provides. To help verify another unit, [open a compatibility report]({{ site.repository_url }}/issues/new/choose) with the monitor model, firmware, Mac, and connection details. Do not copy another unit's verification preferences as a substitute for testing.

For this path, Monitor Bar matches the HDMI service using cached macOS identity information. A refresh makes at most nine reads: the seven slider controls plus PC/AV mode and Picture Mode when enabled. A slider commits when released: the app first checks that the current value still matches its starting value, then sends one write and one readback. A stale starting value is refused. Each operation uses one attempt with the verified packet format, without a capabilities request, alternate-format retries, or a deep scan. A transport failure or connection change pauses hardware commands. **Resume hardware controls** explicitly acknowledges the current HDMI connection; it is available only for a previously verified unit.

The sliders use OSD units: **0–50** for brightness and contrast, **0–20** for sharpness, and **0–100** for volume, following the reported ranges. Custom brightness and contrast calibration is hidden for this path. RGB gains subtract 50 for display when the reported maximum is 100: raw 51 was confirmed as **+1** in the OSD. The full RGB range has not been calibrated, and these gains do not control the separate **Color** slider. Input switching, power commands, and other undocumented Samsung controls remain unavailable.

## Samsung Picture Mode

**Picture Mode** appears above Resolution for a verified unit. It changes the monitor's hardware preset through HDMI. Presets can change brightness, contrast, and color together, so the app refreshes its slider readings after a change.

This control requires separate local verification for the individual monitor and **System → PC/AV Mode → PC** for the Mac's input. The app checks PC/AV mode and the current preset before writing, refuses a stale starting value, then sends one preset write and one readback. It does not switch the input between PC and AV for you.

The mapping below was decoded from the official [Samsung Display Manager app](https://www.samsung.com/latin/support/model/LS49DG910SNXZA/) and compared with the monitor's OSD. Direct HDMI changes between **Eco** and **Original** were physically confirmed on the tested unit. The remaining presets have not each been tested by a hardware write.

| PC Picture Mode | Raw value |
|---|---:|
| Entertain | 0 |
| Graphic | 1 |
| Eco | 2 |
| Game Standard | 3 |
| RPG | 4 |
| RTS | 5 |
| FPS | 6 |
| Sports | 7 |
| Original | 8 |
| Custom | 9 |

Samsung uses VCP **0x2D** for this preset and **0xE4** for PC/AV state. AV mode has a different value mapping and is not enabled here. A reported maximum of 10 does not make this a continuous slider or add another PC preset.

## Samsung G91SD no longer offers 144 Hz

Check the OSD settings for the Mac's input: **System → Input Port Ver. → 2.0↑** and **PIP/PBP → PIP/PBP Mode → Off**. In macOS, keep **5120 × 1440** selected and check the refresh-rate list.

If 144 Hz is missing, disconnect HDMI from the Mac and reconnect it. On the tested setup, this restored the missing modes, and macOS then reported native **5120 × 1440 at 144 Hz**. If needed, turn the monitor off and on normally before reconnecting. Apple's [external-display troubleshooting](https://support.apple.com/en-us/102501) covers redetection and connection checks.

This recovered the HDMI connection on one setup. It does not establish that firmware 1003.2 fixes every refresh-rate or link-training problem, and Monitor Bar cannot select a mode that macOS does not expose.

## A value changes, but the screen does not

DDC readback is the monitor's numeric reply. It is not a measurement of light output, contrast, color, speaker presence, or sound level. Some generic firmware reports success without implementing the expected behavior.

Check the monitor's own menu for modes that lock controls, such as a fixed color preset. Change one control at a time and observe the screen. If brightness or contrast rises and then falls across the slider, inspect [custom calibration]({{ '/controls/' | relative_url }}#optional-brightness-and-contrast-calibration). Do not assume every monitor should use a maximum of 25.

## The slider moves in noticeable steps

The hardware range determines the number of available values. A calibrated range from raw 0 through 25 provides 26 levels, represented by roughly 4% increments on the main slider. Increasing UI precision cannot add hardware levels. Software dimming is separate and can darken the image, but it does not make the backlight control more precise.

## The app could not confirm a change

If the display remains stable, refresh to read the current value again. If it flashes or disconnects, stop hardware control instead. Avoid repeatedly sending competing commands from multiple apps. Monitor Bar serializes its own writes. The verified Samsung path uses one readback attempt and pauses on transport failure; other monitor paths check readback up to three times. A busy connection or unusual firmware can still prevent confirmation.

Input and power changes can deliberately interrupt DDC communication. Use the monitor's physical controls if needed to restore its input or power state.

## The image is blurry or stretched

Open **Resolution** and try an available HiDPI mode. Verify both the workspace dimensions and rendering dimensions. Use a circle or familiar square object to check proportions. Keep a change only when it looks correct; unconfirmed previews request a revert after 15 seconds.

If Monitor Bar shows two native sizes, the panel's EDID and macOS disagree. Read the [HiDPI guide]({{ '/hidpi/' | relative_url }}#when-the-monitor-and-macos-disagree) and compare both available previews. Also check the monitor's physical aspect/scaling menu. Monitor Bar does not override firmware scaling or create missing resolutions.

## Multiple monitors and identity

Hardware control requires a unique match between macOS and the DDC service using vendor, product, and serial identity. If multiple services share that identity, hardware control is withheld to avoid sending a command to the wrong screen. Identical generic displays with missing or duplicate serials can trigger this limitation.

The Samsung path uses cached macOS identity and HDMI connection information rather than requesting EDID over DDC. Its verification record belongs to the individual unit and stays on the Mac. It currently requires the Samsung to be the only external display. With a Samsung and another external display connected, hardware discovery is disabled for both; macOS mode information remains available.

Software controls use the selected macOS display ID. Calibration preferences use the monitor identity, so they cannot distinguish two physical units that report the same identity. Recheck custom ranges after replacing a monitor that reports identical IDs.

## The screen is dim after an adjustment

Under **More controls → Software dimming**, choose **Restore image brightness**, or quit the app to remove its overlay. Hardware brightness and contrast are separate settings and may remain at the values last accepted by the monitor. The app does not restore all hardware controls on exit.

## Collect useful diagnostics

Open **Show details** for EDID information, mode flags, raw feature values, and reply statuses. **Read all 256 control codes** sends GetVCP requests; it may take a few minutes. It does not set control values or issue reset commands, but it still communicates with the monitor and must not be used after flashing or disconnection. For an affected setup, collect existing logs and a CoreGraphics mode-only report instead.

The deep scan is disabled for the Samsung G91SD path. Its report contains cached display information, the seven slider controls, and Picture Mode when enabled and readable. PC/AV state is checked internally to select the correct preset mapping.

Use the gear menu's **Export monitor report…** to save JSON locally. Reports can contain a monitor serial number, registry paths, and display identifiers. Review and redact them before posting anything publicly.

For an [issue report]({{ site.repository_url }}/issues), include:

- App version, Mac chip, and macOS version.
- Monitor model if known, plus the cable, dock, and adapter arrangement.
- The control or mode selected, the visible result, and any app status message.
- Whether the issue persists with other DDC utilities closed and a direct connection.

Share only the relevant redacted fields. A monitor's advertised capabilities cannot establish its retail brand, physical connector inventory, measured HDR performance, or undocumented proprietary features.
