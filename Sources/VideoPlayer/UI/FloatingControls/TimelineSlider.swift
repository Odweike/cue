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
            at: screenPoint,
            avoiding: controlBarScreenFrame()
        )
    }

    private func controlBarScreenFrame() -> NSRect {
        var view: NSView = self
        var bar: NSView = self
        while let parent = view.superview {
            if parent.bounds.height > 220 { break }
            if parent.bounds.height >= bar.bounds.height {
                bar = parent
            }
            view = parent
        }
        guard let window else { return .zero }
        return window.convertToScreen(bar.convert(bar.bounds, to: nil))
    }
}

private final class TimelinePreviewPanel: NSPanel {
    private let imageView = NSImageView()
    private let label = NSTextField(labelWithString: "")

    init() {
        let size = TimelinePreviewPlacement.panelSize(for: TimelinePreviewPlacement.defaultImage)
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
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

        let box = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        box.material = .hudWindow
        box.state = .active
        box.wantsLayer = true
        box.layer?.cornerRadius = 8
        box.autoresizingMask = [.width, .height]
        contentView = box

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        box.addSubview(imageView)
        box.addSubview(label)
        layout(imageSize: TimelinePreviewPlacement.defaultImage)
    }

    func show(image: NSImage?, time: TimeInterval, duration: TimeInterval, at point: NSPoint, avoiding bar: NSRect) {
        imageView.image = image
        let hours = duration >= 3_600
        label.stringValue = PlaybackTimeFormat.string(from: time, includingHours: hours)
        let imageSize = image?.size ?? TimelinePreviewPlacement.defaultImage
        let size = layout(imageSize: imageSize)
        let screen = NSScreen.screens.first { $0.frame.intersects(bar) || $0.frame.contains(point) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(origin: .zero, size: size)
        setFrame(
            NSRect(
                origin: TimelinePreviewPlacement.origin(cursorX: point.x, size: size, avoiding: bar, in: screen),
                size: size
            ),
            display: true
        )
        orderFrontRegardless()
    }

    @discardableResult
    private func layout(imageSize: NSSize) -> NSSize {
        let size = TimelinePreviewPlacement.panelSize(for: imageSize)
        let pad = TimelinePreviewPlacement.padding
        imageView.frame = NSRect(
            x: pad,
            y: TimelinePreviewPlacement.labelHeight,
            width: imageSize.width,
            height: imageSize.height
        )
        label.frame = NSRect(x: pad, y: 4, width: imageSize.width, height: 16)
        return size
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

enum TimelinePreviewPlacement {
    static let defaultImage = VideoThumbnailCache.pointSize(videoWidth: 16, videoHeight: 9)
    static let padding: CGFloat = 8
    static let labelHeight: CGFloat = 22
    static let gap: CGFloat = 10
    static let margin: CGFloat = 8

    static func panelSize(for image: NSSize) -> NSSize {
        NSSize(width: image.width + padding * 2, height: image.height + padding + labelHeight)
    }

    static func origin(cursorX: CGFloat, size: NSSize, avoiding bar: NSRect, in screen: NSRect) -> NSPoint {
        let minX = screen.minX + margin
        let maxX = screen.maxX - size.width - margin
        let x = minX <= maxX
            ? min(max(cursorX - size.width / 2, minX), maxX)
            : screen.midX - size.width / 2
        let above = bar.maxY + gap
        let y = above + size.height <= screen.maxY - margin
            ? above
            : bar.minY - gap - size.height
        return NSPoint(x: x, y: max(screen.minY + margin, y))
    }
}
