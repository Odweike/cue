import Foundation
import Observation

@MainActor
@Observable
final class PlayerViewModel {
    let playbackEngine: any PlaybackEngine
    private(set) var currentURL: URL?
    private(set) var playbackState = PlaybackState()

    init(playbackEngine: any PlaybackEngine) {
        self.playbackEngine = playbackEngine
    }

    func open(_ url: URL) {
        playbackEngine.open(url)
        currentURL = url
        refreshPlaybackState()
    }

    func refreshPlaybackState() {
        playbackState = playbackEngine.state
    }

    func togglePlayback() {
        if playbackState.isPlaying {
            playbackEngine.pause()
        } else {
            playbackEngine.play()
        }
        refreshPlaybackState()
    }

    func seek(to time: TimeInterval) {
        playbackEngine.seek(to: time)
        refreshPlaybackState()
    }

    func skip(by interval: TimeInterval) {
        playbackEngine.skip(by: interval)
        refreshPlaybackState()
    }

    func setVolume(_ volume: Float) {
        playbackEngine.setVolume(volume)
        refreshPlaybackState()
    }
}
