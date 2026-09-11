import AppKit
import SwiftUI

/// Timeline slider backed by a real NSSlider: while dragging, AppKit tracks
/// the mouse directly, so the knob always stays exactly under the cursor.
/// SwiftUI value writes are skipped during scrubbing to avoid fighting the mouse.
struct TimelineSlider: NSViewRepresentable {
    let value: Double
    let range: ClosedRange<Double>
    let onBeginScrubbing: () -> Void
    let onScrub: (Double) -> Void
    let onEndScrubbing: () -> Void

    func makeNSView(context: Context) -> TimelineSliderView {
        let slider = TimelineSliderView()
        slider.isContinuous = true
        slider.setAccessibilityLabel("Timeline")
        return slider
    }

    func updateNSView(_ slider: TimelineSliderView, context: Context) {
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.onBeginScrubbing = onBeginScrubbing
        slider.onScrub = onScrub
        slider.onEndScrubbing = onEndScrubbing
        if !slider.isScrubbing, slider.doubleValue != value {
            slider.doubleValue = value
        }
    }
}

final class TimelineSliderView: NSSlider {
    var onBeginScrubbing: (() -> Void)?
    var onScrub: ((Double) -> Void)?
    var onEndScrubbing: (() -> Void)?
    private(set) var isScrubbing = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cell = TimelineSliderCell(textCell: "")
        target = self
        action = #selector(didMove(_:))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func didMove(_ sender: NSSlider) {
        onScrub?(sender.doubleValue)
    }

    override func mouseDown(with event: NSEvent) {
        isScrubbing = true
        onBeginScrubbing?()
        super.mouseDown(with: event)
        isScrubbing = false
        onScrub?(doubleValue)
        onEndScrubbing?()
    }
}

private final class TimelineSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let barHeight: CGFloat = 4
        let bar = NSRect(
            x: rect.minX,
            y: NSMidY(rect) - barHeight / 2,
            width: rect.width,
            height: barHeight
        )

        NSColor.white.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: bar, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()

        let fillWidth = min(max(knobRect(flipped: flipped).midX - bar.minX, 0), bar.width)
        guard fillWidth > barHeight / 2 else { return }
        NSColor.white.withAlphaComponent(0.9).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: bar.minX, y: bar.minY, width: fillWidth, height: barHeight),
            xRadius: barHeight / 2,
            yRadius: barHeight / 2
        ).fill()
    }
}
