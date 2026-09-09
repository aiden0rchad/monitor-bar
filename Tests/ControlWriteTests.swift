import Foundation

private final class GatedWriter {
    private let lock = NSLock()
    private var recorded: [UInt16] = []
    let gates = [DispatchSemaphore(value: 0), DispatchSemaphore(value: 0)]

    var values: [UInt16] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func write(_ display: DisplayInfo, feature: VCPFeature, value: UInt16) -> (VCPFeature?, String) {
        lock.lock()
        let index = recorded.count
        recorded.append(value)
        lock.unlock()
        precondition(index < gates.count, "Unexpected extra write")
        precondition(gates[index].wait(timeout: .now() + 3) == .success, "Write gate timed out")
        var readback = feature
        readback.current = value
        return (readback, "Confirmed \(value)")
    }
}

@main struct ControlWriteTests {
    static let preferenceSuite = "MonitorBar.ControlWriteTests.\(UUID().uuidString)"
    static let preferences = UserDefaults(suiteName: preferenceSuite)!
    static func feature(_ current: UInt16, status: String = "ok") -> VCPFeature {
        VCPFeature(code: 0x10, current: current, maximum: 100, type: 0, status: status)
    }

    static func snapshot() -> MonitorProbe {
        let display = DisplayInfo(id: 4, name: "Test display", vendor: 1, product: 2, serial: 3,
                                  builtIn: false, widthMM: 350, heightMM: 210, rotation: 0,
                                  currentModeID: 0, modes: [])
        return MonitorProbe(display: display, features: [feature(25)], note: "Test snapshot")
    }

