import XCTest
@testable import VideoPlayer

@MainActor
final class WatchHistoryStoreTests: XCTestCase {
    func testUnfinishedItemsAreRememberedAndFinishedOnesDropOut() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cue-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = WatchHistoryStore(fileURL: fileURL)
        let video = URL(fileURLWithPath: "/tmp/movie.mkv")

        store.upsert(url: video, position: 80, duration: 120)
        XCTAssertEqual(store.unfinished().map(\.fileName), ["movie.mkv"])

        store.upsert(url: video, position: 119, duration: 120)
        XCTAssertTrue(store.unfinished().isEmpty)
    }
}
