---
title: Controls & calibration
description: Keep everyday controls in the menu bar and open Monitor Settings for the rest.
permalink: /controls/
---

## Around the popover

Click the monitor icon in the menu bar. If more than one external display is listed, select the display you want to adjust. Monitor Bar refreshes when it starts, when displays change, on wake, and when you click the refresh button. A hardware pause blocks DDC commands while macOS display information remains available.

| Location | What is there |
|---|---|
| Popup | Brightness, contrast, supported volume, Picture Mode for verified Samsung units, and separate Resolution, Scaling, and Refresh rate choices |
| Gear button or Monitor settings… | Opens the Monitor Settings window |
| Preview controls | Apply a prepared mode with Preview changes, then Keep or Revert within 15 seconds |
| Footer | Open Monitor Settings or quit the app |

Hardware choices appear only when the app can read the control and validate its range or choices. Samsung controls also require a local verification record for that individual unit. **Not supported** means the app cannot offer that control from the available reply; details distinguish explicit unsupported replies from communication failures and invalid data.

## Monitor Settings

Click the popup's gear button or **Monitor settings…** to open a normal Mac
window for additional controls:

| Section | Controls |
|---|---|
| Picture | Sharpness, white balance, other supported hardware controls, and calibration; software dimming is available for monitors other than the Samsung |
| Presets | Save, apply, rename, and delete hardware setups for an individually verified Samsung |
| Information | Monitor details, hardware readback, reported modes, and diagnostic scans where supported |
| App | Launch at login, pause/resume hardware controls, report export, and macOS Displays |

The window shares the selected monitor and live state with the popup. Closing
it keeps Monitor Bar running in the menu bar. A pending resolution preview's
Keep/Revert controls are also available in the window.

<figure class="panel-preview" style="max-width: 760px">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="{{ '/assets/samsung-settings-dark.png' | relative_url }}">
    <img src="{{ '/assets/samsung-settings-light.png' | relative_url }}" alt="Monitor Settings window with Samsung image controls and white balance" width="1520" height="1240">
  </picture>
  <figcaption>Offline preview using sample Samsung data. Hardware controls require local verification.</figcaption>
</figure>

## Resolution, scaling, and refresh rate

The separate **Resolution**, **Scaling**, and **Refresh rate** choices were introduced in v0.1.2.

Choose a workspace size, select a rendering option, then choose an available refresh rate. Standard and HiDPI modes are labeled; different rendering pixel sizes remain available under Scaling. Fractional refresh rates stay distinct. **Unspecified** means macOS did not report a rate.

Selections and HiDPI shortcuts prepare a change. Click **Preview changes** to apply it, then **Keep** within 15 seconds or **Revert**. Until you start the preview, the monitor stays in its current mode. See [Resolution & HiDPI]({{ '/hidpi/' | relative_url }}) for the full workflow.

## Hardware adjustments

On monitors other than the Samsung G91SD, brightness and contrast show a normalized 0–100% range. Other sliders use the values the monitor exposes. Depending on the monitor, additional controls can include color temperature, RGB gain, RGB black levels, sharpness, color presets, audio mute, input source, OSD language, and power mode.

These sliders use absolute target values. Rapid changes are combined into the latest requested target, commands run one at a time, and the app makes up to three numeric readback checks. You can keep moving a slider while a write is in progress. A confirmed number means the firmware reported the requested value; it does not prove a corresponding change in measured brightness, contrast, or sound.

**Input source** and **Off / standby** ask for confirmation because they can disconnect the display. Keep access to the monitor's physical controls: a powered-down or switched-away monitor may stop responding to DDC and may need to be restored manually.

Unknown feature codes and factory-reset commands are diagnostic-only. The app does not offer an arbitrary DDC command console or automatic restoration of all hardware values.

## Saved hardware presets

Version 0.1.3 adds **Monitor Settings → Presets**. Presets belong to the selected
Samsung and require individually verified controls, verified PC Picture Mode,
and a verified PIP/PBP reader. PIP/PBP must be Off; an unavailable prerequisite
stops the operation before a preset is applied.

1. Adjust the monitor, then open **Presets → Save current…**.
2. Enter a name and choose **Save**. The app reads the hardware again instead
   of copying potentially stale slider values.
3. Choose **Apply** beside a saved setup to recall it. The row's **…** menu
   offers **Rename…** and **Delete…**. Deleting a preset only removes its saved data.

Applying sets Picture Mode and Color Tone first, then saved numeric controls,
and checks the final readings. Only currently verified controls can be included.
Eye Saver, input switching, power, display modes, and software dimming are
excluded. Presets stay in local app preferences and are applied manually;
there is no automatic switching by application.

On the tested unit, saving ten hardware values and applying an unchanged preset
passed without setting writes. A separate preset changed Black Equalizer
**5 → 6**, confirmed in the OSD with a stable image; the saved setup restored
**5**, preserving the other picture readings and connection state.

<figure class="panel-preview" style="max-width: 760px">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="{{ '/assets/samsung-presets-dark.png' | relative_url }}">
    <img src="{{ '/assets/samsung-presets-light.png' | relative_url }}" alt="Monitor Settings Presets section with saved hardware setups" width="1520" height="1240">
  </picture>
  <figcaption>Offline preview using sample data. Saving a preset does not verify a new monitor.</figcaption>
</figure>

If an operation fails, the app stops. Settings already accepted by the monitor
can remain changed; there is no automatic rollback. Check the reported failure
and the OSD before resuming hardware control.

