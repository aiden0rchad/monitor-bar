---
title: Your monitor, within reach.
description: Brightness, contrast, resolution, and the controls your external display exposes. Right in the Mac menu bar.
permalink: /
home: true
---

<div class="hero">
  <div class="hero-copy">
    <p>Monitor Bar puts everyday display controls in a small native popover. Click the monitor icon, make an adjustment, and get back to work.</p>
    <p>Built for Apple Silicon with SwiftUI and AppKit. Free, open source, and entirely local.</p>
    <div class="actions">
      <a class="button" href="{{ site.download_url }}">Download v{{ site.release_version }}</a>
      <a class="button secondary" href="{{ '/installation/' | relative_url }}">Installation guide</a>
    </div>
    <p class="release-note">Apple Silicon (arm64) · macOS 13 or later<br>Ad-hoc signed. Not notarized by Apple.</p>
    <p class="release-note">Tested on an M3 Max Mac running macOS 26 with a generic USB-C display and one Samsung G91SD over HDMI. Samsung controls require individual verification and start disabled on new installations.</p>
  </div>
  <figure class="panel-preview">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="{{ '/assets/monitor-panel-dark.png' | relative_url }}">
      <img src="{{ '/assets/monitor-panel-light.png' | relative_url }}" alt="Example Monitor Bar panel with brightness, contrast, volume, resolution, and HiDPI controls." width="840" height="1120">
    </picture>
    <figcaption>Example panel using demo data. Available controls and resolutions depend on your monitor.</figcaption>
  </figure>
</div>

## Small interface. Useful controls.

<div class="feature-grid">
  <section class="feature"><h3>Adjust the hardware</h3><p>Brightness, contrast, volume, color, and other supported DDC controls. The app reads settings back after sending a change.</p></section>
  <section class="feature"><h3>Find a clearer workspace</h3><p>Choose among the modes macOS reports. See HiDPI scaling, rendering pixels, refresh rate, and aspect ratio before keeping a change.</p></section>
  <section class="feature"><h3>Handle unusual ranges</h3><p>Optional per-monitor brightness and contrast calibration maps the slider onto a smaller hardware range.</p></section>
  <section class="feature"><h3>See what the monitor reports</h3><p>Inspect display information, available DDC replies, and every reported mode. Export a local report when needed.</p></section>
</div>

## What to expect

The app controls external displays through macOS display APIs and DDC/CI. A USB-C connection alone does not guarantee hardware control: the monitor, cable, adapter, or dock must allow the commands through. Firmware can advertise a control and still implement it incorrectly.

Generic monitors use their advertised brightness and contrast ranges on a fresh installation. Custom calibration is **off by default**, and saved separately for each control and monitor. There is no universal setting for generic panels.

Version **0.1.1** adds a guarded Samsung G91SD HDMI control path with seven hardware sliders and a PC Picture Mode picker. It requires a local verification record for the individual monitor; the download does not automatically enable another G91SD. [Read the Samsung limits]({{ '/troubleshooting/' | relative_url }}#samsung-g91sd-hardware-controls) before choosing it for that setup.

The gear menu can pause all hardware commands, and the pause survives a relaunch. Samsung connection or control failures also trigger that pause. Resume restarts hardware checks for ordinary monitors, or for a single, previously verified Samsung; a Samsung mixed with another external display remains blocked. Resolution selection and software dimming remain available while hardware commands are paused.

Resolution changes have a 15-second preview. Click **Keep** to retain the mode for your current login session, or let the app request the previous mode. Read more about [HiDPI and aspect ratio]({{ '/hidpi/' | relative_url }}).

Monitor Bar has no account, tracking, network service, or automatic updater. Downloads and updates are available on [GitHub Releases]({{ site.repository_url }}/releases). The [MIT license]({{ site.repository_url }}/blob/main/LICENSE) permits use and modification without charge.

## Start here

- [Install and open the app]({{ '/installation/' | relative_url }}).
- [Learn the controls and optional calibration]({{ '/controls/' | relative_url }}).
- [Find help when a setting is missing or looks wrong]({{ '/troubleshooting/' | relative_url }}).
- [Build from source and review privacy details]({{ '/development/' | relative_url }}).
