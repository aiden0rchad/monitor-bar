---
title: Controls & calibration
description: Use the everyday controls up front, and expand the rest when you need them.
permalink: /controls/
---

## Around the popover

Click the monitor icon in the menu bar. If more than one external display is listed, select the display you want to adjust. Monitor Bar refreshes when it starts, when displays change, on wake, and when you click the refresh button. A hardware pause blocks DDC commands while macOS display information remains available.

| Location | What is there |
|---|---|
| Main card | Brightness, contrast, supported volume, and resolution; verified Samsung units also offer sharpness and Picture Mode |
| More controls | Additional hardware settings, software dimming, and brightness/contrast calibration for monitors other than the Samsung |
| Show details | Monitor information, DDC readback, and reported resolutions; full scan is unavailable for Samsung |
| Gear menu | Pause/resume hardware controls, launch at login, report export, and macOS Displays settings |
| Footer | Quit, or the Keep / Revert controls during a resolution preview |

Hardware choices appear only when the app can read the control and validate its range or choices. Samsung controls also require a local verification record for that individual unit. **Not supported** means the app cannot offer that control from the available reply; details distinguish explicit unsupported replies from communication failures and invalid data.

## Hardware adjustments

On monitors other than the Samsung G91SD, brightness and contrast show a normalized 0–100% range. Other sliders use the values the monitor exposes. Depending on the monitor, additional controls can include color temperature, RGB gain, RGB black levels, sharpness, color presets, audio mute, input source, OSD language, and power mode.

These sliders use absolute target values. Rapid changes are combined into the latest requested target, commands run one at a time, and the app makes up to three numeric readback checks. You can keep moving a slider while a write is in progress. A confirmed number means the firmware reported the requested value; it does not prove a corresponding change in measured brightness, contrast, or sound.

**Input source** and **Off / standby** ask for confirmation because they can disconnect the display. Keep access to the monitor's physical controls: a powered-down or switched-away monitor may stop responding to DDC and may need to be restored manually.

Unknown feature codes and factory-reset commands are diagnostic-only. The app does not offer an arbitrary DDC command console, saved settings presets, or automatic restoration of all hardware values.

## Samsung G91SD controls

Version 0.1.1 includes seven hardware sliders for an individually verified Samsung G91SD over direct HDMI. They start disabled on a new installation; there is no first-use verification or enable workflow in this release. The Samsung must be the Mac's only external display, though the built-in screen can stay active. [Samsung troubleshooting]({{ '/troubleshooting/' | relative_url }}#samsung-g91sd-hardware-controls) explains the verification limit.

<figure class="panel-preview" style="max-width: 420px">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="{{ '/assets/samsung-panel-dark.png' | relative_url }}">
    <img src="{{ '/assets/samsung-panel-light.png' | relative_url }}" alt="Example Samsung panel with hardware sliders and an Eco Picture Mode selection" width="840" height="1120">
  </picture>
  <figcaption>Offline preview using sample Samsung data. Hardware controls require local verification.</figcaption>
</figure>

The sliders use the monitor's OSD units: brightness and contrast **0–50**, sharpness **0–20**, and volume **0–100**, following its reported ranges. White-balance controls are under **More controls**. For RGB gains reporting a maximum of 100, the display subtracts 50: raw 51 was observed as **+1** in the OSD. This is not a full-range color calibration, and it does not change the separate OSD **Color** setting.

Samsung sliders apply when released. The app first reads the current hardware value and refuses a stale change, then sends one write and checks it once. There are no alternate packet-format retries or deep scans. A full refresh makes at most nine reads: seven slider values, PC/AV mode, and Picture Mode. Connection or transport failures pause further commands.

**Picture Mode**, above Resolution, needs separate per-unit verification and the Mac's input in **PC** mode. Its ten named PC choices were mapped from Samsung's official Display Manager app and the OSD; hardware changes between **Eco** and **Original** were physically confirmed. The [mode table]({{ '/troubleshooting/' | relative_url }}#samsung-picture-mode) distinguishes those tests from the other choices. Presets can change brightness, contrast, and color settings, so Monitor Bar temporarily disables adjustments and refreshes the sliders afterward.

## Pause and resume hardware controls

Use **Gear menu → Pause hardware controls** to stop hardware discovery, reads, writes, and retries for every monitor. The pause survives relaunches and reconnections. Software dimming and macOS resolution selection remain available.

When the connection is stable, **Resume hardware controls** restarts checks for connected monitors other than the Samsung, or for one previously verified Samsung connected on its own. Resume is unavailable with no external display, an unverified Samsung, or a Samsung mixed with another external display. Resuming a Samsung explicitly accepts its current HDMI connection; it does not verify a new unit for you.

## Optional brightness and contrast calibration

These calibration controls apply to monitors other than the Samsung G91SD. Fresh installations use the monitor's **advertised range**, with calibration off by default. Enable it only when a control behaves incorrectly across that range, such as increasing and then falling again as you move toward 100%.

The custom range maps the full percentage slider onto hardware values from **0 to a chosen maximum**. It is an endpoint mapping, not an automatic calibration or a measured luminance curve. Brightness and contrast have independent settings.

1. Open **More controls → Brightness calibration** or **Contrast calibration**.
2. Turn on **Use custom range**. The initial proposed maximum is 25, or the advertised maximum if it is lower. This is a starting value to inspect, not a detected correct endpoint.
3. Adjust **Maximum hardware value** to the end of the useful rising range for this control on your monitor.
4. Move the corresponding main slider to try the mapping. If the visible effect reverses near the top, lower the maximum and try again.
5. Turn off **Use custom range** whenever you want to return to the advertised range.

Saving or disabling a range **does not send a hardware command**. Your next adjustment of that slider uses the new mapping. If the current raw value lies above a newly chosen maximum, the app leaves it untouched until you adjust the slider; the displayed percentage is capped at 100%.

### Why 25 is an example

One generic USB-C panel showed a rising brightness range around raw 0–25 followed by falling and repeating behavior across its advertised range. A maximum of 25 worked as a useful starting point on that panel. This observation does not establish an appropriate range for another monitor, or the right contrast endpoint even on the same monitor.

A raw range of **0–25 contains 26 hardware levels**. The slider therefore changes in roughly 4% steps. It cannot create additional physical backlight levels. Diagnostics continue to show raw hardware values, while the main slider shows the mapped percentage.

The mapping is saved locally per control and per vendor/product/serial identity. It is not automatically applied to unrelated monitors. Display identity limitations are covered in [troubleshooting]({{ '/troubleshooting/' | relative_url }}#multiple-monitors-and-identity).

## Software dimming

**More controls → Software dimming** adds a click-through dark overlay to the selected screen. **Image brightness** ranges from 20% to 100%. It darkens the image without reducing the physical backlight or changing hardware brightness calibration.

Use **Restore image brightness** or move the slider to 100% to remove the overlay. Quitting Monitor Bar also removes it. This setting is separate from hardware brightness and is not a monitor power-saving control.

## Settings managed by macOS

Use the gear menu's **Open macOS Displays** action for HDR, arrangement, rotation, mirroring, and color profiles. Monitor Bar's [resolution controls]({{ '/hidpi/' | relative_url }}) choose among existing macOS modes; they do not install custom resolutions or EDID overrides.