Input, PIP/PBP, and sound-source formats have been decoded and tested offline.
Single hardware reads matched HDMI 1 and PIP/PBP support with the mode off.
A source-assignment read returned **invalid reply**, so testing stopped before
any input or layout changes. The user confirmed a stable
image, and verified picture controls were resumed. Audio was not queried. These controls remain unavailable. Transition verification needs a
second connected, active source and a physical check of the monitor's behavior.

## Samsung G91SD controls

Version 0.1.3 includes brightness, contrast, volume, sharpness, RGB white balance, Black Equalizer, Color Tone, and PC Picture Mode for an individually verified Samsung G91SD over direct HDMI. Hardware controls start disabled on a new installation; there is no first-use verification or enable workflow in this release. The Samsung must be the Mac's only external display, though the built-in screen can stay active. [Samsung troubleshooting]({{ '/troubleshooting/' | relative_url }}#samsung-g91sd-hardware-controls) explains the verification limit.

<figure class="panel-preview" style="max-width: 420px">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="{{ '/assets/samsung-panel-dark.png' | relative_url }}">
    <img src="{{ '/assets/samsung-panel-light.png' | relative_url }}" alt="Example Samsung panel with hardware sliders and an Eco Picture Mode selection" width="840" height="1120">
  </picture>
  <figcaption>Offline preview using sample Samsung data. Hardware controls require local verification.</figcaption>
</figure>

The sliders use the monitor's OSD units: brightness and contrast **0–50**, sharpness **0–20**, volume **0–100**, and Black Equalizer **0–10**, following its reported ranges. Sharpness and white balance are under **Monitor Settings → Picture**. For RGB gains reporting a maximum of 100, the display subtracts 50: raw 51 was observed as **+1** in the OSD. This is not a full-range color calibration, and it does not change the separate OSD **Color** setting.

**Color Tone** offers Cool, Standard, Warm 1, Warm 2, and Natural. All five choices were physically confirmed on the tested setup, with Warm 1 restored after each check. Black Equalizer OSD values **0, 5, 6, and 10** were confirmed with a stable image. Intermediate levels and the direction of the visual change remain unverified. Other picture readbacks were unchanged immediately after each test change. Black Equalizer was returned to 5 after the endpoint checks. This coverage does not apply to other units, firmware, or input modes. Each additional control requires its own local verification record. Samsung's Color Tone mapping is separate from generic color-temperature presets.

**Eye Saver Mode** remains disabled while its delayed response is investigated. Its state is read before affected controls when an additional Samsung control is enabled. While Eye Saver is active or unavailable, brightness, Picture Mode, Color Tone, white balance, and Black Equalizer cannot be changed. See [Eye Saver timing]({{ '/troubleshooting/' | relative_url }}#samsung-eye-saver-mode) for the test result.

Samsung sliders apply when released. The app first reads the current hardware value and refuses a stale change, then sends one write and checks it once. There are no alternate packet-format retries or deep scans. A full refresh makes at most 12 reads with all verified controls enabled and skips controls known to be locked. Preset changes complete and refresh related settings before another write is accepted. Connection or transport failures pause further commands.

**Picture Mode**, above Resolution, needs separate per-unit verification and the Mac's input in **PC** mode. Its ten named PC choices were mapped from Samsung's official Display Manager app and the OSD; hardware changes between **Eco** and **Original** were physically confirmed. The [mode table]({{ '/troubleshooting/' | relative_url }}#samsung-picture-mode) distinguishes those tests from the other choices. Presets can change brightness, contrast, and color settings, so Monitor Bar temporarily disables adjustments and refreshes the sliders afterward.

## Pause and resume hardware controls

Use **Monitor Settings → App → Pause hardware controls** to stop hardware discovery, reads, writes, and retries for every monitor. The pause survives relaunches and reconnections. macOS resolution selection and software dimming on other monitors remain available.

When the connection is stable, **Resume hardware controls** restarts checks for connected monitors other than the Samsung, or for one previously verified Samsung connected on its own. Resume is unavailable with no external display, an unverified Samsung, or a Samsung mixed with another external display. Resuming a Samsung explicitly accepts its current HDMI connection; it does not verify a new unit for you.

## Optional brightness and contrast calibration

These calibration controls apply to monitors other than the Samsung G91SD. Fresh installations use the monitor's **advertised range**, with calibration off by default. Enable it only when a control behaves incorrectly across that range, such as increasing and then falling again as you move toward 100%.

The custom range maps the full percentage slider onto hardware values from **0 to a chosen maximum**. It is an endpoint mapping, not an automatic calibration or a measured luminance curve. Brightness and contrast have independent settings.

1. Open **Monitor Settings → Picture → Calibration** and choose brightness or contrast.
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

On monitors other than the Samsung, **Monitor Settings → Picture → Software dimming** adds a click-through dark overlay to the selected screen. **Image brightness** ranges from 20% to 100%. It darkens the image without reducing the physical backlight or changing hardware brightness calibration.

Use **Restore image brightness** or move the slider to 100% to remove the overlay. Quitting Monitor Bar also removes it. This setting is separate from hardware brightness and is not a monitor power-saving control.

## Settings managed by macOS

Use **Monitor Settings → App → Open macOS Displays** for HDR, arrangement, rotation, mirroring, and color profiles. Monitor Bar's [resolution controls]({{ '/hidpi/' | relative_url }}) choose among existing macOS modes; they do not install custom resolutions or EDID overrides.
