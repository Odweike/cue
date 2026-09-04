import AppKit
import Foundation

enum VideoScalingMode: String, CaseIterable, Identifiable, Sendable {
    case fit
    case fill

    var id: Self { self }
}

struct PlaybackState: Equatable, Sendable {
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var isPlaying = false
    var volume: Float = 1
    var isMuted = false
    var playbackRate: Float = 1
    var videoScalingMode = VideoScalingMode.fit
}

@MainActor
protocol PlaybackEngine: AnyObject {
    var renderView: NSView { get }
    var currentURL: URL? { get }
    var state: PlaybackState { get }

    func open(_ url: URL)
    func play()
    func pause()
    func seek(to time: TimeInterval)
    func skip(by interval: TimeInterval)
    func setVolume(_ volume: Float)
    func setMuted(_ isMuted: Bool)
    func setPlaybackRate(_ rate: Float)
    func setVideoScalingMode(_ mode: VideoScalingMode)
}
