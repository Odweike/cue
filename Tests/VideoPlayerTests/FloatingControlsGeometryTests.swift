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
}
