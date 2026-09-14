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

    func testPlaybackSettingsSurviveRestartForTheSameFile() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cue-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let video = URL(fileURLWithPath: "/tmp/movie.mkv")
        let settings = VideoPlaybackSettings(
            audioTrackID: 2,
            audioLanguage: "jpn",
            volume: 0.4,
            playbackRate: 1.5
        )

        let firstStore = WatchHistoryStore(fileURL: fileURL)
        firstStore.upsert(url: video, position: 80, duration: 120, settings: settings)

        let secondStore = WatchHistoryStore(fileURL: fileURL)
        let restored = secondStore.item(for: video)?.settings
        XCTAssertEqual(restored?.audioTrackID, 2)
        XCTAssertEqual(restored?.audioLanguage, "jpn")
        XCTAssertEqual(restored?.volume, 0.4)
        XCTAssertEqual(restored?.playbackRate, 1.5)
        XCTAssertEqual(
            restored?.matchingAudioTrack(in: [
                AudioTrack(id: 1, title: nil, language: "eng", codec: nil, channelCount: 2, isSelected: false),
                AudioTrack(id: 2, title: nil, language: "jpn", codec: nil, channelCount: 2, isSelected: true)
            ])?.id,
            2
        )
    }
}
