import Foundation

private final class CalibrationWriter {
    private let lock = NSLock()
    private var recorded: [(UInt8, UInt16)] = []

    var writes: [(UInt8, UInt16)] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func write(_ display: DisplayInfo, feature: VCPFeature, value: UInt16) -> (VCPFeature?, String) {
        lock.lock()
        recorded.append((feature.code, value))
        lock.unlock()
        var readback = feature
        readback.current = value
        return (readback, "Confirmed \(value)")
    }
}

@main struct BrightnessCalibrationTests {
    static func snapshot(id: UInt32 = 4, serial: UInt32 = 3, current: UInt16 = 25, maximum: UInt16 = 100) -> MonitorProbe {
        let display = DisplayInfo(id: id, name: "Test display", vendor: 1, product: 2, serial: serial,
                                  builtIn: false, widthMM: 350, heightMM: 210, rotation: 0,
                                  currentModeID: 0, modes: [])
        return MonitorProbe(display: display, features: [
            VCPFeature(code: 0x10, current: current, maximum: maximum, type: 0, status: "ok"),
            VCPFeature(code: 0x12, current: 50, maximum: 100, type: 0, status: "ok"),
            VCPFeature(code: 0x62, current: 50, maximum: 100, type: 0, status: "ok")
        ])
    }

    @MainActor static func finished(_ store: MonitorStore) async {
        let deadline = Date().addingTimeInterval(3)
        while store.writing {
            precondition(Date() < deadline, "Control write timed out")
            try! await Task.sleep(nanoseconds: 10_000_000)
        }
        precondition(store.pendingValues.isEmpty)
    }

