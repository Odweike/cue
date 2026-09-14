import AppKit
import SwiftUI

/// Timeline slider backed by a real NSSlider: while dragging, AppKit tracks
/// the mouse directly, so the knob always stays exactly under the cursor.
/// SwiftUI value writes are skipped during scrubbing to avoid fighting the mouse.
struct TimelineSlider: NSViewRepresentable {
    let value: Double
    let range: ClosedRange<Double>
    let chapters: [PlaybackChapter]
    let loopA: TimeInterval?
    let loopB: TimeInterval?
    let thumbnail: (TimeInterval) -> NSImage?
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
        slider.chapterStarts = chapters.map(\.start)
        slider.loopA = loopA
        slider.loopB = loopB
        slider.thumbnail = thumbnail
        slider.onBeginScrubbing = onBeginScrubbing
        slider.onScrub = onScrub
        slider.onEndScrubbing = onEndScrubbing
        if !slider.isScrubbing, slider.doubleValue != value {
            slider.doubleValue = value
        }
        slider.needsDisplay = true
    }
}

final class TimelineSliderView: NSSlider {
    var onBeginScrubbing: (() -> Void)?
    var onScrub: ((Double) -> Void)?
    var onEndScrubbing: (() -> Void)?
    var thumbnail: ((TimeInterval) -> NSImage?)?
    var chapterStarts: [TimeInterval] = [] {
        didSet { (cell as? TimelineSliderCell)?.chapterStarts = chapterStarts }
    }
    var loopA: TimeInterval? {
        didSet { (cell as? TimelineSliderCell)?.loopA = loopA }
    }
    var loopB: TimeInterval? {
        didSet { (cell as? TimelineSliderCell)?.loopB = loopB }
    }
    private(set) var isScrubbing = false
    private let preview = TimelinePreviewPanel()
    private var tracking: NSTrackingArea?

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

    deinit {
        preview.close()
    }

    @objc private func didMove(_ sender: NSSlider) {
        onScrub?(sender.doubleValue)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        showPreview(at: event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        preview.orderOut(nil)
    }

    override func mouseDown(with event: NSEvent) {
        isScrubbing = true
        onBeginScrubbing?()
        super.mouseDown(with: event)
        isScrubbing = false
        onScrub?(doubleValue)
        onEndScrubbing?()
        preview.orderOut(nil)
    }

    private func showPreview(at event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let span = maxValue - minValue
        guard span > 0, bounds.width > 0 else { return }
        let progress = min(max(location.x / bounds.width, 0), 1)
        let time = minValue + span * progress
        let screenPoint = window?.convertPoint(toScreen: event.locationInWindow) ?? .zero
        preview.show(
            image: thumbnail?(time),
            time: time,
            duration: maxValue,
            at: screenPoint
        )
    }
}

private final class TimelinePreviewPanel: NSPanel {
    private let imageView = NSImageView()
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 168, height: 118),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let box = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 168, height: 118))
        box.material = .hudWindow
        box.state = .active
        box.wantsLayer = true
        box.layer?.cornerRadius = 8
        contentView = box

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 4
        imageView.layer?.masksToBounds = true
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        box.addSubview(imageView)
        box.addSubview(label)
        imageView.frame = NSRect(x: 8, y: 24, width: 152, height: 86)
        label.frame = NSRect(x: 8, y: 4, width: 152, height: 16)
    }

    func show(image: NSImage?, time: TimeInterval, duration: TimeInterval, at point: NSPoint) {
        imageView.image = image
        let hours = duration >= 3_600
        label.stringValue = PlaybackTimeFormat.string(from: time, includingHours: hours)
        setFrameOrigin(NSPoint(x: point.x - 84, y: point.y + 18))
        orderFrontRegardless()
    }
}

private final class TimelineSliderCell: NSSliderCell {
    var chapterStarts: [TimeInterval] = []
    var loopA: TimeInterval?
    var loopB: TimeInterval?

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

        if let loopA, let loopB, maxValue > minValue {
            let span = maxValue - minValue
            let start = bar.minX + bar.width * CGFloat((min(loopA, loopB) - minValue) / span)
            let end = bar.minX + bar.width * CGFloat((max(loopA, loopB) - minValue) / span)
            NSColor.systemYellow.withAlphaComponent(0.45).setFill()
            NSBezierPath(
                roundedRect: NSRect(x: start, y: bar.minY, width: max(end - start, 2), height: barHeight),
                xRadius: 1,
                yRadius: 1
            ).fill()
        }

        let fillWidth = min(max(knobRect(flipped: flipped).midX - bar.minX, 0), bar.width)
        if fillWidth > barHeight / 2 {
            NSColor.white.withAlphaComponent(0.9).setFill()
            NSBezierPath(
                roundedRect: NSRect(x: bar.minX, y: bar.minY, width: fillWidth, height: barHeight),
                xRadius: barHeight / 2,
                yRadius: barHeight / 2
            ).fill()
        }

        guard maxValue > minValue else { return }
        NSColor.white.withAlphaComponent(0.7).setFill()
        for chapter in chapterStarts where chapter > minValue && chapter < maxValue {
            let x = bar.minX + bar.width * CGFloat((chapter - minValue) / (maxValue - minValue))
            NSBezierPath(rect: NSRect(x: x, y: bar.minY - 2, width: 1, height: barHeight + 4)).fill()
        }
    }
}
