---
title: Resolution & HiDPI
description: Separate workspace size, rendering pixels, and aspect ratio when choosing a display mode.
permalink: /hidpi/
---

Version 0.1.2 separates display-mode selection into resolution, scaling, and refresh rate. You can prepare a combination before previewing it.

## Choose resolution, scaling, and refresh rate

The main card separates display modes into three choices:

- **Resolution** lists each logical workspace size once.
- **Scaling** selects a rendering option for that workspace. Standard and HiDPI modes are labeled; other modes show their rendering pixel size. Different rendering sizes remain separate options, even when both are HiDPI.
- **Refresh rate** lists the rates available for that resolution and scaling. Fractional rates such as 59.94 Hz remain distinct from 60 Hz when macOS reports both. **Unspecified** means macOS did not report a rate.

These choices prepare a change without applying it. Review the selected rendering pixels and aspect ratio before clicking **Preview changes**. The available combinations come from macOS; the app does not create missing modes.

## Read the mode information

| Term | Meaning |
|---|---|
| Workspace size | The logical dimensions that determine how much desktop fits and how large the interface appears |
| Rendering pixels | The pixel dimensions macOS reports for that mode |
| HiDPI | Rendering uses more pixels than logical workspace points, with matching scale factors on both axes |
| Refresh rate | The rate reported by macOS for the mode; firmware may provide incomplete data |
| Aspect ratio | The relationship between width and height, such as 16:10 or 3:2 |

For example, a **1280 × 800 workspace rendered at 2560 × 1600** has 2× scaling on both axes. Text and interface elements have more rendering pixels at the same logical size. A larger workspace number does not automatically mean sharper text.

HiDPI rendering alone does not establish the physical panel's resolution or guarantee a sharp final image. Scaling inside the monitor, a mismatched aspect ratio, and the display connection can still affect what you see.

## Preview a resolution

1. Choose **Resolution**, **Scaling**, and **Refresh rate**, or use a HiDPI shortcut if one appears. Shortcuts also prepare the selection without applying it.
2. Click **Preview changes** to try the selected mode.
3. Check text, circles, and the edges of the desktop. Look for stretch, cropping, or black borders.
4. Click **Keep** within 15 seconds if the result looks correct. Click **Revert** to return immediately.

If you do nothing, Monitor Bar requests the previous mode after 15 seconds. It also verifies that macOS actually applied the requested mode. A kept selection lasts for the **current login session**; it is not a startup resolution preset.

If the display stays blank after the timer, open macOS Displays from another screen if available, or reconnect the monitor. The app reports a failed restore when macOS returns an error.

## Why some modes are in details only

macOS can return duplicates and modes unsuitable for normal desktop use. The controls deduplicate equivalent entries and offer valid, safe modes that are desktop-usable or marked native. Different rendering sizes and reported refresh rates remain available. Stretched, interlaced, hidden, and other unsuitable entries are excluded from normal selection. The current mode remains visible even when it does not meet those rules.

**Monitor Settings → Information → Monitor information → All reported modes** preserves the complete list, including flags and desktop-usability information. A mode appearing in diagnostics is not a recommendation to use it. The app does not generate or force extra modes that macOS did not return.

## When the monitor and macOS disagree

Monitor Bar compares the monitor's preferred EDID timing with the mode macOS marks native. If suitable HiDPI modes exist for both and they differ, the main card offers both as shortcuts. Select one, then click **Preview changes**. Neither reported value by itself proves the physical panel size.

One tested generic display reported these conflicting sizes:

| Reported option | Workspace | Rendering pixels | Aspect |
|---|---|---|---|
| Monitor preferred timing | 1260 × 840 | 2520 × 1680 | 3:2 |
| macOS native mode | 1280 × 800 | 2560 × 1600 | 16:10 |

These are an example, not requirements or guaranteed modes for your display. Preview the available options and keep the one with correct proportions and clear text. If neither looks right, inspect the monitor's own aspect/scaling settings and the connection, then use [troubleshooting]({{ '/troubleshooting/' | relative_url }}#the-image-is-blurry-or-stretched).

## No HiDPI choice appears

The app can only select modes that macOS exposes for the current connection. A different cable, direct connection, adapter, or input can change that list. Refresh the app after reconnecting. If no suitable HiDPI mode is reported, Monitor Bar cannot enable one through a custom timing or system override.
