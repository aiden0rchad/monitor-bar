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
final class MonitorSettingsWindow {
    static let shared = MonitorSettingsWindow()
    private var controller: NSWindowController?

    private init() {}

    func show(store: MonitorStore) {
        if controller == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "Monitor Settings"
            window.contentViewController = NSHostingController(rootView: MonitorSettingsView(store: store))
            window.contentMinSize = NSSize(width: 700, height: 540)
            window.setContentSize(NSSize(width: 760, height: 620))
            window.tabbingMode = .disallowed
            window.isReleasedWhenClosed = false
            if !window.setFrameUsingName("MonitorSettings") { window.center() }
            window.setFrameAutosaveName("MonitorSettings")
            controller = NSWindowController(window: window)
        }
        controller?.showWindow(nil)
        if controller?.window?.isMiniaturized == true { controller?.window?.deminiaturize(nil) }
        controller?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
struct MonitorPanel: View {
    @ObservedObject var store: MonitorStore
    @State private var draftMode: DisplayModeInfo?

    init(store: MonitorStore, previewSelection: DisplayModeInfo? = nil) {
        self.store = store
        _draftMode = State(initialValue: previewSelection)
    }

    private var mainFeatures: [VCPFeature] {
        store.features.filter { [0x10, 0x12, 0x62].contains($0.code) && $0.isSlider }
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
                               let pictureMode = store.features.first(where: { $0.code == 0x2D }) {
                                if pictureMode.isReadable && !store.allowedChoices(for: pictureMode).isEmpty {
                                    pictureModeControl(pictureMode)
                                } else {
                                    HStack {
                                        Label("Picture Mode", systemImage: "photo")
                                        Spacer()
                                        Text("Unavailable").foregroundStyle(.secondary)
                                    }.font(.system(size: 12))
                                }
                            }
                            if store.usesSamsungControls,
                               let eye = store.features.first(where: { $0.code == 0x0A && $0.isReadable }), eye.current != 0 {
                                Text("Eye Saver Mode is on; some picture controls are unavailable.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            resolutionControls(display)
                        }
                        .padding(14)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
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
            } else if let mode = draftMode, let display = store.selected, mode != display.currentMode {
                HStack {
                    Text("Not applied").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { draftMode = nil }
                    Button("Preview changes") {
                        store.setMode(mode, on: display)
                        draftMode = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!mode.isSelectable)
                }
                .controlSize(.small)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .disabled(store.busy || store.writing)
                .help("Preview this combination for 15 seconds. Keep it, or it reverts automatically.")
            } else {
                footer
            }
        }
        .frame(width: 420, height: 560)
        .background(.regularMaterial)
        .onAppear {
            if store.lastScan == nil && !store.busy { store.refresh() }
        }
        .onChange(of: store.selectedID) { _ in draftMode = nil }
        .onChange(of: store.selected?.identity) { _ in draftMode = nil }
        .onChange(of: store.selected?.currentMode) { _ in draftMode = nil }
        .onChange(of: store.selected?.modes) { _ in draftMode = nil }
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
            Button(action: openSettings) { Image(systemName: "gearshape") }
                .keyboardShortcut(",", modifiers: .command)
                .help("Open Monitor Settings").accessibilityLabel("Open Monitor Settings")
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
                    HardwareSlider(store: store, feature: feature)
                } else {
                    HStack {
                        Label(code == 0x10 ? "Brightness" : "Contrast", systemImage: code == 0x10 ? "sun.max" : "circle.lefthalf.filled")
                        Spacer()
                        Text(store.hardwareCommandsPaused ? "Paused" : store.busy ? "Reading…" : store.features.contains(where: { $0.code == code && $0.status == "unavailable" }) ? "Unavailable" : "Not supported").foregroundStyle(.secondary)
                    }.font(.system(size: 12)).frame(height: 42)
                }
            }
            if let volume = mainFeatures.first(where: { $0.code == 0x62 }) { HardwareSlider(store: store, feature: volume) }
        }
        .disabled(store.hardwareCommandsPaused || store.busy || store.pendingMode || (store.usesSamsungControls && store.writing) || store.pendingValues[0x2D] != nil)
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
        let options = DisplayModeOptions(display: display)
        let selection = draftMode ?? display.currentMode
        return VStack(alignment: .leading, spacing: 8) {
            if let mode = selection {
                HStack(spacing: 7) {
                    Image(systemName: "rectangle.inset.filled").foregroundStyle(.secondary).frame(width: 18)
                    Text("Resolution").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Picker("Resolution", selection: Binding(get: { mode.resolution }, set: { size in
                        draftMode = options.preferredMode(resolution: size, near: mode)
                    })) {
                        ForEach(options.resolutions, id: \.self) { size in
                            Text(size.label).tag(size)
                                .disabled(!options.availableModes.contains { $0.resolution == size })
                        }
                    }
                    .labelsHidden().controlSize(.small).frame(maxWidth: 220, alignment: .trailing)
                }
                HStack(spacing: 7) {
                    Image(systemName: "textformat.size").foregroundStyle(.secondary).frame(width: 18)
                    Text("Scaling").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Picker("Scaling", selection: Binding(get: { mode.renderingSize }, set: { size in
                        draftMode = options.preferredMode(resolution: mode.resolution, rendering: size, near: mode)
                    })) {
                        ForEach(options.renderingSizes(for: mode.resolution), id: \.self) { size in
                            let candidate = options.preferredMode(resolution: mode.resolution, rendering: size, near: mode)
                            Text(options.scalingLabel(for: candidate ?? mode)).tag(size)
                                .disabled(candidate == nil)
                        }
                    }
                    .labelsHidden().controlSize(.small).frame(maxWidth: 220, alignment: .trailing)
                    .disabled(options.renderingSizes(for: mode.resolution).count < 2)
                }
                .help("HiDPI renders more pixels for sharper text. Available scaling depends on the selected resolution.")
                HStack(spacing: 7) {
                    Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.secondary).frame(width: 18)
                    Text("Refresh rate").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Picker("Refresh rate", selection: Binding(get: { mode.refreshRate }, set: { rate in
                        draftMode = options.preferredMode(resolution: mode.resolution, rendering: mode.renderingSize,
                                                          rate: rate, near: mode)
                    })) {
                        ForEach(options.refreshModes(for: mode), id: \.refreshRate) { candidate in
                            Text(options.refreshLabel(for: candidate)).tag(candidate.refreshRate)
                                .disabled(!candidate.isSelectable)
                        }
                    }
                    .labelsHidden().controlSize(.small).frame(maxWidth: 220, alignment: .trailing)
                    .disabled(options.refreshModes(for: mode).count < 2)
                }
                Text("Rendering \(mode.renderingSize.label) · \(mode.aspectLabel)")
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 25)
            } else {
                Text("Current display mode unavailable").font(.caption).foregroundStyle(.secondary)
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
            if let mode = selection, mode != display.currentMode {
                if let current = display.currentMode {
                    Text("Current: \(current.resolution.label) · \(current.scalingChoiceLabel) · \(current.refreshLabel)")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
        .disabled(store.busy || store.writing || store.pendingMode)
    }

    private func hiDPIButton(_ mode: DisplayModeInfo, title: String) -> some View {
        Button { draftMode = mode } label: {
            Label(title, systemImage: mode.id == (draftMode?.id ?? store.selected?.currentModeID) ? "checkmark" : "sparkles")
        }
        .controlSize(.small)
        .disabled(store.busy || store.writing || store.pendingMode || mode.id == (draftMode?.id ?? store.selected?.currentModeID))
        .help("Choose \(mode.width) × \(mode.height) workspace, \(mode.pixelLabel), then click Preview changes.")
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
            Button(action: openSettings) {
                Label("Monitor settings…", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.plain)
            .help("Open picture controls, monitor information, and app settings")
            Spacer()
            if let display = store.selected {
                Text(display.currentMode?.refreshLabel ?? "").foregroundStyle(.tertiary)
            }
            Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .font(.system(size: 10)).padding(.horizontal, 12).padding(.vertical, 10)
    }

    private func openSettings() {
        MonitorSettingsWindow.shared.show(store: store)
    }
}
