import Foundation

private final class PresetMonitor {
    let lock = NSLock()
    var snapshot: MonitorProbe
    var reads = 0
    var writes: [UInt8] = []
    var failCode: UInt8?
    var disconnectAfterWrite = false
    var connected = true
    var changeRangeAfterMode = false
    var onRead: (() -> Void)?

    init(_ snapshot: MonitorProbe) { self.snapshot = snapshot }

    func read(_ display: DisplayInfo) -> MonitorProbe {
        lock.lock(); defer { lock.unlock() }
        reads += 1
        onRead?()
        return snapshot
    }

    func isConnected(_ display: DisplayInfo) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return connected
    }

    func write(_ display: DisplayInfo, _ feature: VCPFeature, _ value: UInt16) -> (VCPFeature?, String) {
        lock.lock(); defer { lock.unlock() }
        writes.append(feature.code)
        if disconnectAfterWrite { connected = false }
        if failCode == feature.code { return (nil, "Synthetic write failure.") }
        var updated = feature
        updated.current = value
        snapshot.features[snapshot.features.firstIndex { $0.code == feature.code }!] = updated
        if feature.code == 0x2D {
            // Picture Mode replaces brightness. The next write must use a fresh snapshot.
            let index = snapshot.features.firstIndex { $0.code == 0x10 }!
            snapshot.features[index] = VCPFeature(code: 0x10, current: 8,
                maximum: changeRangeAfterMode ? 40 : 50, type: 0, status: "ok")
        }
        return (updated, "Confirmed.")
    }
}

@main struct PresetOperationTests {
    static func snapshot() -> MonitorProbe {
        let display = DisplayInfo(id: 42, name: "Test Samsung", vendor: 0x4C2D, product: 0x778D,
            serial: 1234, builtIn: false, widthMM: 1000, heightMM: 300, rotation: 0, currentModeID: 0, modes: [])
        return MonitorProbe(display: display, features: [
            VCPFeature(code: 0x2D, current: 2, maximum: 10, type: 0, status: "ok"),
            VCPFeature(code: 0x14, current: 2, maximum: 4, type: 0, status: "ok"),
            VCPFeature(code: 0x10, current: 14, maximum: 50, type: 0, status: "ok"),
            VCPFeature(code: 0x2F, current: 5, maximum: 10, type: 0, status: "ok"),
            VCPFeature(code: 0x0A, current: 0, maximum: 2, type: 0, status: "ok"),
            VCPFeature(code: 0xE2, current: 0x3500, maximum: 127, type: 0, status: "ok")])
    }

