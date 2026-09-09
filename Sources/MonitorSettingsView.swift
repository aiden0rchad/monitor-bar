import AppKit
import SwiftUI

@MainActor
struct MonitorSettingsView: View {
    @ObservedObject var store: MonitorStore
    @State private var section: SettingsSection = .picture
    @State private var diagnosticsExpanded = true
    @State private var modesExpanded = false
    @State private var presetEditorIsPresented = false
    @State private var editingPreset: HardwarePreset?
    @State private var presetName = ""
    @State private var deletingPreset: HardwarePreset?

    private enum SettingsSection: String, CaseIterable, Identifiable {
        case picture = "Picture", presets = "Presets", information = "Information", app = "App"
        var id: Self { self }
        var icon: String {
            switch self {
            case .picture: return "slider.horizontal.3"
            case .presets: return "bookmark"
            case .information: return "info.circle"
            case .app: return "gearshape"
            }
        }
        var subtitle: String {
            switch self {
            case .picture: return "Fine-tune the image on your monitor."
            case .presets: return "Save hardware settings for this monitor."
            case .information: return "Display modes, hardware replies, and connection details."
            case .app: return "Startup and hardware control preferences."
            }
        }
    }

    init(store: MonitorStore, previewPresets: Bool = false) {
        self.store = store
        _section = State(initialValue: previewPresets ? .presets : .picture)
    }

