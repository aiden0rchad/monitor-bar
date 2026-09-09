import AppKit
import SwiftUI

// Opt-in integration check: changes one calibrated control, then restores it.
@main struct DDCControlRange {
    @MainActor static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 4, arguments[0] == "--display-id", let displayID = UInt32(arguments[1]), displayID != 0,
              ["--brightness", "--contrast"].contains(arguments[2]), arguments[3] == "--exercise" else {
            print("Usage: ddc-control-range --display-id <CGDirectDisplayID> --brightness|--contrast --exercise")
            print("List display IDs with monitor-probe --modes. Quit Monitor Bar and other DDC utilities first.")
            exit(2)
        }
        let code: UInt8 = arguments[2] == "--contrast" ? 0x12 : 0x10
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "local.monitorbar.app").isEmpty else {
            print("Quit Monitor Bar before exercising DDC.")
            exit(2)
        }
        _ = NSApplication.shared
        let matches = Hardware.displays().filter { $0.id == displayID }
        guard matches.first?.isSamsungG91SD != true else {
            print("Samsung G91SD requires the guarded monitor-probe diagnostics; this range exercise is disabled.")
            exit(2)
        }
        guard matches.count == 1, let display = matches.first,
              let service = Hardware.service(for: display), let handle = DDCOpen(service.id) else {
            print("The selected display has no unique DDC connection; nothing written.")
            exit(2)
        }
        let initial = Hardware.feature(handle, code)
        DDCClose(handle)
        guard initial.isSlider else {
            print("The monitor did not return a valid continuous range for \(initial.name); nothing written.")
            exit(2)
        }
        print("CONTROL \(initial.name) INITIAL \(initial.current)")
        let preferences = UserDefaults(suiteName: "local.monitorbar.app")!
        let store = MonitorStore(snapshot: MonitorProbe(display: display, features: [initial]), preferences: preferences)
        guard let maximum = store.controlLimits[code] else {
            print("Save a custom range for \(initial.name) in Monitor Bar before running this check.")
            exit(2)
        }
        print("CALIBRATED RANGE 0...\(maximum)")
        print("This checks reported values. Observe the monitor to verify its physical response.")
        var displayed = store.controlPercent(for: initial)
        let view = AbsoluteSlider(value: Binding(get: { displayed }, set: { displayed = $0 }),
                                  isEditing: .constant(false), range: 0...100, step: 100 / Double(maximum),
                                  label: initial.name, detail: "Integration test",
                                  commit: { store.setPercent(initial, percent: $0) })
        let coordinator = view.makeCoordinator()
        let slider = TrackingSlider()
        slider.minValue = 0
        slider.maxValue = 100
        slider.target = coordinator
        slider.action = #selector(AbsoluteSlider.Coordinator.changed(_:))
        var passed = true
        for target in [0.0, 25, 50, 75, 100] {
            slider.doubleValue = target
            slider.sendAction(slider.action!, to: slider.target)
            let deadline = Date().addingTimeInterval(10)
            while store.writing && Date() < deadline { try? await Task.sleep(nanoseconds: 20_000_000) }
            if store.writing {
                print("The write did not finish within 10 seconds; stopping the exercise and restoring the initial value.")
                passed = false
                break
            }
            let actual = store.features.first?.current
            let expected = UInt16((target * Double(maximum) / 100).rounded())
            let exact = actual == expected && expected <= maximum && store.pendingValues.isEmpty
                && abs(displayed - store.controlPercent(for: store.features[0])) < 0.001
            print("TARGET \(Int(target)) SLIDER \(displayed) RAW \(actual.map(String.init) ?? "nil") MATCH \(exact) STATUS \(store.message)")
            passed = passed && exact
            if !exact { break }
        }
        // Restore after any outstanding write, including a timed-out verification.
        let (restored, status) = await withCheckedContinuation { continuation in
            Hardware.queue.async {
                continuation.resume(returning: Hardware.write(display, feature: initial, value: initial.current))
            }
        }
        let restoreOK = restored?.current == initial.current
        print("RESTORE \(initial.current) MATCH \(restoreOK) STATUS \(status)")
        exit(passed && restoreOK ? 0 : 1)
    }
}
