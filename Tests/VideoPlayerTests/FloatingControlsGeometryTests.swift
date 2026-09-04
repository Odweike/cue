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
}