    private var advancedControls: [(UInt8, String)] {
        [(0x0A, "Eye Saver Mode"), (0x14, "Color Tone"), (0x2F, "Black Equalizer")]
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 5) {
                ForEach(SettingsSection.allCases) { item in
                    Button { section = item } label: {
                        Label(item.rawValue, systemImage: item.icon)
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.vertical, 9)
                            .foregroundStyle(section == item ? Color.white : Color.primary)
                            .background(section == item ? Color.accentColor : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(section == item ? .isSelected : [])
                }
                Spacer()
            }
            .padding(12).padding(.top, 8)
            .frame(width: 165)
            .frame(maxHeight: .infinity)
            .background(.quaternary.opacity(0.25))
            Divider()
            VStack(spacing: 0) {
                displayHeader
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(section.rawValue).font(.title2.weight(.semibold))
                            Text(section.subtitle).foregroundStyle(.secondary)
                        }
                        switch section {
                        case .picture:
                            if store.selected != nil { pictureControls.id(store.selected?.identity) }
                            else { Text("Connect an external monitor, then refresh.").foregroundStyle(.secondary) }
                        case .presets: presetControls
                        case .information:
                            if store.selected != nil { diagnostics }
                            else { Text("No external display is connected.").foregroundStyle(.secondary) }
                        case .app: appControls
                        }
                    }
                    .frame(maxWidth: 620, alignment: .leading)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                statusFooter
            }
        }
        .frame(minWidth: 700, minHeight: 540)
        .onAppear {
            if store.lastScan == nil && !store.busy { store.refresh() }
        }
        .onChange(of: store.selected?.identity) { _ in
            presetEditorIsPresented = false
            editingPreset = nil
            deletingPreset = nil
        }
        .sheet(isPresented: $presetEditorIsPresented) { presetEditor }
        .alert("Delete preset?", isPresented: Binding(
            get: { deletingPreset != nil }, set: { if !$0 { deletingPreset = nil } }), presenting: deletingPreset) { preset in
            Button("Delete", role: .destructive) { store.deleteHardwarePreset(preset) }
            Button("Cancel", role: .cancel) {}
        } message: { preset in
            Text("Delete “\(preset.name)” from your saved presets? Your monitor’s settings stay unchanged.")
        }
    }

    private var presetControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            if store.usesSamsungControls {
                if let error = store.presetStorageError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.secondary)
                }
                HStack(alignment: .top) {
                    Text("Save the monitor’s current picture and volume settings, then restore them together.")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Button("Save current…") {
                        editingPreset = nil
                        presetName = ""
                        presetEditorIsPresented = true
                    }
                    .disabled(!store.canSaveHardwarePreset)
                }
                let presets = store.savedPresets.filter { $0.displayIdentity == store.selected?.identity }
                if presets.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "bookmark").font(.system(size: 28, weight: .light))
                        Text("No saved presets").font(.headline)
                        Text("Set up the image you like, then save it here.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 26)
                } else {
                    VStack(spacing: 10) {
                        ForEach(presets) { preset in
                            GroupBox {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(preset.name).font(.headline).lineLimit(2)
                                        Text("\(preset.values.count) hardware settings")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 10)
                                    Button("Apply") { store.applyHardwarePreset(preset) }
                                        .disabled(!store.canApplyHardwarePreset(preset))
                                        .accessibilityLabel("Apply \(preset.name)")
                                    Menu {
                                        Button("Rename…") {
                                            editingPreset = preset
                                            presetName = preset.name
                                            presetEditorIsPresented = true
                                        }
                                        Button("Delete…", role: .destructive) { deletingPreset = preset }
                                    } label: { Image(systemName: "ellipsis") }
                                    .menuStyle(.borderlessButton).fixedSize()
                                    .disabled(store.busy || store.writing || store.pendingMode)
                                    .accessibilityLabel("Manage \(preset.name)")
                                }
                                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                Text("Each preset belongs to this monitor. Only verified controls are saved; display resolution and connection settings stay separate.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Label("Hardware presets are available for verified Samsung G91SD controls.", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var presetEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(editingPreset == nil ? "Save current settings" : "Rename preset").font(.headline)
            TextField("Preset name", text: $presetName)
                .textFieldStyle(.roundedBorder)
            Text(editingPreset == nil ? "Monitor Bar reads the current hardware values before saving." : "Choose a name with up to 64 characters.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { presetEditorIsPresented = false }.keyboardShortcut(.cancelAction)
                Button(editingPreset == nil ? "Save" : "Rename") {
                    if let preset = editingPreset { store.renameHardwarePreset(preset, to: presetName) }
                    else { store.saveHardwarePreset(named: presetName) }
                    presetEditorIsPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(HardwarePreset.normalizedName(presetName) == nil || store.busy || store.writing || store.pendingMode
                          || (editingPreset == nil && !store.canSaveHardwarePreset))
            }
        }
        .padding(24).frame(width: 360)
    }

    private var displayHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "display").font(.system(size: 24, weight: .light)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                if store.displays.count > 1 {
                    Picker("Monitor", selection: Binding(get: { store.selectedID }, set: { store.selectDisplay($0) })) {
                        ForEach(store.displays) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden().fixedSize()
                    .disabled(store.busy || store.writing || store.pendingMode)
                } else {
                    Text(store.selected?.name ?? "No external display").font(.headline)
                }
                Text(store.usesSamsungControls ? "HDMI hardware controls" : "External display settings")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if store.busy || store.writing {
                ProgressView().controlSize(.small).accessibilityLabel(store.statusText)
            }
            Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .help("Refresh display settings").accessibilityLabel("Refresh display settings")
                .disabled(store.busy || store.writing || store.pendingMode)
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
    }

    private var pictureControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            if store.usesSamsungControls {
                if let eye = store.features.first(where: { $0.code == 0x0A && $0.isReadable }), eye.current != 0 {
                    Label("Eye Saver Mode is on. Turn it off to adjust brightness, Picture Mode, Color Tone, white balance, and Black Equalizer.", systemImage: "info.circle")
                        .font(.callout).foregroundStyle(.secondary)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        if let sharpness = store.features.first(where: { $0.code == 0x87 && $0.isSlider }) {
                            HardwareSlider(store: store, feature: sharpness)
                        }
                        ForEach(advancedControls, id: \.0) { code, name in
                            if store.canUseAdvancedControl(code) {
                                if let feature = store.features.first(where: { $0.code == code && $0.isReadable }) {
                                    if code == 0x2F { HardwareSlider(store: store, feature: feature) }
                                    else { HardwarePicker(store: store, feature: feature) }
                                } else {
                                    HStack {
                                        Text(name)
                                        Spacer()
                                        Text("Unavailable").foregroundStyle(.secondary)
                                    }.font(.callout)
                                }
                            }
                        }
                        let unverified = advancedControls.filter { !store.canUseAdvancedControl($0.0) }.map(\.1)
                        if !unverified.isEmpty {
                            Text("Still being verified for this monitor: \(unverified.joined(separator: ", ")).")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                } label: { Label("Image", systemImage: "photo") }
                let balance = store.features.filter { [0x16, 0x18, 0x1A].contains($0.code) && $0.isSlider }
                if !balance.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(balance) { HardwareSlider(store: store, feature: $0) }
                            Text("Values match the monitor’s white balance controls.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(8)
                    } label: { Label("White balance", systemImage: "paintpalette") }
                }
            } else {
                let sliders = store.features.filter { ![0x10, 0x12, 0x62].contains($0.code) && $0.isSlider }
                let choices = store.features.filter { $0.isReadable && !store.allowedChoices(for: $0).isEmpty }
                if !sliders.isEmpty || !choices.isEmpty {
                    GroupBox {
                        VStack(spacing: 16) {
                            ForEach(sliders) { HardwareSlider(store: store, feature: $0) }
                            ForEach(choices) { HardwarePicker(store: store, feature: $0) }
                        }.padding(8)
                    } label: { Label("Hardware controls", systemImage: "slider.horizontal.3") }
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(store.features.filter { [0x10, 0x12].contains($0.code) && $0.isSlider }) {
                            controlCalibration($0)
                        }
                        Text("Adjust a control’s range if its brightness rises and falls as you move the slider.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(8)
                } label: { Label("Calibration", systemImage: "dial.low") }
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        ValueSlider(title: "Image brightness", icon: "moon", current: store.dimming * 100,
                                    range: 20...100, detail: "Darkens the image; does not change the backlight.", suffix: "%") {
                            store.setDimming($0 / 100)
                        }
                        Text("Darkens the image with an overlay. This does not change the monitor’s backlight.")
                            .font(.caption).foregroundStyle(.secondary)
                        if store.dimming < 1 {
                            Button("Restore image brightness") { store.setDimming(1) }.controlSize(.small)
                        }
                    }.padding(8).disabled(store.busy || store.writing || store.pendingMode)
                } label: { Label("Software dimming", systemImage: "moon") }
            }
        }
    }

    private var appControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Launch Monitor Bar at login", isOn: Binding(
                        get: { store.launchAtLogin }, set: { _ in store.toggleLaunchAtLogin() }))
                    Text("Monitor Bar stays in the menu bar. Close this window to return to quick controls.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(8)
            } label: { Label("General", systemImage: "gearshape") }
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text(store.hardwareCommandsPaused ? "Hardware controls are paused." : "Hardware controls are active.")
                    Text("Pausing stops hardware queries and changes. Your monitor keeps its current settings.")
                        .font(.caption).foregroundStyle(.secondary)
                    if store.hardwareCommandsPaused {
                        Button("Resume hardware controls", action: store.resumeHardwareCommands)
                            .disabled(!store.canResumeHardwareCommands || store.busy || store.writing || store.pendingMode)
                    } else {
                        Button("Pause hardware controls", action: store.pauseHardwareCommands)
                            .disabled(store.pendingMode)
                    }
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            } label: { Label("Hardware connection", systemImage: "cable.connector") }
            HStack {
                Button("Export monitor report…", action: store.exportReport)
                    .disabled(store.busy || store.writing || store.pendingMode)
                Button("Open macOS Displays", action: store.openDisplaySettings)
            }
        }
    }

    @ViewBuilder
    private var statusFooter: some View {
        if store.pendingMode {
            Divider()
            HStack {
                Text("Reverting display mode in \(store.modeSeconds)s").font(.caption)
                Spacer()
                Button("Revert", action: store.revertMode)
                Button("Keep", action: store.keepMode).buttonStyle(.borderedProminent)
            }.padding(16).background(.orange.opacity(0.10))
        } else if !store.message.isEmpty || store.hardwareCommandsPaused {
            Divider()
            Label(store.hardwareCommandsPaused ? "Hardware controls paused. Resume in App settings." : store.statusText,
                  systemImage: store.hardwareCommandsPaused ? "pause.circle" : "info.circle")
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
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

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                                Text(store.controlName(for: feature))
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
                        Text("Only enabled controls are queried. Additional features are verified for this monitor before use.")
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

}

@MainActor
struct HardwareSlider: View {
    @ObservedObject var store: MonitorStore
    let feature: VCPFeature

    var body: some View {
        slider.disabled(!store.isWritableSlider(feature) || store.hardwareCommandsPaused || store.busy || store.pendingMode || (store.usesSamsungControls && store.writing))
    }

    @ViewBuilder
    private var slider: some View {
        if store.usesSamsungControls {
            let offset = store.osdOffset(for: feature)
            let title = offset == 50 ? store.controlName(for: feature).replacingOccurrences(of: " gain", with: "") : store.controlName(for: feature)
            let icon = [UInt8(0x10): "sun.max", 0x12: "circle.lefthalf.filled", 0x87: "circle.lefthalf.striped.horizontal", 0x62: "speaker.wave.2"][feature.code] ?? "circle.fill"
            ValueSlider(title: title, icon: icon,
                        current: Double(Int(store.value(for: feature)) - offset),
                        range: Double(-offset)...Double(Int(feature.maximum) - offset),
                        detail: "Release to apply. HDMI value: \(feature.current) / \(feature.maximum).",
                        commitWhileDragging: false) { store.setOSDValue(feature, value: $0) }
        } else if [0x10, 0x12].contains(feature.code) {
            let limit = store.controlLimits[feature.code] ?? feature.maximum
            ValueSlider(title: store.controlName(for: feature), icon: feature.code == 0x10 ? "sun.max" : "circle.lefthalf.filled",
                        current: store.controlPercent(for: feature),
                        range: 0...100,
                        detail: "\(store.controlName(for: feature)) 0–100% uses hardware values 0–\(limit). Monitor reports \(feature.current) / \(feature.maximum).",
                        suffix: "%", step: 100 / Double(limit)) { store.setPercent(feature, percent: $0) }
        } else if feature.code == 0x0C,
           let increment = store.features.first(where: { $0.code == 0x0B && $0.isReadable })?.current,
           (1...1000).contains(increment) {
            let kelvin = 3000 + Int(store.value(for: feature)) * Int(increment)
            ValueSlider(title: store.controlName(for: feature), icon: "thermometer.medium", current: Double(kelvin),
                        range: 3000...Double(3000 + Int(feature.maximum) * Int(increment)),
                        detail: "Monitor reports \(feature.current) / \(feature.maximum)",
                        suffix: " K", step: Double(increment)) {
                store.set(feature, value: UInt16((($0 - 3000) / Double(increment)).rounded()))
            }
        } else {
            ValueSlider(
                title: store.controlName(for: feature),
                icon: feature.code == 0x62 ? "speaker.wave.2" : "circle.lefthalf.filled",
                current: Double(store.value(for: feature)),
                range: 0...Double(feature.maximum),
                detail: "Monitor reports \(feature.current) / \(feature.maximum)",
                suffix: feature.maximum == 100 ? "%" : ""
            ) { value in store.set(feature, value: UInt16(value.rounded())) }
        }
    }

}

@MainActor
struct HardwarePicker: View {
    @ObservedObject var store: MonitorStore
    let feature: VCPFeature
    @State private var pendingValue: UInt16?

    var body: some View {
        let choices = store.allowedChoices(for: feature)
        Picker(store.controlName(for: feature), selection: Binding(get: { store.value(for: feature) }, set: { value in
            guard value != feature.current else { return }
            if [0x60, 0xD6].contains(feature.code) { pendingValue = value }
            else { store.set(feature, value: value) }
        })) {
            if !choices.contains(where: { $0.0 == feature.current }) {
                Text("Current: \(feature.current)").tag(feature.current)
            }
            ForEach(choices, id: \.0) { Text($0.1).tag($0.0) }
        }
        .disabled(choices.isEmpty || store.hardwareCommandsPaused || store.busy || store.writing || store.pendingMode)
        .alert("Change \(store.controlName(for: feature).lowercased())?", isPresented: Binding(
            get: { pendingValue != nil }, set: { if !$0 { pendingValue = nil } }), presenting: pendingValue) { value in
            Button("Apply \(choices.first { $0.0 == value }?.1 ?? String(value))") { store.set(feature, value: value) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This may disconnect or blank the display. You may need the monitor’s physical controls to restore it.")
        }
    }
}

struct ValueSlider: View {
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
