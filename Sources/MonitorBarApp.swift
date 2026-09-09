import AppKit
import SwiftUI

@main
@MainActor
struct MonitorBarApp: App {
    @NSApplicationDelegateAdaptor(MonitorBarDelegate.self) private var delegate
    @StateObject private var store = MonitorStore()

    var body: some Scene {
        MenuBarExtra("Monitor Bar", systemImage: "display") {
            MonitorPanel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class MonitorBarDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@MainActor
struct MonitorPanel: View {
    @ObservedObject var store: MonitorStore
    @State private var diagnosticsExpanded = true
    @State private var showDetails = false
    @State private var modesExpanded = false
    @State private var pendingControl: PendingControl?

    private struct PendingControl: Identifiable {
        let feature: VCPFeature
        let value: UInt16
        let label: String
        var id: UInt8 { feature.code }
    }

    private var mainFeatures: [VCPFeature] {
        store.features.filter { ([0x10, 0x12, 0x62].contains($0.code) || (store.usesSamsungControls && $0.code == 0x87)) && $0.isSlider }
    }

    private var otherFeatures: [VCPFeature] {
        store.features.filter { feature in !mainFeatures.contains(where: { $0.code == feature.code }) && feature.isSlider }
    }

    private var choiceFeatures: [VCPFeature] {
        store.features.filter { !(store.usesSamsungControls && $0.code == 0x2D) && $0.isReadable && !store.allowedChoices(for: $0).isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let display = store.selected {
                        VStack(alignment: .leading, spacing: 12) {
                            displayCard(display)
                            Divider()
                            hardwareControls
                            Divider()
                            if store.usesSamsungControls,
                               let pictureMode = store.features.first(where: { $0.code == 0x2D && $0.isReadable }),
                               !store.allowedChoices(for: pictureMode).isEmpty {
                                pictureModeControl(pictureMode)
                            }
                            resolutionControls(display)
                        }
                        .padding(14)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                        moreControls
                        if showDetails { diagnostics }
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "display.trianglebadge.exclamationmark")
                                .font(.system(size: 36, weight: .light))
                                .foregroundStyle(.secondary)
                            Text("No external display").font(.headline)
                            Text("Connect your monitor, then rescan.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                    }
                    if !store.message.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: store.busy || store.writing ? "arrow.triangle.2.circlepath" : "info.circle")
                            Text(store.statusText).textSelection(.enabled)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
            }
            Divider()
            if store.pendingMode {
                modeConfirmation
            } else {
                footer
            }
        }
        .frame(width: 420, height: 560)
        .background(.regularMaterial)
        .onAppear {
            if store.lastScan == nil && !store.busy { store.refresh() }
        }
        .alert(item: $pendingControl) { change in
            Alert(
                title: Text("Change \(change.feature.name.lowercased())?"),
                message: Text("Selecting \(change.label) may disconnect or blank this display. You may need the monitor’s physical controls to restore it."),
                primaryButton: .default(Text("Apply \(change.label)")) {
                    store.set(change.feature, value: change.value)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "display").font(.system(size: 17)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Monitor Bar").font(.system(size: 13, weight: .semibold))
                Text("Controls for your external display").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if store.busy || store.writing { ProgressView().controlSize(.mini).accessibilityLabel(store.message) }
            Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .disabled(store.busy || store.writing || store.pendingMode)
                .help("Refresh display settings").accessibilityLabel("Refresh display settings")
            Menu {
                if store.hardwareCommandsPaused {
                    Button("Resume hardware controls", action: store.resumeHardwareCommands)
                        .disabled(!store.canResumeHardwareCommands)
                } else {
                    Button("Pause hardware controls", action: store.pauseHardwareCommands)
                }
                Divider()
                Toggle("Launch at login", isOn: Binding(get: { store.launchAtLogin }, set: { _ in store.toggleLaunchAtLogin() }))
                Button("Export monitor report…", action: store.exportReport).disabled(store.busy || store.writing || store.pendingMode)
                Button("Open macOS Displays", action: store.openDisplaySettings)
                Divider()
                Button("Quit Monitor Bar") { NSApp.terminate(nil) }.keyboardShortcut("q")
            } label: { Image(systemName: "gearshape") }
            .menuStyle(.borderlessButton).fixedSize()
            .help("Settings").accessibilityLabel("Settings")
        }
        .buttonStyle(.borderless)
        .padding(12)
    }

    private func displayCard(_ display: DisplayInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "display").font(.system(size: 25, weight: .light))
                .foregroundStyle(.green).frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                if store.displays.count > 1 {
                    Picker("Display", selection: Binding(get: { store.selectedID }, set: { store.selectDisplay($0) })) {
                        ForEach(store.displays) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden().disabled(store.busy || store.writing || store.pendingMode)
                } else {
                    Text(display.name).font(.system(size: 15, weight: .semibold))
                }
                Text(store.usesSamsungControls ? "HDMI hardware controls" : "External display")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(.system(size: 10, weight: .medium)).foregroundStyle(.green)
        }
    }

    private var hardwareControls: some View {
        VStack(spacing: 12) {
            ForEach([UInt8(0x10), 0x12], id: \.self) { code in
                if let feature = mainFeatures.first(where: { $0.code == code }) {
                    featureSlider(feature)
                } else {
                    HStack {
                        Label(code == 0x10 ? "Brightness" : "Contrast", systemImage: code == 0x10 ? "sun.max" : "circle.lefthalf.filled")
                        Spacer()
                        Text(store.hardwareCommandsPaused ? "Paused" : store.busy ? "Reading…" : "Not supported").foregroundStyle(.secondary)
                    }.font(.system(size: 12)).frame(height: 42)
                }
            }
            if let sharpness = mainFeatures.first(where: { $0.code == 0x87 }) { featureSlider(sharpness) }
            if let volume = mainFeatures.first(where: { $0.code == 0x62 }) { featureSlider(volume) }
        }
        .disabled(store.hardwareCommandsPaused || store.busy || store.pendingMode || store.pendingValues[0x2D] != nil)
    }

    private var moreControls: some View {
        DisclosureGroup {
            VStack(spacing: 13) {
                if !store.usesSamsungControls {
                    ForEach(mainFeatures.filter { [0x10, 0x12].contains($0.code) }) { feature in
                        controlCalibration(feature)
                    }
                }
                if store.usesSamsungControls && !otherFeatures.isEmpty { sectionTitle("WHITE BALANCE", detail: "Monitor values") }
                ForEach(otherFeatures) { feature in featureSlider(feature) }.disabled(store.hardwareCommandsPaused)
                ForEach(choiceFeatures) { feature in featurePicker(feature) }.disabled(store.hardwareCommandsPaused)
                dimmingControls
            }
            .padding(.top, 12)
            .disabled(store.busy || store.pendingMode || store.pendingValues[0x2D] != nil)
        } label: {
            Label("More controls", systemImage: "slider.horizontal.3").font(.system(size: 12, weight: .medium))
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func featureSlider(_ feature: VCPFeature) -> some View {
        if store.usesSamsungControls {
            let offset = store.osdOffset(for: feature)
            let title = offset == 50 ? feature.name.replacingOccurrences(of: " gain", with: "") : feature.name
            let icon = [UInt8(0x10): "sun.max", 0x12: "circle.lefthalf.filled", 0x87: "circle.lefthalf.striped.horizontal", 0x62: "speaker.wave.2"][feature.code] ?? "circle.fill"
            ValueSlider(title: title, icon: icon,
                        current: Double(Int(store.value(for: feature)) - offset),
                        range: Double(-offset)...Double(Int(feature.maximum) - offset),
                        detail: "Release to apply. HDMI value: \(feature.current) / \(feature.maximum).",
                        commitWhileDragging: false) { store.setOSDValue(feature, value: $0) }
        } else if [0x10, 0x12].contains(feature.code) {
            let limit = store.controlLimits[feature.code] ?? feature.maximum
            ValueSlider(title: feature.name, icon: feature.code == 0x10 ? "sun.max" : "circle.lefthalf.filled",
                        current: store.controlPercent(for: feature),
                        range: 0...100,
                        detail: "\(feature.name) 0–100% uses hardware values 0–\(limit). Monitor reports \(feature.current) / \(feature.maximum).",
                        suffix: "%", step: 100 / Double(limit)) { store.setPercent(feature, percent: $0) }
        } else if feature.code == 0x0C,
           let increment = store.features.first(where: { $0.code == 0x0B && $0.isReadable })?.current,
           (1...1000).contains(increment) {
            let kelvin = 3000 + Int(store.value(for: feature)) * Int(increment)
            ValueSlider(title: feature.name, icon: "thermometer.medium", current: Double(kelvin),
                        range: 3000...Double(3000 + Int(feature.maximum) * Int(increment)),
                        detail: "Monitor reports \(feature.current) / \(feature.maximum)",
                        suffix: " K", step: Double(increment)) {
                store.set(feature, value: UInt16((($0 - 3000) / Double(increment)).rounded()))
            }
        } else {
            ValueSlider(
                title: feature.name,
                icon: feature.code == 0x62 ? "speaker.wave.2" : "circle.lefthalf.filled",
                current: Double(store.value(for: feature)),
                range: 0...Double(feature.maximum),
                detail: "Monitor reports \(feature.current) / \(feature.maximum)",
                suffix: feature.maximum == 100 ? "%" : ""
            ) { value in store.set(feature, value: UInt16(value.rounded())) }
        }
    }

    private func controlCalibration(_ feature: VCPFeature) -> some View {
        DisclosureGroup("\(feature.name) calibration") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Use custom range", isOn: Binding(
                    get: { store.controlLimits[feature.code] != nil },
                    set: { store.setControlLimit(feature, limit: $0 ? min(25, feature.maximum) : nil) }))
                    .toggleStyle(.switch).controlSize(.mini)
                if let limit = store.controlLimits[feature.code] {
                    Stepper("Maximum hardware value: \(limit)", value: Binding(
                        get: { store.controlLimits[feature.code] ?? min(25, feature.maximum) },
                        set: { store.setControlLimit(feature, limit: $0) }), in: 1...feature.maximum)
                        .controlSize(.small)
                }
                Text("Uses only the first rising section. Start at 25; lower if \(feature.name.lowercased()) falls near the top.")
                    .foregroundStyle(.secondary)
                Text("Current hardware value: \(feature.current) / \(feature.maximum)")
                    .foregroundStyle(.secondary).monospacedDigit()
                if let limit = store.controlLimits[feature.code], feature.current > limit {
                    Text("The current value is above this range. Adjust \(feature.name.lowercased()) to apply the calibrated range.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 10)
        }
        .font(.caption)
        .disabled(store.hardwareCommandsPaused || store.busy || store.writing || store.pendingMode)
    }

    private func featurePicker(_ feature: VCPFeature) -> some View {
        let choices = store.allowedChoices(for: feature)
        return Picker(feature.name, selection: Binding(get: { feature.current }, set: { value in
            guard value != feature.current else { return }
            if [0x60, 0xD6].contains(feature.code) {
                pendingControl = PendingControl(feature: feature, value: value, label: choices.first { $0.0 == value }?.1 ?? String(value))
            } else {
                store.set(feature, value: value)
            }
        })) {
            if !choices.contains(where: { $0.0 == feature.current }) {
                Text("Current: \(feature.current)").tag(feature.current)
            }
            ForEach(choices, id: \.0) { choice in
                Text(choice.1).tag(choice.0)
            }
        }
        .font(.caption)
    }

    private var dimmingControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            sectionTitle("SOFTWARE DIMMING", detail: "Screen overlay")
            ValueSlider(title: "Image brightness", icon: "moon", current: store.dimming * 100, range: 20...100, detail: "Darkens the image; does not change the backlight.", suffix: "%") {
                store.setDimming($0 / 100)
            }
            .disabled(store.busy || store.pendingMode)
            if store.dimming < 1 {
                Button("Restore image brightness") { store.setDimming(1) }
                    .font(.caption)
                    .disabled(store.busy || store.pendingMode)
            }
        }
    }

    private func pictureModeControl(_ feature: VCPFeature) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "photo").foregroundStyle(.secondary).frame(width: 18)
            Text("Picture Mode").font(.system(size: 12, weight: .medium))
            Spacer()
            Picker("Picture Mode", selection: Binding(get: { feature.current }, set: { value in
                if value != feature.current { store.set(feature, value: value) }
            })) {
                ForEach(store.allowedChoices(for: feature), id: \.0) { choice in
                    Text(choice.1).tag(choice.0)
                }
            }
            .labelsHidden().controlSize(.small).frame(maxWidth: 245, alignment: .trailing)
        }
        .help("Picture presets may change brightness, contrast, and color settings.")
        .disabled(store.hardwareCommandsPaused || store.busy || store.writing || store.pendingMode)
    }

    private func resolutionControls(_ display: DisplayInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "rectangle.inset.filled").foregroundStyle(.secondary).frame(width: 18)
                Text("Resolution").font(.system(size: 12, weight: .medium))
                Spacer()
                Picker("Resolution", selection: Binding(get: { display.currentModeID }, set: { store.setMode($0) })) {
                    Section("HiDPI · sharper text") {
                        ForEach(display.selectableModes.filter(\.isHiDPI)) { mode in
                            Text(modeChoice(mode)).tag(mode.id)
                        }
                    }
                    Section("Standard resolution") {
                        ForEach(display.selectableModes.filter { !$0.isHiDPI }) { mode in
                            Text(modeChoice(mode)).tag(mode.id)
                        }
                    }
                }
                .labelsHidden().controlSize(.small).frame(maxWidth: 245, alignment: .trailing)
                .disabled(store.busy || store.writing || store.pendingMode)
            }
            if let mode = display.currentMode {
                Text("\(mode.scaleLabel) · \(mode.pixelLabel) · \(mode.aspectLabel)")
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 25)
            }
            if let panel = store.panelHiDPIMode, let macOS = store.macOSHiDPIMode, panel.id != macOS.id {
                HStack(spacing: 8) {
                    hiDPIButton(panel, title: "\(panel.aspectLabel) HiDPI")
                    hiDPIButton(macOS, title: "\(macOS.aspectLabel) HiDPI")
                    Spacer(minLength: 0)
                }
                Text("Two native sizes reported. Preview to check proportions.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).help(store.modeWarning ?? "")
            } else if let mode = store.panelHiDPIMode ?? store.macOSHiDPIMode {
                hiDPIButton(mode, title: "Use HiDPI")
            }
        }
    }

    private func modeChoice(_ mode: DisplayModeInfo) -> String {
        "\(mode.width) × \(mode.height)" + (mode.isHiDPI ? " · HiDPI" : "") + String(format: " · %.2f Hz", mode.refreshRate)
    }

    private func hiDPIButton(_ mode: DisplayModeInfo, title: String) -> some View {
        Button { store.setMode(mode.id) } label: {
            Label(title, systemImage: mode.id == store.selected?.currentModeID ? "checkmark" : "sparkles")
        }
        .controlSize(.small)
        .disabled(store.busy || store.writing || store.pendingMode || mode.id == store.selected?.currentModeID)
        .help("Preview \(mode.width) × \(mode.height) workspace, \(mode.pixelLabel). Reverts in 15 seconds unless kept.")
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            DisclosureGroup("Monitor information", isExpanded: $diagnosticsExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    if let display = store.selected {
                        Text("Panel: \(Int(display.widthMM)) × \(Int(display.heightMM)) mm · Rotation: \(Int(display.rotation))°")
                            .foregroundStyle(.secondary)
                        DisclosureGroup("All \(display.modes.count) reported modes", isExpanded: $modesExpanded) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Read-only diagnostics. The resolution picker includes valid, safe desktop or native modes. Other reported modes are not recommended.")
                                    .foregroundStyle(.secondary)
                                ForEach(Array(display.modes.enumerated()), id: \.offset) { _, mode in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mode.label)
                                        Text("\(mode.pixelLabel) · \(mode.aspectLabel)")
                                        Text("ID \(mode.id) · Flags \(String(format: "0x%08X", mode.ioFlags))")
                                            .font(.system(size: 10, design: .monospaced))
                                        Text("Desktop GUI: \(mode.isDesktopUsable ? "yes" : "no") · Native: \(mode.isNative ? "yes" : "no")")
                                        Text(mode.isSelectable ? "Available in resolution picker" : "Not recommended · read-only")
                                            .foregroundStyle(mode.isSelectable ? Color.secondary : Color.orange)
                                    }
                                    .textSelection(.enabled)
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                    if let warning = store.modeWarning { Text(warning).foregroundStyle(.orange) }
                    Text("Monitor preferred: \(store.panelModeLabel)\nmacOS native: \(store.macOSModeLabel)")
                    if !store.edidSummary.isEmpty {
                        Text(store.edidSummary).textSelection(.enabled)
                    }
                    if let scanned = store.lastScan {
                        Text("Last read: \(scanned.formatted(date: .omitted, time: .standard))")
                            .foregroundStyle(.secondary)
                    }
                    if !store.features.isEmpty {
                        Text("CONTROL READBACK").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        ForEach(store.features) { feature in
                            HStack(alignment: .top, spacing: 6) {
                                Text(feature.hex).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                                Text(feature.name)
                                Spacer(minLength: 4)
                                Text(feature.isReadable ? "\(feature.current) / \(feature.maximum)" : feature.status)
                                    .foregroundStyle(feature.isReadable ? Color.primary : Color.secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                            .textSelection(.enabled)
                        }
                    }
                    if !store.capabilities.isEmpty {
                        Text("DDC/CI CAPABILITIES").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        Text(store.capabilities)
                            .font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    if store.usesSamsungControls {
                        Text("Reads seven picture and volume controls. When Picture Mode is enabled, PC/AV and Picture Mode checks bring the scan to at most nine reads.")
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Read all 256 control codes") { store.refresh(deep: true) }
                            .disabled(store.hardwareCommandsPaused || store.busy || store.writing || store.pendingMode)
                        Text("Sends DDC queries. Do not scan a display that flashes or disconnects.")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .padding(.top, 10)
            }
            .font(.subheadline)
        }
    }

    private var modeConfirmation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keep this display mode?").font(.subheadline.weight(.medium))
            HStack {
                Text("Reverting in \(store.modeSeconds)s")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Revert") { store.revertMode() }
                Button("Keep") { store.keepMode() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .fixedSize(horizontal: false, vertical: true)
        .background(.orange.opacity(0.10))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Toggle("Show details", isOn: $showDetails).toggleStyle(.switch).controlSize(.mini).fixedSize()
            Spacer()
            if let display = store.selected {
                let count = display.selectableModes.filter(\.isHiDPI).count
                Text("\(count) HiDPI \(count == 1 ? "mode" : "modes")").foregroundStyle(.tertiary)
            }
            Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .font(.system(size: 10)).padding(.horizontal, 12).padding(.vertical, 10)
    }

    private func sectionTitle(_ title: String, detail: String?) -> some View {
        HStack {
            Text(title).font(.system(size: 10, weight: .semibold)).tracking(0.8)
            Spacer()
            if let detail { Text(detail).font(.system(size: 10)) }
        }
        .foregroundStyle(.secondary)
    }
}

private struct ValueSlider: View {
    let title: String
    let icon: String
    let current: Double
    let range: ClosedRange<Double>
    let detail: String
    var suffix = ""
    var step: Double = 1
    var commitWhileDragging = true
    let commit: (Double) -> Void
    @State private var value: Double
    @State private var isEditing = false

    init(title: String, icon: String, current: Double, range: ClosedRange<Double>, detail: String, suffix: String = "", step: Double = 1, commitWhileDragging: Bool = true, commit: @escaping (Double) -> Void) {
        self.title = title
        self.icon = icon
        self.current = current
        self.range = range
        self.detail = detail
        self.suffix = suffix
        self.step = step
        self.commitWhileDragging = commitWhileDragging
        self.commit = commit
        _value = State(initialValue: current)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Image(systemName: icon).foregroundStyle(.secondary).frame(width: 16)
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int(value.rounded()))\(suffix)")
                    .font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
            }
            AbsoluteSlider(value: $value, isEditing: $isEditing, range: range, step: step,
                           label: title, detail: detail, commitWhileDragging: commitWhileDragging, commit: commit)
                .frame(height: 16)

        }
        .onChange(of: current) { if !isEditing { value = $0 } }
    }
}
