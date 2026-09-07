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
        let store = MonitorStore(snapshot: snapshot(), writer: writer.write)
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
            let store = MonitorStore(snapshot: snapshot()) { _, _, _ in (readback, status) }
            store.set(feature(25), value: 80)
            await eventually("failed write finishes") { !store.writing }
            precondition(store.pendingValues.isEmpty && store.message == status)
            precondition(store.features[0].current == (readback?.current ?? 25))
            precondition(store.features[0].status == "ok")
            precondition(store.value(for: store.features[0]) == (readback?.current ?? 25))
        }
    }

    @MainActor static func main() async {
        readbackChecks()
        await queueCheck(initial: [20, 50, 80], latest: 30)
        await queueCheck(initial: [80], latest: 25)
        await failureChecks()
        print("9 control write scenarios passed (no hardware access)")
    }
}
