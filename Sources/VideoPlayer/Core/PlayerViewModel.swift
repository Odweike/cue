import Foundation
import Observation

@MainActor
@Observable
final class PlayerViewModel {
    let playbackEngine: any PlaybackEngine
    private(set) var currentURL: URL?
    private(set) var playbackState = PlaybackState()
    private(set) var subtitleTracks: [SubtitleTrack] = []

    init(playbackEngine: any PlaybackEngine) {
        self.playbackEngine = playbackEngine
    }

    func open(_ url: URL) {
        subtitleTracks.removeAll()
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

    func setMuted(_ isMuted: Bool) {
        playbackEngine.setMuted(isMuted)
        refreshPlaybackState()
    }

    func setPlaybackRate(_ rate: Float) {
        playbackEngine.setPlaybackRate(rate)
        refreshPlaybackState()
    }

    func setVideoScalingMode(_ mode: VideoScalingMode) {
        playbackEngine.setVideoScalingMode(mode)
        refreshPlaybackState()
    }

    var visibleSubtitleCues: [SubtitleCue] {
        let time = playbackState.currentTime
        return subtitleTracks
            .filter(\.isEnabled)
            .flatMap(\.cues)
            .filter { $0.startTime <= time && time < $0.endTime }
    }

    func importSubtitles(_ url: URL) throws {
        let trackID = UUID()
        let contents = try String(contentsOf: url, encoding: .utf8)
        let cues = try SubtitleParser.parse(contents, fileExtension: url.pathExtension, trackID: trackID)
        let isEnabled = subtitleTracks.filter(\.isEnabled).count < 2
        subtitleTracks.append(
            SubtitleTrack(id: trackID, name: url.lastPathComponent, cues: cues, isEnabled: isEnabled)
        )
    }

    func setSubtitleTrack(_ trackID: UUID, enabled: Bool) {
        guard let index = subtitleTracks.firstIndex(where: { $0.id == trackID }) else { return }
        if enabled, subtitleTracks.filter(\.isEnabled).count >= 2 { return }
        subtitleTracks[index].isEnabled = enabled
    }
}
