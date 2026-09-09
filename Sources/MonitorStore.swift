import AppKit
import Combine
import ServiceManagement
import UniformTypeIdentifiers

@MainActor final class MonitorStore: ObservableObject {
    @Published var displays: [DisplayInfo] = []
    @Published var selectedID: UInt32 = 0
    @Published var features: [VCPFeature] = []
    @Published var capabilities = ""
    @Published var busy = false
    @Published private(set) var hardwareCommandsPaused = false
    @Published private(set) var writing = false
    @Published private(set) var pendingValues: [UInt8: UInt16] = [:]
    @Published private(set) var controlLimits: [UInt8: UInt16] = [:]
    @Published var message = "Reading connected displays…"
    @Published var lastScan: Date?
    @Published var dimming: Double = 1
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var pendingMode = false
    @Published var modeSeconds = 0
    @Published var edidSummary = ""
    @Published var ddcAvailable = false
    var selected: DisplayInfo? { displays.first { $0.id == selectedID } }
    var usesSamsungControls: Bool { selected?.isSamsungG91SD == true }
    var canResumeHardwareCommands: Bool {
        hardwareCommandsPaused && !busy && !writing && !pendingMode && !displays.isEmpty
            && (displays.allSatisfy { !$0.isSamsungG91SD }
                || (displays.count == 1 && selected.map { Hardware.canUseSamsungControls($0, preferences: preferences) } == true))
    }
    func value(for feature: VCPFeature) -> UInt16 { pendingValues[feature.code] ?? feature.current }
    var statusText: String { message == probe?.note && ddcAvailable ? "Settings up to date" : message }
    private var panelPixels: (Int, Int)? {
        guard let edid = probe?.edid, edid.checksumValid,
              let width = edid.preferredWidth, let height = edid.preferredHeight,
              width > 0, height > 0 else { return nil }
        return (width, height)
    }
    var panelHiDPIMode: DisplayModeInfo? {
        guard let (width, height) = panelPixels else { return nil }
        return selected?.selectableModes.first { $0.isSelectable && $0.isHiDPI && $0.pixelWidth == width && $0.pixelHeight == height }
    }
    var macOSHiDPIMode: DisplayModeInfo? {
        selected?.selectableModes.first { $0.isSelectable && $0.isHiDPI && $0.isNative }
    }
    var panelModeLabel: String {
        guard let (width, height) = panelPixels else { return "Preferred timing unavailable" }
        return "\(width) × \(height) · \(DisplayModeInfo.aspect(width: width, height: height))"
    }
    var macOSModeLabel: String {
        guard let mode = selected?.selectableModes.first(where: \.isNative) else { return "Native mode not marked" }
        return "\(mode.pixelWidth) × \(mode.pixelHeight) · \(DisplayModeInfo.aspect(width: mode.pixelWidth, height: mode.pixelHeight))"
    }
    var modeSummary: String {
        guard let mode = selected?.currentMode else { return "Current display mode unavailable" }
        return "Looks like \(mode.width) × \(mode.height) · \(mode.scaleLabel)\nRendering: \(mode.pixelLabel) · \(mode.aspectLabel)"
    }
    var modeWarning: String? {
        guard let current = selected?.currentMode else { return nil }
        if let (width, height) = panelPixels {
            if let native = selected?.selectableModes.first(where: \.isNative),
               abs(Double(native.pixelWidth) / Double(native.pixelHeight) - Double(width) / Double(height)) > 0.01 {
                return "The monitor reports \(DisplayModeInfo.aspect(width: width, height: height)), but macOS marks \(DisplayModeInfo.aspect(width: native.pixelWidth, height: native.pixelHeight)) as native. Try both HiDPI options and keep the one with correct proportions."
            }
            if abs(Double(current.width) / Double(current.height) - Double(width) / Double(height)) > 0.01 {
                return "This mode’s aspect ratio differs from the monitor’s preferred timing; the image may stretch or show black bars."
            }
        }
        return current.isHiDPI ? nil : "HiDPI is off. A 2× HiDPI mode renders sharper text with a larger workspace interface."
    }