    @MainActor static func main() async {
        let suite = "MonitorBar.BrightnessCalibrationTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let writer = CalibrationWriter()
        let store = MonitorStore(snapshot: snapshot(), writer: writer.write, preferences: preferences)

        precondition(store.controlLimits[0x10] == nil && store.controlPercent(for: store.features[0]) == 25)
        store.setControlLimit(store.features[0], limit: 25)
        precondition(store.controlLimits[0x10] == 25 && store.controlPercent(for: store.features[0]) == 100)
        precondition(!store.writing && writer.writes.isEmpty, "Saving a limit must not change the monitor")

        let reloaded = MonitorStore(snapshot: snapshot(id: 8), writer: writer.write, preferences: UserDefaults(suiteName: suite)!)
        precondition(reloaded.controlLimits[0x10] == 25, "Calibration must follow identity across display IDs")
        let other = MonitorStore(snapshot: snapshot(serial: 99), writer: writer.write, preferences: preferences)
        precondition(other.controlLimits[0x10] == nil)
        other.setControlLimit(other.features[0], limit: 10)
        precondition(other.controlPercent(for: other.features[0]) == 100, "Values above the limit must display at 100%")
        precondition(MonitorStore(snapshot: snapshot(), writer: writer.write, preferences: preferences).controlLimits[0x10] == 25)

        for invalid: UInt16 in [0, 101, UInt16.max] { store.setControlLimit(store.features[0], limit: invalid) }
        precondition(store.controlLimits[0x10] == 25)
        for invalid in [-1.0, 100.1, Double.nan, Double.infinity, -Double.infinity] { store.setPercent(store.features[0], percent: invalid) }
        store.set(store.features[0], value: 26)
        precondition(!store.writing && store.pendingValues.isEmpty && writer.writes.isEmpty)

        var previous: UInt16 = 0
        for percent in 0...100 {
            store.setPercent(store.features[0], percent: Double(percent))
            let expected = UInt16((Double(percent) * 25 / 100).rounded())
            let raw = store.value(for: store.features[0])
            precondition(raw == expected && raw >= previous && raw <= 25)
            precondition(store.controlPercent(for: store.features[0]) == Double(raw) * 4)
            previous = raw
        }
        await finished(store)
        precondition(writer.writes.map(\.1) == [25], "Rapid percent changes must send only the latest mapped value")

        for (percent, expected): (Double, UInt16) in [(0, 0), (25, 6), (50, 13), (75, 19), (100, 25)] {
            store.setPercent(store.features[0], percent: percent)
            await finished(store)
            precondition(store.features[0].current == expected)
            precondition(store.controlPercent(for: store.features[0]) == Double(expected) * 4)
        }
        precondition(writer.writes.map(\.1) == [25, 0, 6, 13, 19, 25])

        store.set(store.features[1], value: 80)
        await finished(store)
        precondition(store.features[1].current == 80 && writer.writes.last!.0 == 0x12)

        let writesBeforeContrastLimit = writer.writes.count
        store.setControlLimit(store.features[1], limit: 25)
        precondition(store.controlLimits == [0x10: 25, 0x12: 25])
        precondition(store.features[0].current == 25 && store.features[1].current == 80)
        precondition(store.controlPercent(for: store.features[1]) == 100)
        precondition(!store.writing && writer.writes.count == writesBeforeContrastLimit)
        precondition(preferences.integer(forKey: "brightnessLimit.\(snapshot().display.identity)") == 25)
        precondition(preferences.integer(forKey: "contrastLimit.\(snapshot().display.identity)") == 25)
        let bothReloaded = MonitorStore(snapshot: snapshot(id: 9), writer: writer.write, preferences: preferences)
        precondition(bothReloaded.controlLimits == [0x10: 25, 0x12: 25])
        precondition(MonitorStore(snapshot: snapshot(serial: 99), writer: writer.write, preferences: preferences).controlLimits == [0x10: 10])

        for invalid: UInt16 in [0, 101, UInt16.max] { store.setControlLimit(store.features[1], limit: invalid) }
        for invalid in [-1.0, 100.1, Double.nan, Double.infinity] { store.setPercent(store.features[1], percent: invalid) }
        store.set(store.features[1], value: 26)
        store.setControlLimit(store.features[2], limit: 25)
        precondition(store.controlLimits == [0x10: 25, 0x12: 25], "Volume must not acquire a calibration")
        precondition(!store.writing && store.pendingValues.isEmpty && writer.writes.count == writesBeforeContrastLimit)

        previous = 0
        for percent in 0...100 {
            store.setPercent(store.features[1], percent: Double(percent))
            let expected = UInt16((Double(percent) * 25 / 100).rounded())
            let raw = store.value(for: store.features[1])
            precondition(raw == expected && raw >= previous && raw <= 25)
            precondition(store.controlPercent(for: store.features[1]) == Double(raw) * 4)
            precondition(store.features[0].current == 25 && store.controlLimits[0x10] == 25)
            previous = raw
        }
        await finished(store)
        precondition(writer.writes.count == writesBeforeContrastLimit + 1 && writer.writes.last!.0 == 0x12)
        precondition(store.features[1].current == 25)
        store.setControlLimit(store.features[1], limit: 10)
        precondition(store.controlLimits == [0x10: 25, 0x12: 10] && store.features[0].current == 25)
        precondition(MonitorStore(snapshot: snapshot(), writer: writer.write, preferences: preferences).controlLimits == [0x10: 25, 0x12: 10])

        let writesBeforeReset = writer.writes.count
        store.setControlLimit(store.features[0], limit: nil)
        precondition(store.controlLimits[0x10] == nil && !store.writing && writer.writes.count == writesBeforeReset)
        precondition(store.controlLimits[0x12] == 10, "Resetting brightness must preserve the contrast limit")
        precondition(store.controlPercent(for: store.features[0]) == 25)
        precondition(MonitorStore(snapshot: snapshot(), writer: writer.write, preferences: preferences).controlLimits[0x10] == nil)
        precondition(MonitorStore(snapshot: snapshot(serial: 99), writer: writer.write, preferences: preferences).controlLimits[0x10] == 10)
        store.setControlLimit(store.features[1], limit: nil)
        precondition(store.controlLimits.isEmpty && preferences.object(forKey: "contrastLimit.\(snapshot().display.identity)") == nil)

        let normalWriter = CalibrationWriter()
        let normal = MonitorStore(snapshot: snapshot(serial: 100, current: 50, maximum: 200), writer: normalWriter.write, preferences: preferences)
        precondition(normal.controlPercent(for: normal.features[0]) == 25)
        normal.setPercent(normal.features[0], percent: 100)
        await finished(normal)
        precondition(normal.features[0].current == 200 && normalWriter.writes.map(\.1) == [200])
        precondition(normal.controlPercent(for: normal.features[0]) == 100)

        print("Brightness and contrast calibration checks passed: 202 monotonic mappings, independent persisted limits, validation, coalescing, and volume exclusion (no hardware access)")
    }
}
