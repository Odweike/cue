import CoreGraphics
import XCTest
@testable import VideoPlayer

final class FloatingControlsGeometryTests: XCTestCase {
    func testBottomTrailingResizeKeepsTopLeadingCornerFixed() {
        let availableSize = CGSize(width: 1_000, height: 608)
        let currentSize = CGSize(width: 500, height: 145)
        let resizedSize = CGSize(width: 580, height: 165)
        let currentOffset = CGSize(width: -104, height: -193)
        let adjustment = FloatingControlsOverlay.offsetAdjustment(
            for: CGSize(
                width: resizedSize.width - currentSize.width,
                height: resizedSize.height - currentSize.height
            )
        )
        let currentTopLeading = CGPoint(
            x: (availableSize.width - currentSize.width) / 2 + currentOffset.width,
            y: availableSize.height - 24 - currentSize.height + currentOffset.height
        )
        let resizedTopLeading = CGPoint(
            x: (availableSize.width - resizedSize.width) / 2
                + currentOffset.width + adjustment.width,
            y: availableSize.height - 24 - resizedSize.height
                + currentOffset.height + adjustment.height
        )

        XCTAssertEqual(resizedTopLeading.x, currentTopLeading.x)
        XCTAssertEqual(resizedTopLeading.y, currentTopLeading.y)
    }

    func testControlsShrinkOnlyForCompactPanel() {
        XCTAssertEqual(
            FloatingControlsOverlay.controlsScale(for: CGSize(width: 500, height: 116)),
            1
        )
        XCTAssertEqual(
            FloatingControlsOverlay.controlsScale(for: CGSize(width: 360, height: 84)),
            0.72
        )
    }

    func testPanelOriginAndOffsetRoundTrip() {
        let availableSize = CGSize(width: 1_000, height: 608)
        let panelSize = CGSize(width: 620, height: 132)
        let offset = CGSize(width: -80, height: -120)
        let origin = FloatingControlsOverlay.origin(
            for: offset,
            panelSize: panelSize,
            availableSize: availableSize
        )
        let roundTrip = FloatingControlsOverlay.offset(
            from: origin,
            panelSize: panelSize,
            availableSize: availableSize
        )

        XCTAssertEqual(roundTrip.width, offset.width)
        XCTAssertEqual(roundTrip.height, offset.height)
    }

    func testClampedOffsetStaysInsideWindow() {
        let availableSize = CGSize(width: 800, height: 500)
        let panelSize = CGSize(width: 500, height: 116)
        let clamped = FloatingControlsOverlay.clampedOffset(
            CGSize(width: 4_000, height: -4_000),
            panelSize: panelSize,
            availableSize: availableSize
        )
        let origin = FloatingControlsOverlay.origin(
            for: clamped,
            panelSize: panelSize,
            availableSize: availableSize
        )

        XCTAssertGreaterThanOrEqual(origin.x, 16)
        XCTAssertLessThanOrEqual(origin.x + panelSize.width, availableSize.width - 16)
        XCTAssertGreaterThanOrEqual(origin.y, 0)
        XCTAssertLessThanOrEqual(origin.y + panelSize.height, availableSize.height - 16)
    }

    func testTimelinePreviewSitsAboveTheControlBarWhenThereIsRoom() {
        let screen = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let bar = NSRect(x: 400, y: 40, width: 620, height: 132)
        let size = TimelinePreviewPlacement.panelSize(for: TimelinePreviewPlacement.defaultImage)
        let origin = TimelinePreviewPlacement.origin(cursorX: 700, size: size, avoiding: bar, in: screen)
        let preview = NSRect(origin: origin, size: size)

        XCTAssertEqual(origin.y, bar.maxY + TimelinePreviewPlacement.gap)
        XCTAssertFalse(preview.intersects(bar))
        XCTAssertEqual(origin.x, 700 - size.width / 2)
    }

    func testTimelinePreviewMovesBelowWhenTheBarIsAtTheTop() {
        let screen = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let bar = NSRect(x: 400, y: 760, width: 620, height: 132)
        let size = TimelinePreviewPlacement.panelSize(for: TimelinePreviewPlacement.defaultImage)
        let origin = TimelinePreviewPlacement.origin(cursorX: 700, size: size, avoiding: bar, in: screen)
        let preview = NSRect(origin: origin, size: size)

        XCTAssertEqual(origin.y, bar.minY - TimelinePreviewPlacement.gap - size.height)
        XCTAssertFalse(preview.intersects(bar))
        XCTAssertGreaterThanOrEqual(origin.y, screen.minY)
    }

    func testTimelineThumbnailKeepsVideoAspectAndGrowsPastTheOld160By90Box() {
        XCTAssertEqual(VideoThumbnailCache.pointSize(videoWidth: 1_920, videoHeight: 1_080), NSSize(width: 240, height: 135))
        XCTAssertEqual(VideoThumbnailCache.pointSize(videoWidth: 1_920, videoHeight: 800), NSSize(width: 240, height: 100))
        XCTAssertEqual(VideoThumbnailCache.pointSize(videoWidth: 1_080, videoHeight: 1_920), NSSize(width: 135, height: 240))
        XCTAssertGreaterThan(TimelinePreviewPlacement.panelSize(for: TimelinePreviewPlacement.defaultImage).width, 168)
    }
}