    private var probe: MonitorProbe?
    private var observers: [NSObjectProtocol] = []
    private var refreshRequested = false
    private var dimPanel: NSPanel?
    private var modeTimer: Timer?
    private var previousMode: (UInt32, CGDisplayMode)?
    private var previewedMode: DisplayModeInfo?
    private let writer: (DisplayInfo, VCPFeature, UInt16) -> (VCPFeature?, String)
    private let preferences: UserDefaults
    private static let calibrationKeys: [UInt8: String] = [0x10: "brightnessLimit", 0x12: "contrastLimit"]
    private var writeTask: DispatchWorkItem?
    private var writeInFlight = false
    private var writeGeneration = 0
    private var resumeGeneration = 0

    init(snapshot: MonitorProbe? = nil,
         writer: @escaping (DisplayInfo, VCPFeature, UInt16) -> (VCPFeature?, String) = Hardware.write,
         preferences: UserDefaults = Hardware.commandPreferences) {
        self.writer = writer
        self.preferences = preferences
        if let snapshot {
            displays = [snapshot.display]
            selectedID = snapshot.display.id
            applyProbe(snapshot)
            return
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.screensChanged() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.restorePendingMode() }
        })
        refresh()
    }

    private func screensChanged() {
        displays = Hardware.displays()
        if !displays.contains(where: { $0.id == selectedID }) {
            selectedID = displays.first?.id ?? 0
            dimming = 1
            dimPanel?.close()
            dimPanel = nil
        } else if dimming < 1 { setDimming(dimming) }
        if !pendingMode { refresh() }
    }

    func selectDisplay(_ id: UInt32) {
        guard !busy, !writing, !pendingMode, selectedID != id else { return }
        dimPanel?.close()
        dimPanel = nil
        dimming = 1
        selectedID = id
        refresh()
    }

    func refresh(deep: Bool = false) {
        guard !pendingMode else { return }
        displays = Hardware.displays()
        if !displays.contains(where: { $0.id == selectedID }) { selectedID = displays.first?.id ?? 0 }
        guard !stopHardwareIfPaused() else { return }
        guard let display = selected else {
            applyProbe(nil)
            message = "Connect an external monitor to get started."
            return
        }
        if probe?.display.id != display.id || probe?.display.identity != display.identity {
            applyProbe(nil)
        }
        guard !busy, !writing else { refreshRequested = true; return }
        busy = true
        message = deep ? "Reading all 256 DDC feature addresses…" : "Reading monitor settings…"
        Hardware.queue.async {
            let result = Hardware.probe(display, deep: deep) { count in
                if deep && count % 8 == 0 {
                    DispatchQueue.main.async { self.message = "Reading DDC features: \(count) / 256…" }
                }
            }
            DispatchQueue.main.async {
                if self.selected?.id == display.id && self.selected?.identity == display.identity {
                    self.applyProbe(result)
                }
                self.finishOperation()
            }
        }
    }

    private func applyProbe(_ result: MonitorProbe?) {
        hardwareCommandsPaused = Hardware.commandsPaused(in: preferences)
        let result = hardwareCommandsPaused ? nil : result
        if result == nil {
            writeGeneration += 1
            writeTask?.cancel(); writeTask = nil
            pendingValues.removeAll()
            writeInFlight = false
            writing = false
        }
        probe = result
        features = result?.features ?? []
        controlLimits.removeAll()
        if let result {
            for feature in features where feature.isSlider && !result.display.isSamsungG91SD {
                guard let key = Self.calibrationKeys[feature.code],
                      let stored = preferences.object(forKey: "\(key).\(result.display.identity)") as? Int,
                      (1...Int(feature.maximum)).contains(stored) else { continue }
                controlLimits[feature.code] = UInt16(stored)
            }
        }
        capabilities = result?.capabilities ?? ""
        edidSummary = result == nil ? "" : result?.edid?.summary ?? "EDID unavailable."
        ddcAvailable = features.contains(where: \.isReadable)
        lastScan = result?.scannedAt
        message = hardwareCommandsPaused ? Hardware.pauseReason(in: preferences) ?? Hardware.pauseMessage : result?.note ?? ""
    }

    func pauseHardwareCommands() {
        resumeGeneration += 1
        preferences.removeObject(forKey: "hardwarePauseReason")
        preferences.set(true, forKey: Hardware.pauseKey)
        preferences.synchronize()
        _ = stopHardwareIfPaused()
    }

    func resumeHardwareCommands() {
        guard canResumeHardwareCommands else { return }
        busy = true
        message = "Resuming hardware controls…"
        resumeGeneration += 1
        let generation = resumeGeneration
        // Keep the pause set until any older hardware operation has finished.
        Hardware.queue.async {
            Hardware.resetSamsungSession()
            DispatchQueue.main.async {
                guard self.resumeGeneration == generation else { return }
                self.busy = false
                guard self.canResumeHardwareCommands else { self.message = Hardware.pauseMessage; return }
                self.preferences.removeObject(forKey: "hardwarePauseReason")
                self.preferences.removeObject(forKey: Hardware.pauseKey)
                self.preferences.set(false, forKey: Hardware.pauseKey)
                self.preferences.synchronize()
                self.hardwareCommandsPaused = false
                self.refresh()
            }
        }
    }

    private func stopHardwareIfPaused() -> Bool {
        guard Hardware.commandsPaused(in: preferences) else { return false }
        refreshRequested = false
        busy = false
        applyProbe(nil)
        return true
    }

    private func finishOperation() {
        busy = false
        if refreshRequested { refreshRequested = false; refresh() }
    }

    func allowedChoices(for feature: VCPFeature) -> [(UInt16, String)] {
        guard feature.isReadable else { return [] }
        if feature.code == 0x2D {
            guard let display = selected, Hardware.canUseSamsungPictureMode(display, preferences: preferences),
                  feature.type == 0, feature.maximum == 10, feature.current < 10 else { return [] }
            return Hardware.samsungPictureModeChoices
        }
        let advertised = Capabilities.features(capabilities)[feature.code] ?? []
        return feature.choices.filter { advertised.contains($0.0) }
    }

    func controlPercent(for feature: VCPFeature) -> Double {
        let maximum = controlLimits[feature.code] ?? feature.maximum
        guard maximum > 0 else { return 0 }
        return min(100, Double(value(for: feature)) * 100 / Double(maximum))
    }

    func osdOffset(for feature: VCPFeature) -> Int {
        usesSamsungControls && feature.maximum == 100 && [0x16, 0x18, 0x1A].contains(feature.code) ? 50 : 0
    }

    func setOSDValue(_ feature: VCPFeature, value: Double) {
        guard value.isFinite else { return }
        let raw = value + Double(osdOffset(for: feature))
        guard raw >= 0, raw <= Double(feature.maximum) else { return }
        set(feature, value: UInt16(raw.rounded()))
    }

    func setPercent(_ feature: VCPFeature, percent: Double) {
        guard percent.isFinite, (0...100).contains(percent),
              Self.calibrationKeys[feature.code] != nil,
              let live = features.first(where: { $0.code == feature.code && $0.isSlider }) else { return }
        let maximum = controlLimits[live.code] ?? live.maximum
        set(live, value: UInt16((percent * Double(maximum) / 100).rounded()))
    }

    func setControlLimit(_ feature: VCPFeature, limit: UInt16?) {
        guard !usesSamsungControls, !busy, !writing, !pendingMode, let display = selected,
              let prefix = Self.calibrationKeys[feature.code],
              let live = features.first(where: { $0.code == feature.code && $0.isSlider }) else { return }
        if let limit, !(1...live.maximum).contains(limit) { return }
        let key = "\(prefix).\(display.identity)"
        if let limit { preferences.set(Int(limit), forKey: key) }
        else { preferences.removeObject(forKey: key) }
        controlLimits[live.code] = limit
        message = "\(live.name) range saved. Move the \(live.name.lowercased()) slider to apply it."
    }

    func set(_ feature: VCPFeature, value: UInt16) {
        guard !stopHardwareIfPaused() else { return }
        guard !busy, !pendingMode, selected != nil,
              let live = features.first(where: { $0.code == feature.code }), live.isReadable else { return }
        if let display = selected, display.isSamsungG91SD {
            guard pendingValues[0x2D] == nil, live.code != 0x2D || !writing else { return }
            guard Hardware.canUseSamsungControls(display, preferences: preferences),
                  Hardware.samsungControlCodes.contains(live.code)
                    || (live.code == 0x2D && Hardware.canUseSamsungPictureMode(display, preferences: preferences)) else {
                message = "This Samsung control has not been enabled for this monitor."
                return
            }
        }
        guard (live.isSlider && value <= live.maximum) || allowedChoices(for: live).contains(where: { $0.0 == value }) else {
            message = "That setting is not a supported writable control."
            return
        }
        guard value <= (controlLimits[live.code] ?? UInt16.max) else {
            message = "That \(live.name.lowercased()) is outside the calibrated range."
            return
        }
        guard pendingValues[live.code] != value else { return }
        guard pendingValues[live.code] != nil || value != live.current else { return }
        pendingValues[live.code] = value
        writing = true
        if live.code == 0x2D, let name = allowedChoices(for: live).first(where: { $0.0 == value })?.1 {
            message = "Applying \(name)…"
        } else {
            message = controlLimits[live.code] != nil ? "Applying \(live.name.lowercased())…" : "Applying \(live.name): \(value)…"
        }
        scheduleWrite()
    }

    private func scheduleWrite() {
        guard !writeInFlight, writeTask == nil else { return }
        let task = DispatchWorkItem { [weak self] in self?.flushWrite() }
        writeTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: task)
    }

    private func flushWrite() {
        writeTask = nil
        guard !stopHardwareIfPaused() else { return }
        guard let display = selected, let code = pendingValues.keys.sorted().first,
              let value = pendingValues[code], let live = features.first(where: { $0.code == code }) else {
            pendingValues.removeAll()
            writing = false
            finishOperation()
            return
        }
        writeInFlight = true
        let generation = writeGeneration
        let writer = self.writer
        // UserDefaults is thread-safe; recheck the pause when queued work begins.
        nonisolated(unsafe) let commandPreferences = preferences
        Hardware.queue.async {
            let (readback, status) = Hardware.commandsPaused(in: commandPreferences)
                ? (nil, Hardware.pauseMessage) : writer(display, live, value)
            DispatchQueue.main.async {
                guard !self.stopHardwareIfPaused() else { return }
                guard self.writeGeneration == generation,
                      self.selected?.id == display.id, self.selected?.identity == display.identity else { return }
                self.writeInFlight = false
                if let readback, let index = self.features.firstIndex(where: { $0.code == code }) {
                    self.features[index] = readback
                    self.probe?.features = self.features
                }
                if self.pendingValues[code] == value {
                    self.pendingValues.removeValue(forKey: code)
                    self.message = self.controlLimits[code] != nil && readback?.current == value
                        ? "\(live.name) command confirmed." : status
                }
                // A preset can replace several picture values. Read them before accepting another write.
                if display.isSamsungG91SD && code == 0x2D { self.refreshRequested = true }
                if self.pendingValues.isEmpty {
                    self.writing = false
                    self.finishOperation()
                } else {
                    self.scheduleWrite()
                }
            }
        }
    }

    func setDimming(_ value: Double) {
        guard value.isFinite else { return }
        dimming = min(1, max(0.2, value))
        guard dimming < 1, let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == selectedID
        }) else {
            dimPanel?.close(); dimPanel = nil
            return
        }
        if dimPanel == nil {
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.backgroundColor = .black
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            dimPanel = panel
        }
        dimPanel?.setFrame(screen.frame, display: true)
        dimPanel?.alphaValue = 1 - dimming
        dimPanel?.orderFrontRegardless()
    }

    func setMode(_ id: Int32) {
        guard !busy, !writing, !pendingMode, let display = selected, id != display.currentModeID,
              let requested = display.selectableModes.first(where: { $0.id == id && $0.isSelectable }),
              let original = CGDisplayCopyDisplayMode(display.id),
              let modes = CGDisplayCopyAllDisplayModes(display.id, [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary) as? [CGDisplayMode],
              let mode = modes.first(where: { $0.ioDisplayModeID == id && Self.matches($0, requested) }) else { return }
        // Temporary configuration asks WindowServer to restore it if this app exits.
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { message = "Could not begin the display change."; return }
        guard CGConfigureDisplayWithDisplayMode(config, display.id, mode, nil) == .success else {
            CGCancelDisplayConfiguration(config); message = "macOS rejected that display mode."; return
        }
        previousMode = (display.id, original)
        pendingMode = true
        let result = CGCompleteDisplayConfiguration(config, .forAppOnly)
        guard result == .success else {
            pendingMode = false; previousMode = nil; message = "macOS could not apply that display mode (\(result.rawValue))."; return
        }
        displays = Hardware.displays()
        guard let applied = CGDisplayCopyDisplayMode(display.id), Self.matches(applied, requested) else {
            revertMode()
            message = "macOS applied a different mode. The previous mode was requested again."
            return
        }
        previewedMode = requested
        modeSeconds = 15
        message = "Keep this display mode? Reverting in 15 seconds."
        let deadline = Date().addingTimeInterval(15)
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.modeSeconds = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
                if self.modeSeconds <= 0 { self.revertMode() }
            }
        }
        modeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func keepMode() {
        guard pendingMode, let (id, _) = previousMode, let mode = CGDisplayCopyDisplayMode(id),
              let previewedMode, Self.matches(mode, previewedMode) else {
            if pendingMode { revertMode() }
            return
        }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { message = "Could not keep the display mode."; return }
        guard CGConfigureDisplayWithDisplayMode(config, id, mode, nil) == .success else { CGCancelDisplayConfiguration(config); return }
        guard CGCompleteDisplayConfiguration(config, .forSession) == .success else { message = "Could not keep the display mode; it will revert."; return }
        modeTimer?.invalidate(); modeTimer = nil; previousMode = nil; self.previewedMode = nil; pendingMode = false
        message = "\(previewedMode.label) verified and kept for this login session."
        displays = Hardware.displays()
    }

    private static func matches(_ mode: CGDisplayMode, _ requested: DisplayModeInfo) -> Bool {
        mode.width == requested.width && mode.height == requested.height &&
        mode.pixelWidth == requested.pixelWidth && mode.pixelHeight == requested.pixelHeight &&
        abs(mode.refreshRate - requested.refreshRate) < 0.01 && mode.ioFlags == requested.ioFlags
    }

    private func restorePendingMode() {
        if let (id, mode) = previousMode { _ = CGDisplaySetDisplayMode(id, mode, nil) }
    }

    func revertMode() {
        modeTimer?.invalidate(); modeTimer = nil
        guard let (id, mode) = previousMode else { pendingMode = false; return }
        let result = CGDisplaySetDisplayMode(id, mode, nil)
        previousMode = nil; previewedMode = nil; pendingMode = false
        displays = Hardware.displays()
        message = result == .success ? "Previous display mode restored." : "Could not restore the mode. Open macOS Displays settings (error \(result.rawValue))."
    }

    func exportReport() {
        guard !busy, !writing, !pendingMode else { return }
        guard var report = probe else { message = "Scan the monitor before exporting a report."; return }
        if let selected { report.display = selected }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Monitor-diagnostics.json"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(report).write(to: url, options: .atomic)
            message = "Report saved to \(url.lastPathComponent)."
        } catch { message = "Could not save the report: \(error.localizedDescription)" }
    }

    func openDisplaySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") { NSWorkspace.shared.open(url) }
    }

    func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            message = SMAppService.mainApp.status == .requiresApproval ? "Enable Monitor Bar in System Settings → General → Login Items." : (launchAtLogin ? "Monitor Bar will launch at login." : "Launch at login is off.")
        } catch { message = "Could not update launch at login: \(error.localizedDescription)" }
    }
}