    @MainActor static func eventually(_ label: String, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(3)
        while !condition() {
            precondition(Date() < deadline, "Timed out: \(label)")
            try! await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    static func readbackChecks() {
        let cases: [([VCPFeature], UInt16?, Int)] = [
            ([feature(80)], 80, 1),
            ([feature(20), feature(80)], 80, 2),
            ([feature(20), feature(40), feature(60)], 60, 3),
            ([feature(20), feature(0, status: "no reply"), feature(0, status: "no reply")], 20, 3),
            ([feature(0, status: "no reply"), feature(0, status: "no reply"), feature(0, status: "no reply")], nil, 3)
        ]
        for (replies, expected, expectedReads) in cases {
            var reads = 0
            let (actual, message) = Hardware.verifyWrite(feature: feature(25), value: 80) {
                defer { reads += 1 }
                return replies[reads]
            }
            precondition(actual?.current == expected && reads == expectedReads)
            if expected == nil {
                precondition(message.contains("Input or power changes can disconnect DDC"))
            } else if expected != 80 {
                precondition(message.contains("not confirmed") && message.contains("requesting 80"))
            } else {
                precondition(message == "Brightness confirmed: 80.")
            }
        }
    }

    @MainActor static func queueCheck(initial: [UInt16], latest: UInt16) async {
        let writer = GatedWriter()
        defer { writer.gates.forEach { $0.signal() } }
        let store = MonitorStore(snapshot: snapshot(), writer: writer.write, preferences: preferences)
        for value in initial { store.set(feature(25), value: value) }
        precondition(store.writing && store.value(for: store.features[0]) == initial.last!)
        await eventually("first write starts") { writer.values.count == 1 }
        precondition(writer.values == [initial.last!], "Rapid changes must collapse to the latest value")

        store.set(feature(25), value: latest)
        precondition(store.value(for: store.features[0]) == latest && store.writing)
        writer.gates[0].signal()
        await eventually("newest write starts") { writer.values.count == 2 }
        precondition(writer.values == [initial.last!, latest])
        precondition(store.features[0].current == initial.last!)
        precondition(store.value(for: store.features[0]) == latest && store.writing,
                     "Earlier readback must not replace the pending slider value")

        writer.gates[1].signal()
        await eventually("writes finish") { !store.writing }
        precondition(store.features[0].current == latest && store.pendingValues.isEmpty)
        precondition(store.value(for: store.features[0]) == latest)
    }

    @MainActor static func failureChecks() async {
        for readback in [feature(40), nil] as [VCPFeature?] {
            let status = readback == nil ? "Brightness was sent; the monitor did not confirm it. Input or power changes can disconnect DDC."
                                        : "The monitor last reported 40 after requesting 80 for Brightness; the change was not confirmed."
            let store = MonitorStore(snapshot: snapshot(), writer: { _, _, _ in (readback, status) }, preferences: preferences)
            store.set(feature(25), value: 80)
            await eventually("failed write finishes") { !store.writing }
            precondition(store.pendingValues.isEmpty && store.message == status)
            precondition(store.features[0].current == (readback?.current ?? 25))
            precondition(store.features[0].status == "ok")
            precondition(store.value(for: store.features[0]) == (readback?.current ?? 25))
        }
    }

    @MainActor static func pauseChecks() async {
        for invalid in [0, "false", [String]()] as [Any] {
            preferences.set(invalid, forKey: Hardware.pauseKey)
            precondition(Hardware.commandsPaused(in: preferences), "Malformed pause values must fail closed")
        }
        for queueAlreadyStarted in [false, true] {
            preferences.set(false, forKey: Hardware.pauseKey)
            let writer = GatedWriter()
            defer { writer.gates.forEach { $0.signal() } }
            let queueGate = DispatchSemaphore(value: 0)
            if queueAlreadyStarted {
                Hardware.queue.async { _ = queueGate.wait(timeout: .now() + 3) }
            }
            let store = MonitorStore(snapshot: snapshot(), writer: writer.write, preferences: preferences)
            store.set(feature(25), value: 80)
            if queueAlreadyStarted { try! await Task.sleep(nanoseconds: 180_000_000) }
            store.pauseHardwareCommands()
            queueGate.signal()
            try! await Task.sleep(nanoseconds: 180_000_000)
            precondition(writer.values.isEmpty, "Pausing must prevent pending and already queued writes")
            precondition(store.hardwareCommandsPaused && !store.writing && !store.busy)
            precondition(store.features.isEmpty && store.pendingValues.isEmpty && !store.ddcAvailable)
            precondition(store.message == Hardware.pauseMessage)
        }
        let restarted = MonitorStore(snapshot: snapshot(), writer: { _, _, _ in
            preconditionFailure("Paused stores must never call the writer")
        }, preferences: UserDefaults(suiteName: preferenceSuite)!)
        precondition(restarted.hardwareCommandsPaused && restarted.features.isEmpty,
                     "Pause persists across stores and suppresses cached hardware controls")
        precondition(restarted.canResumeHardwareCommands, "Generic monitors must be able to resume")
        restarted.displays.append(DisplayInfo(id: 100, name: "Second generic display", vendor: 1, product: 2, serial: 3,
                                              builtIn: false, widthMM: 1, heightMM: 1, rotation: 0,
                                              currentModeID: 0, modes: []))
        precondition(restarted.canResumeHardwareCommands, "Multiple generic monitors can resume")
        let resumeGate = DispatchSemaphore(value: 0)
        Hardware.queue.async { _ = resumeGate.wait(timeout: .now() + 3) }
        restarted.resumeHardwareCommands()
        precondition(restarted.busy && Hardware.commandsPaused(in: preferences), "Resume waits for older operations")
        restarted.pauseHardwareCommands()
        resumeGate.signal()
        try! await Task.sleep(nanoseconds: 180_000_000)
        precondition(Hardware.commandsPaused(in: preferences) && !restarted.busy, "A new pause cancels queued resume")
        restarted.displays = []
        precondition(!restarted.canResumeHardwareCommands, "No display cannot resume")
        restarted.set(feature(25), value: 80)
        precondition(!restarted.writing && restarted.message == Hardware.pauseMessage)
    }

    @MainActor static func samsungChecks() async {
        preferences.removeObject(forKey: Hardware.pauseKey)
        let display = DisplayInfo(id: 99, name: "Samsung test", vendor: 0x4C2D, product: 0x778D, serial: 999,
                                  builtIn: false, widthMM: 1200, heightMM: 340, rotation: 0, currentModeID: 0, modes: [])
        let red = VCPFeature(code: 0x16, current: 51, maximum: 100, type: 0, status: "ok")
        let brightness = VCPFeature(code: 0x10, current: 49, maximum: 50, type: 0, status: "ok")
        let blocked = VCPFeature(code: 0x60, current: 17, maximum: 18, type: 1, status: "ok")
        let snapshot = MonitorProbe(display: display, capabilities: "(vcp(60(11 12)))", features: [red, brightness, blocked])
        let writer = GatedWriter()
        defer { writer.gates.forEach { $0.signal() } }
        let store = MonitorStore(snapshot: snapshot, writer: writer.write, preferences: preferences)
        store.setOSDValue(red, value: 2)
        precondition(!store.writing && writer.values.isEmpty, "An unverified Samsung unit cannot write")
        preferences.set(true, forKey: Hardware.samsungEnableKey(display))
        preferences.set(25, forKey: "brightnessLimit.\(display.identity)")
        let enabled = MonitorStore(snapshot: snapshot, writer: writer.write, preferences: preferences)
        precondition(enabled.usesSamsungControls && enabled.controlLimits.isEmpty)
        precondition(enabled.osdOffset(for: red) == 50 && enabled.osdOffset(for: brightness) == 0)
        let differentRange = VCPFeature(code: 0x16, current: 20, maximum: 50, type: 0, status: "ok")
        precondition(enabled.osdOffset(for: differentRange) == 0, "Do not apply an untested RGB range offset")
        for value in [-51.0, 51, Double.nan, Double.infinity] { enabled.setOSDValue(red, value: value) }
        enabled.set(blocked, value: 18)
        enabled.setControlLimit(brightness, limit: 25)
        precondition(!enabled.writing && writer.values.isEmpty && enabled.controlLimits.isEmpty)
        enabled.setOSDValue(red, value: -1)
        await eventually("Samsung centered value write") { writer.values == [49] }
        writer.gates[0].signal()
        await eventually("Samsung centered value readback") { !enabled.writing }
        precondition(enabled.features[0].current == 49 && enabled.value(for: enabled.features[0]) == 49)
        enabled.setOSDValue(brightness, value: 48)
        await eventually("Samsung raw brightness write") { writer.values == [49, 48] }
        writer.gates[1].signal()
        await eventually("Samsung raw brightness readback") { !enabled.writing }
        precondition(enabled.features[1].current == 48, "Samsung brightness must not use percentage conversion")
        enabled.pauseHardwareCommands()
        precondition(enabled.canResumeHardwareCommands)
        enabled.displays.append(DisplayInfo(id: 100, name: "Other", vendor: 1, product: 2, serial: 3, builtIn: false,
                                           widthMM: 1, heightMM: 1, rotation: 0, currentModeID: 0, modes: []))
        precondition(!enabled.canResumeHardwareCommands, "Resume must not clear the global pause with multiple displays")
        preferences.removeObject(forKey: Hardware.samsungEnableKey(display))
        enabled.displays = [display]
        precondition(!enabled.canResumeHardwareCommands, "Resume requires per-unit verification")
    }

    @MainActor static func samsungPictureModeChecks() async {
        preferences.removeObject(forKey: Hardware.pauseKey)
        let display = DisplayInfo(id: 99, name: "Samsung test", vendor: 0x4C2D, product: 0x778D, serial: 999,
                                  builtIn: false, widthMM: 1200, heightMM: 340, rotation: 0, currentModeID: 0, modes: [])
        let mode = VCPFeature(code: 0x2D, current: 2, maximum: 10, type: 0, status: "ok")
        let brightness = VCPFeature(code: 0x10, current: 49, maximum: 50, type: 0, status: "ok")
        let snapshot = MonitorProbe(display: display, features: [mode, brightness])
        let writer = GatedWriter()
        defer { writer.gates.forEach { $0.signal() } }
        preferences.set(true, forKey: Hardware.samsungEnableKey(display))
        let store = MonitorStore(snapshot: snapshot, writer: writer.write, preferences: preferences)
        precondition(store.allowedChoices(for: mode).isEmpty && !mode.isSlider)
        store.set(mode, value: 8)
        precondition(!store.writing)
        preferences.set(true, forKey: Hardware.samsungPictureModeEnableKey(display))
        precondition(store.allowedChoices(for: mode).map(\.0) == Array(UInt16(0)...9))
        var unavailable = mode
        unavailable.status = "unavailable"
        precondition(store.allowedChoices(for: unavailable).isEmpty)
        store.set(mode, value: 10)
        precondition(!store.writing, "The reported maximum is not a valid PC mode")
        store.set(mode, value: 8)
        await eventually("Samsung preset write") { writer.values == [8] }
        store.set(brightness, value: 25)
        store.set(mode, value: 3)
        precondition(store.pendingValues == [0x2D: 8], "Presets cannot overlap queued controls")
        // Pause before releasing the fake writer so this offline fixture cannot trigger live discovery.
        store.pauseHardwareCommands()
        writer.gates[0].signal()
        await eventually("Paused preset queue") { !store.writing }
        precondition(store.pendingValues.isEmpty)
        preferences.removeObject(forKey: Hardware.pauseKey)
        let second = MonitorStore(snapshot: snapshot, writer: writer.write, preferences: preferences)
        second.set(brightness, value: 48)
        await eventually("Brightness before preset") { writer.values == [8, 48] }
        second.set(mode, value: 8)
        precondition(second.pendingValues == [0x10: 48], "A preset cannot queue behind another control")
        writer.gates[1].signal()
        await eventually("Brightness completes") { !second.writing }
    }

    @MainActor static func samsungAdvancedChecks() async {
        preferences.removeObject(forKey: Hardware.pauseKey)
        let display = DisplayInfo(id: 99, name: "Samsung test", vendor: 0x4C2D, product: 0x778D, serial: 999,
                                  builtIn: false, widthMM: 1200, heightMM: 340, rotation: 0, currentModeID: 0, modes: [])
        let eye = VCPFeature(code: 0x0A, current: 0, maximum: 2, type: 0, status: "ok")
        let tone = VCPFeature(code: 0x14, current: 2, maximum: 4, type: 0, status: "ok")
        let black = VCPFeature(code: 0x2F, current: 5, maximum: 10, type: 0, status: "ok")
        let brightness = VCPFeature(code: 0x10, current: 25, maximum: 50, type: 0, status: "ok")
        let snapshot = MonitorProbe(display: display, capabilities: "(vcp(14(01 02 04 05 06 08 0B)))",
                                    features: [eye, tone, black, brightness])
        let writer = GatedWriter()
        defer {
            writer.gates.forEach { $0.signal() }
            for code in Hardware.samsungAdvancedControlCodes {
                preferences.removeObject(forKey: Hardware.samsungAdvancedEnableKey(display, code: code))
            }
        }
        preferences.set(true, forKey: Hardware.samsungEnableKey(display))
        let store = MonitorStore(snapshot: snapshot, writer: writer.write, preferences: preferences)
        precondition(store.allowedChoices(for: tone).isEmpty, "Samsung must never fall back to generic color-temperature values")
        precondition(!store.isWritableSlider(black))
        for feature in [eye, tone, black] { store.set(feature, value: 1) }
        precondition(!store.writing && writer.values.isEmpty, "New controls require separate verification")
        for code in Hardware.samsungAdvancedControlCodes {
            preferences.set(true, forKey: Hardware.samsungAdvancedEnableKey(display, code: code))
        }
        precondition(store.allowedChoices(for: eye).map(\.0) == [0, 1, 2])
        precondition(store.allowedChoices(for: tone).map(\.1) == ["Cool", "Standard", "Warm 1", "Warm 2", "Natural"])
        precondition(store.controlName(for: tone) == "Color Tone" && store.isWritableSlider(black))
        store.set(black, value: 11)
        store.set(tone, value: 5)
        precondition(!store.writing, "Out-of-range values must be rejected")
        store.features[0].current = 1
        precondition(store.allowedChoices(for: tone).isEmpty && !store.isWritableSlider(black) && !store.isWritableSlider(brightness))
        store.set(black, value: 6)
        precondition(!store.writing && !store.allowedChoices(for: store.features[0]).isEmpty,
                     "Eye Saver locks affected settings but remains available to switch off")
        store.features[0].status = "unsupported"
        precondition(!store.isWritableSlider(black), "Missing Eye Saver state must fail closed")
        store.features[0] = eye
        store.set(black, value: 6)
        await eventually("Black Equalizer write") { writer.values == [6] }
        writer.gates[0].signal()
        await eventually("Black Equalizer readback") { !store.writing }
        precondition(store.features[2].current == 6)
        store.set(tone, value: 3)
        await eventually("Color Tone write") { writer.values == [6, 3] }
        store.set(brightness, value: 24)
        store.set(eye, value: 1)
        precondition(store.pendingValues == [0x14: 3], "Tone changes must finish and refresh before another picture write")
        // Prevent this offline preset fixture from initiating a live post-write refresh.
        store.pauseHardwareCommands()
        writer.gates[1].signal()
        await eventually("Paused color queue") { !store.writing }
    }

    @MainActor static func main() async {
        defer { preferences.removePersistentDomain(forName: preferenceSuite) }
        readbackChecks()
        await queueCheck(initial: [20, 50, 80], latest: 30)
        await queueCheck(initial: [80], latest: 25)
        await failureChecks()
        await pauseChecks()
        await samsungChecks()
        await samsungPictureModeChecks()
        await samsungAdvancedChecks()
        print("Control write, readback, and persistent pause scenarios passed (no hardware access)")
    }
}
