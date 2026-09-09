---
title: Install Monitor Bar
description: A small app bundle, a menu bar icon, and no background server.
permalink: /installation/
---

## Requirements

- An **Apple Silicon Mac**. The release contains an arm64 executable; Intel Macs are not supported.
- **macOS 13 or later**. Runtime hardware testing has been limited to an M3 Max Mac on macOS 26 with a generic USB-C monitor and a Samsung G91SD over HDMI. The minimum deployment target is not a claim that every older macOS release has been tested.
- An external display. Hardware sliders require a working DDC/CI path; resolution selection uses the modes macOS provides.

The app controls external monitors. It does not provide built-in Mac display brightness control.

## Download and launch

1. Download [Monitor-Bar-{{ site.release_version }}-arm64.zip]({{ site.download_url }}) from this project's GitHub release.
2. Open the ZIP in Finder to extract **Monitor Bar.app**.
3. Move **Monitor Bar.app** into **Applications**.
4. Open the app, then click its monitor icon in the menu bar.

The app has no Dock icon. Everyday controls open from the menu bar icon; the gear button opens a separate **Monitor Settings** window. Closing that window keeps the app running. If another copy is already running, quit it before opening a replacement.

### Samsung G91SD on a new installation

The Samsung control code is included in v0.1.3, but hardware controls start disabled without a local verification record for the individual monitor. Matching the model is not enough, and the release does not include an automatic verification or first-use enable button. Picture Mode, Color Tone, and Black Equalizer each need separate verification. Picture Mode also needs the Mac input set to PC mode. Saved hardware presets additionally require a verified PIP/PBP reader with PIP/PBP Off; see [Presets]({{ '/controls/' | relative_url }}#saved-hardware-presets).

Resolution selection remains available through macOS. If you want to help verify another Samsung unit, [open a compatibility report]({{ site.repository_url }}/issues/new/choose) with its model, firmware, Mac, and HDMI connection details. See [Samsung troubleshooting]({{ '/troubleshooting/' | relative_url }}#samsung-g91sd-hardware-controls) for the tested setup and current limits.

## First-open security prompt

This release is **ad-hoc signed and not notarized**. An ad-hoc signature does not identify a verified Apple developer. macOS may block the first launch because it cannot verify the developer or check the app for malicious software.

If you have reviewed the source and release and choose to trust this copy, first try opening it normally. Then open **System Settings → Privacy & Security**, find the message about Monitor Bar, and use **Open Anyway** if macOS offers it. Confirm the app-specific prompt. Apple's [guide to safely opening apps](https://support.apple.com/en-us/102445) explains these warnings and the exception process.

Do not disable Gatekeeper or remove system-wide protections to run the app. A warning that an app is damaged or will harm your computer deserves investigation; download a fresh copy from the release page and review Apple's guidance.

## Permissions and launch at login

Implemented display controls do not require administrator access, Accessibility permission, or Screen Recording permission. No helper daemon is installed.

Open **Monitor Settings → App** and enable **Launch Monitor Bar at login**. If macOS asks for approval, open **System Settings → General → Login Items** and allow Monitor Bar. Enable this after moving the app to its permanent location.

## Update

Updates are manual. Check [GitHub Releases]({{ site.repository_url }}/releases), quit Monitor Bar, and replace the app in Applications with the new copy. There is no in-app update checker. Custom ranges, hardware pauses, and per-unit Samsung verification stay in local preferences; they are not shipped inside the download. Updating does not clear a hardware pause or enable an unverified monitor.

## Quit or remove

Click **Quit** in the popover to stop the app. Software dimming disappears when the app closes. Hardware settings you changed can remain stored by the monitor; quitting does not restore every hardware setting. A kept resolution applies to the current login session.

To remove the app, turn off **Launch at login**, quit, and move **Monitor Bar.app** to the Trash. To return brightness or contrast to its advertised slider range, turn off that control's **Use custom range** before removing the app. This changes the saved mapping without issuing a hardware command.
