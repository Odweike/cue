import XCTest
@testable import VideoPlayer

final class RulerSliderTests: XCTestCase {
    func testLinearEndsSitOnFirstAndLastTick() {
        let width: CGFloat = 240
        let thumb: CGFloat = 10
        XCTAssertEqual(RulerSlider.x(forPosition: 0, width: width, thumbSize: thumb), thumb / 2)
        XCTAssertEqual(RulerSlider.x(forPosition: 1, width: width, thumbSize: thumb), width - thumb / 2)
    }

    func testLogSpeedPuts1xOneThirdAlongTheTrack() {
        let position = RulerSlider.position(for: 1, range: 0.25...16, logScale: true)
        XCTAssertEqual(position, 1 / 3, accuracy: 0.0001)
        XCTAssertEqual(
            RulerSlider.value(at: 1 / 3, range: 0.25...16, logScale: true),
            1,
            accuracy: 0.0001
        )
    }
}
