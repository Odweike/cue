import AVFoundation
import AVKit

@MainActor
final class AVPlaybackEngine: PlaybackEngine {
    private let player = AVPlayer()
    private let playerView = AVPlayerView()

    private(set) var currentURL: URL?
    var renderView: NSView { playerView }

    init() {
        playerView.player = player
        playerView.controlsStyle = .floating
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
}

