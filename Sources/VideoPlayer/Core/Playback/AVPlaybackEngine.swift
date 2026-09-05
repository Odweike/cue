import AVFoundation
import AVKit

@MainActor
final class AVPlaybackEngine: PlaybackEngine {
    private let player = AVPlayer()
    private let playerView = AVPlayerView()
    private var playbackRate: Float = 1
    private var videoScalingMode = VideoScalingMode.fit
    private var aspectRatio = VideoRatio.automatic
    private var cropRatio = VideoRatio.automatic
    private var rotation = VideoRotation.degrees0
    private var hardwareDecoding = true
    private var deinterlacing = false
    private var videoEqualizer = VideoEqualizer()
    private var audioDelay: TimeInterval = 0

    private(set) var currentURL: URL?
    var renderView: NSView { playerView }
    var state: PlaybackState {
        PlaybackState(
            currentTime: finiteSeconds(player.currentTime().seconds),
            duration: finiteSeconds(player.currentItem?.duration.seconds),
            isPlaying: player.rate != 0 || player.timeControlStatus == .waitingToPlayAtSpecifiedRate,
            volume: player.volume,
            isMuted: player.isMuted,
            playbackRate: playbackRate,
            videoScalingMode: videoScalingMode,
            aspectRatio: aspectRatio,
            cropRatio: cropRatio,
            rotation: rotation,
            hardwareDecoding: hardwareDecoding,
            deinterlacing: deinterlacing,
            videoEqualizer: videoEqualizer,
            audioDelay: audioDelay
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
        player.playImmediately(atRate: playbackRate)
    }

    func play() {
        player.playImmediately(atRate: playbackRate)
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

    func setMuted(_ isMuted: Bool) {
        player.isMuted = isMuted
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = min(max(rate, 0.25), 16)
        if player.rate != 0 {
            player.rate = playbackRate
        }
    }

    func setVideoScalingMode(_ mode: VideoScalingMode) {
        videoScalingMode = mode
        playerView.videoGravity = mode == .fit ? .resizeAspect : .resizeAspectFill
    }

    func setAspectRatio(_ ratio: VideoRatio) {
        aspectRatio = ratio
    }

    func setCropRatio(_ ratio: VideoRatio) {
        cropRatio = ratio
    }

    func setRotation(_ rotation: VideoRotation) {
        self.rotation = rotation
    }

    func setHardwareDecoding(_ isEnabled: Bool) {
        hardwareDecoding = isEnabled
    }

    func setDeinterlacing(_ isEnabled: Bool) {
        deinterlacing = isEnabled
    }

    func setVideoEqualizer(_ equalizer: VideoEqualizer) {
        videoEqualizer = equalizer
    }

    func audioTracks() -> [AudioTrack] {
        []
    }

    func selectAudioTrack(_ id: Int64) {}

    func setAudioDelay(_ delay: TimeInterval) {
        audioDelay = min(max(delay, -5), 5)
    }

    private func finiteSeconds(_ value: Double?) -> TimeInterval {
        guard let value, value.isFinite, value >= 0 else { return 0 }
        return value
    }
}