    @MainActor static func eventually(_ store: MonitorStore) async {
        let deadline = Date().addingTimeInterval(4)
        while store.busy {
            precondition(Date() < deadline, "Preset operation timed out")
            try! await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    @MainActor static func waitForQueue(_ signal: DispatchSemaphore) async {
        let reached: Bool = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: signal.wait(timeout: .now() + 4) == .success)
            }
        }
        precondition(reached, "Preset queue did not reach the test gate")
    }

    @MainActor static func main() async throws {
        let suite = "MonitorBar.PresetOperationTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let original = snapshot()
        func reset() {
            preferences.removePersistentDomain(forName: suite)
            preferences.set(true, forKey: Hardware.samsungEnableKey(original.display))
            preferences.set(true, forKey: Hardware.samsungPictureModeEnableKey(original.display))
            preferences.set(true, forKey: Hardware.samsungPIPReadEnableKey(original.display))
            for code: UInt8 in [0x14, 0x2F] {
                preferences.set(true, forKey: Hardware.samsungAdvancedEnableKey(original.display, code: code))
            }
        }
        @MainActor func store(_ monitor: PresetMonitor) -> MonitorStore {
            MonitorStore(snapshot: original, writer: monitor.write, preferences: preferences,
                         presetReader: monitor.read, presetDisplayConnected: monitor.isConnected)
        }
        let preset = try HardwarePreset(name: "Work", displayIdentity: original.display.identity,
            values: [0x2D: 8, 0x14: 3, 0x10: 20, 0x2F: 6], maxima: [0x2D: 10, 0x14: 4, 0x10: 50, 0x2F: 10])

        reset()
        let fresh = PresetMonitor(original)
        fresh.snapshot.features[2].current = 21
        let saving = store(fresh)
        saving.saveHardwarePreset(named: "Current")
        await eventually(saving)
        precondition(saving.savedPresets.count == 1 && saving.savedPresets[0].values[0x10] == 21)
        precondition(saving.savedPresets[0].values[0x0A] == nil && fresh.writes.isEmpty && fresh.reads == 1)

        for key in [Hardware.samsungEnableKey(original.display), Hardware.samsungPictureModeEnableKey(original.display), Hardware.samsungPIPReadEnableKey(original.display)] {
            reset()
            let revoked = PresetMonitor(original)
            revoked.onRead = { preferences.set(false, forKey: key) }
            let saving = store(revoked)
            saving.saveHardwarePreset(named: "Revoked")
            await eventually(saving)
            precondition(saving.savedPresets.isEmpty && revoked.writes.isEmpty,
                         "Revoking verification during Save must not persist a partial preset")
        }

        for failure in ["none", "write", "disconnect", "range", "eye", "pip", "pip-invalid", "paused", "revoked", "final-drift"] {
            reset()
            try HardwarePresetLibrary.save([preset], to: preferences)
            let monitor = PresetMonitor(original)
            if failure == "write" { monitor.failCode = 0x14 }
            if failure == "disconnect" { monitor.disconnectAfterWrite = true }
            if failure == "range" { monitor.changeRangeAfterMode = true }
            if failure == "eye" { monitor.snapshot.features[4].current = 1 }
            if failure == "pip" { monitor.snapshot.features[5].current = 0x3501 }
            if failure == "pip-invalid" { monitor.snapshot.features[5].status = "invalid reply" }
            if failure == "paused" {
                monitor.onRead = { preferences.set(true, forKey: Hardware.pauseKey) }
            }
            if failure == "revoked" {
                monitor.onRead = {
                    preferences.set(false, forKey: Hardware.samsungAdvancedEnableKey(original.display, code: 0x14))
                }
            }
            if failure == "final-drift" {
                monitor.onRead = {
                    if monitor.reads == 4 {
                        let index = monitor.snapshot.features.firstIndex { $0.code == 0x10 }!
                        monitor.snapshot.features[index].current = 21
                    }
                }
            }
            let applying = store(monitor)
            applying.applyHardwarePreset(preset)
            await eventually(applying)
            switch failure {
            case "none":
                precondition(monitor.writes == [0x2D, 0x14, 0x10, 0x2F], "Apply Picture Mode, Color Tone, then numeric settings")
                precondition(monitor.reads == 4 && applying.message.contains("applied and confirmed"))
                applying.applyHardwarePreset(preset)
                await eventually(applying)
                precondition(monitor.writes.count == 4, "Matching settings need no writes")
                precondition(monitor.reads == 6, "A no-op preset still gets fresh initial and final verification")
            case "write": precondition(monitor.writes == [0x2D, 0x14] && applying.message.contains("stopped"))
            case "disconnect", "range": precondition(monitor.writes == [0x2D])
            case "final-drift":
                precondition(monitor.writes == [0x2D, 0x14, 0x10, 0x2F] && monitor.reads == 4)
                precondition(applying.message.contains("not fully confirmed"))
                precondition(applying.features.first { $0.code == 0x10 }?.current == 21,
                             "Final drift stays visible without a retry or rollback")
            default: precondition(monitor.writes.isEmpty)
            }
        }

        for pauseBeforeRead in [true, false] {
            reset()
            try HardwarePresetLibrary.save([preset], to: preferences)
            let monitor = PresetMonitor(original)
            let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
            let blockQueue = {
                Hardware.queue.async {
                    entered.signal()
                    _ = release.wait(timeout: .now() + 3)
                }
            }
            if pauseBeforeRead { blockQueue() }
            else { monitor.onRead = { if monitor.reads == 1 { blockQueue() } } }
            let applying = store(monitor)
            applying.applyHardwarePreset(preset)
            await waitForQueue(entered)
            // Let the main-actor continuation enqueue its read/write behind the gate.
            try await Task.sleep(nanoseconds: 20_000_000)
            precondition(applying.busy)
            applying.pauseHardwareCommands()
            release.signal()
            await withCheckedContinuation { continuation in
                Hardware.queue.async { continuation.resume() }
            }
            await Task.yield()
            await eventually(applying)
            precondition(monitor.reads == (pauseBeforeRead ? 0 : 1) && monitor.writes.isEmpty,
                         "Pausing queued preset work must prevent any subsequent reader or writer call")
            precondition(applying.hardwareCommandsPaused && applying.features.isEmpty)
            precondition(applying.savedPresets == [preset], "Cancellation must preserve the saved preset")
        }

        reset()
        try HardwarePresetLibrary.save([preset], to: preferences)
        let monitor = PresetMonitor(original)
        let changed = store(monitor)
        changed.selectedID = 100
        changed.applyHardwarePreset(preset)
        precondition(monitor.writes.isEmpty && monitor.reads == 0)

        reset()
        preferences.set(Data("broken".utf8), forKey: HardwarePresetLibrary.storageKey)
        let corrupt = store(PresetMonitor(original))
        precondition(corrupt.presetStorageError != nil && !corrupt.canSaveHardwarePreset)
        corrupt.saveHardwarePreset(named: "Ignored")
        precondition(preferences.data(forKey: HardwarePresetLibrary.storageKey) == Data("broken".utf8))
        print("Preset operations: fresh save, ordered apply, no-op, pause, disconnect, range, Eye Saver, opt-in and storage guards passed.")
    }
}
