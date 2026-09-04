import Foundation
import Observation

@MainActor
@Observable
final class PlayerViewModel {
    let playbackEngine: any PlaybackEngine
    private(set) var currentURL: URL?

    init(playbackEngine: any PlaybackEngine) {
        self.playbackEngine = playbackEngine
    }

    func open(_ url: URL) {
        playbackEngine.open(url)
        currentURL = url
    }
}

