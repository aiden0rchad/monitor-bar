import AppKit
import SwiftUI

struct AbsoluteSlider: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    @Binding var value: Double
    @Binding var isEditing: Bool
    let range: ClosedRange<Double>
    let step: Double
    let label: String
    let detail: String
    var commitWhileDragging = true
    let commit: (Double) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> TrackingSlider {
        let slider = TrackingSlider()
        slider.isContinuous = commitWhileDragging
        slider.controlSize = .small
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        slider.trackingChanged = { context.coordinator.parent.isEditing = $0 }
        updateNSView(slider, context: context)
        return slider
    }

    func updateNSView(_ slider: TrackingSlider, context: Context) {
        context.coordinator.parent = self
        slider.isEnabled = isEnabled
        slider.isContinuous = commitWhileDragging
        slider.setAccessibilityLabel(label)
        slider.toolTip = detail
        // AppKit owns the thumb while tracking, even when readbacks redraw SwiftUI.
        if !slider.isTracking {
            slider.minValue = range.lowerBound
            slider.maxValue = range.upperBound
            slider.doubleValue = value
        }
    }

    final class Coordinator: NSObject {
        var parent: AbsoluteSlider

        init(_ parent: AbsoluteSlider) { self.parent = parent }

        @objc func changed(_ slider: NSSlider) {
            guard slider.isEnabled, slider.doubleValue.isFinite,
                  parent.step.isFinite, parent.step > 0 else { return }
            let lower = parent.range.lowerBound
            let value = min(parent.range.upperBound, max(lower,
                lower + ((slider.doubleValue - lower) / parent.step).rounded() * parent.step))
            slider.doubleValue = value
            parent.value = value
            parent.commit(value)
        }
    }
}

final class TrackingSlider: NSSlider {
    private(set) var isTracking = false
    var trackingChanged: ((Bool) -> Void)?

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isTracking = true
        trackingChanged?(true)
        super.mouseDown(with: event)
        // Read the final native value directly, including release outside the track.
        if let action { sendAction(action, to: target) }
        isTracking = false
        trackingChanged?(false)
    }
}
