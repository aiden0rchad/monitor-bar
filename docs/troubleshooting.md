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

## A value changes, but the screen does not

DDC readback is the monitor's numeric reply. It is not a measurement of light output, contrast, color, speaker presence, or sound level. Some generic firmware reports success without implementing the expected behavior.

Check the monitor's own menu for modes that lock controls, such as a fixed color preset. Change one control at a time and observe the screen. If brightness or contrast rises and then falls across the slider, inspect [custom calibration]({{ '/controls/' | relative_url }}#optional-brightness-and-contrast-calibration). Do not assume every monitor should use a maximum of 25.

## The slider moves in noticeable steps

The hardware range determines the number of available values. A calibrated range from raw 0 through 25 provides 26 levels, represented by roughly 4% increments on the main slider. Increasing UI precision cannot add hardware levels. Software dimming is separate and can darken the image, but it does not make the backlight control more precise.

## The app could not confirm a change

Refresh to read the current value again. Avoid repeatedly sending competing commands from multiple apps. Monitor Bar serializes its own writes and checks readback up to three times, but a busy connection or unusual firmware can still prevent confirmation.

Input and power changes can deliberately interrupt DDC communication. Use the monitor's physical controls if needed to restore its input or power state.

## The image is blurry or stretched

Open **Resolution** and try an available HiDPI mode. Verify both the workspace dimensions and rendering dimensions. Use a circle or familiar square object to check proportions. Keep a change only when it looks correct; unconfirmed previews request a revert after 15 seconds.

If Monitor Bar shows two native sizes, the panel's EDID and macOS disagree. Read the [HiDPI guide]({{ '/hidpi/' | relative_url }}#when-the-monitor-and-macos-disagree) and compare both available previews. Also check the monitor's physical aspect/scaling menu. Monitor Bar does not override firmware scaling or create missing resolutions.

## Multiple monitors and identity

Hardware control requires a unique match between macOS and the DDC service using vendor, product, and serial identity. If multiple services share that identity, hardware control is withheld to avoid sending a command to the wrong screen. Identical generic displays with missing or duplicate serials can trigger this limitation.

Software controls use the selected macOS display ID. Calibration preferences use the monitor identity, so they cannot distinguish two physical units that report the same identity. Recheck custom ranges after replacing a monitor that reports identical IDs.

## The screen is dim after an adjustment

Under **More controls → Software dimming**, choose **Restore image brightness**, or quit the app to remove its overlay. Hardware brightness and contrast are separate settings and may remain at the values last accepted by the monitor. The app does not restore all hardware controls on exit.

## Collect useful diagnostics

Open **Show details** for EDID information, mode flags, raw feature values, and reply statuses. **Read all 256 control codes** performs a read-only GetVCP scan; it may take a few minutes. It does not enable additional unsupported features or issue reset commands.

Use the gear menu's **Export monitor report…** to save JSON locally. Reports can contain a monitor serial number, registry paths, and display identifiers. Review and redact them before posting anything publicly.

For an [issue report]({{ site.repository_url }}/issues), include:

- App version, Mac chip, and macOS version.
- Monitor model if known, plus the cable, dock, and adapter arrangement.
- The control or mode selected, the visible result, and any app status message.
- Whether the issue persists with other DDC utilities closed and a direct connection.

Share only the relevant redacted fields. A monitor's advertised capabilities cannot establish its retail brand, physical connector inventory, measured HDR performance, or undocumented proprietary features.
