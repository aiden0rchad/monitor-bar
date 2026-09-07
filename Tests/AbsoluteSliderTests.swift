import AppKit
import SwiftUI

@main
struct AbsoluteSliderTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        var displayed = 25.0
        var editing = false
        var writes: [Double] = []
        let view = AbsoluteSlider(
            value: Binding(get: { displayed }, set: { displayed = $0 }),
            isEditing: Binding(get: { editing }, set: { editing = $0 }),
            range: 0...100, step: 1, label: "Brightness", detail: "Test",
            commit: { writes.append($0) })
        let coordinator = view.makeCoordinator()
        let slider = TrackingSlider()
        slider.minValue = 0
        slider.maxValue = 100
        slider.target = coordinator
        slider.action = #selector(AbsoluteSlider.Coordinator.changed(_:))

        let targets = [0.0, 25, 50, 75, 100, 80, 20, 0, 100]
        for target in targets {
            slider.doubleValue = target
            slider.sendAction(slider.action!, to: slider.target)
            assert(displayed == target, "The label follows the absolute thumb value")
            assert(writes.last == target, "Writes use the absolute thumb value")
        }
        assert(writes == targets, "Both increasing and decreasing targets remain exact")
        slider.doubleValue = 49.6
        slider.sendAction(slider.action!, to: slider.target)
        assert(displayed == 50 && writes.last == 50, "Fractional positions round to a whole control step")

        let beforeAccessibility = writes.count
        _ = slider.accessibilityPerformIncrement()
        assert(writes.count == beforeAccessibility + 1 && writes.last == slider.doubleValue && displayed == slider.doubleValue,
               "Accessibility changes use the same absolute target action")
        let beforeDisabled = writes.count
        slider.isEnabled = false
        slider.doubleValue = 10
        slider.sendAction(slider.action!, to: slider.target)
        assert(writes.count == beforeDisabled, "Disabled controls cannot write")

        coordinator.parent = AbsoluteSlider(
            value: Binding(get: { displayed }, set: { displayed = $0 }),
            isEditing: .constant(false), range: 3000...9500, step: 100,
            label: "Temperature", detail: "Test", commit: { writes.append($0) })
        slider.isEnabled = true
        slider.minValue = 3000
        slider.maxValue = 9500
        slider.doubleValue = 6549
        slider.sendAction(slider.action!, to: slider.target)
        assert(displayed == 6500 && writes.last == 6500, "Quantization uses the control's lower bound and step")
        slider.doubleValue = 9500
        slider.sendAction(slider.action!, to: slider.target)
        assert(displayed == 9500 && writes.last == 9500, "The upper endpoint remains reachable")
        print("Absolute slider tests passed (\(targets.count * 2 + 6) checks; no hardware writes).")
    }
}
