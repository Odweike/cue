import AVFoundation
import AVKit

@MainActor
final class AVPlaybackEngine: PlaybackEngine {
    private let player = AVPlayer()
    private let playerView = AVPlayerView()

    private(set) var currentURL: URL?
    var renderView: NSView { playerView }
    var state: PlaybackState {
        PlaybackState(
            currentTime: finiteSeconds(player.currentTime().seconds),
            duration: finiteSeconds(player.currentItem?.duration.seconds),
            isPlaying: player.rate != 0 || player.timeControlStatus == .waitingToPlayAtSpecifiedRate,
            volume: player.volume
        )
    }

    init() {
        playerView.player = player
        playerView.controlsStyle = .none
        playerView.videoGravity = .resizeAspect
    }

    func open(_ url: URL) {
        currentURL = url
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.play()
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func seek(to time: TimeInterval) {
        let target = min(max(time, 0), state.duration)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    func skip(by interval: TimeInterval) {
        seek(to: state.currentTime + interval)
    }

    func setVolume(_ volume: Float) {
        player.volume = min(max(volume, 0), 1)
    }

    private func finiteSeconds(_ value: Double?) -> TimeInterval {
        guard let value, value.isFinite, value >= 0 else { return 0 }
        return value
    }
}
