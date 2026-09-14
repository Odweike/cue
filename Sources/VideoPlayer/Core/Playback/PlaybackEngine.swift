import AppKit
import Foundation

enum VideoScalingMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case fit
    case fill

    var id: Self { self }
}

enum VideoRatio: String, CaseIterable, Identifiable, Codable, Sendable {
    case automatic
    case ratio4x3 = "4:3"
    case ratio16x9 = "16:9"
    case ratio16x10 = "16:10"
    case ratio21x9 = "21:9"
    case ratio5x4 = "5:4"

    var id: Self { self }
    var mpvValue: String { self == .automatic ? "no" : rawValue }
}

enum VideoRotation: Int, CaseIterable, Identifiable, Codable, Sendable {
    case degrees0 = 0
    case degrees90 = 90
    case degrees180 = 180
    case degrees270 = 270

    var id: Self { self }
}

struct VideoEqualizer: Codable, Equatable, Sendable {
    var brightness = 0.0
    var contrast = 0.0
    var saturation = 0.0
    var gamma = 0.0
    var hue = 0.0
}

struct PlaybackState: Equatable, Sendable {
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var isPlaying = false
    var volume: Float = 1
    var isMuted = false
    var playbackRate: Float = 1
    var videoScalingMode = VideoScalingMode.fit
    var aspectRatio = VideoRatio.automatic
    var cropRatio = VideoRatio.automatic
    var rotation = VideoRotation.degrees0
    var hardwareDecoding = true
    var deinterlacing = false
    var videoEqualizer = VideoEqualizer()
    var audioDelay: TimeInterval = 0

    func hasSameControls(as other: PlaybackState) -> Bool {
        volume == other.volume
            && isMuted == other.isMuted
            && playbackRate == other.playbackRate
            && videoScalingMode == other.videoScalingMode
            && aspectRatio == other.aspectRatio
            && cropRatio == other.cropRatio
            && rotation == other.rotation
            && hardwareDecoding == other.hardwareDecoding
            && deinterlacing == other.deinterlacing
            && videoEqualizer == other.videoEqualizer
            && audioDelay == other.audioDelay
    }
}

struct PlaybackChapter: Equatable, Sendable, Identifiable {
    var id: TimeInterval { start }
    var start: TimeInterval
    var title: String
}

enum PlaybackEngineEvent: Sendable {
    case fileReady
    case failedToOpen(String)
}

@MainActor
protocol PlaybackEngine: AnyObject {
    var eventHandler: ((PlaybackEngineEvent) -> Void)? { get set }
    var renderView: NSView { get }
    var currentURL: URL? { get }
    var state: PlaybackState { get }
    var loopA: TimeInterval? { get }
    var loopB: TimeInterval? { get }

    func playbackClock() -> (time: TimeInterval, duration: TimeInterval, isPlaying: Bool)
    func open(_ url: URL)
    func play()
    func pause()
    func seek(to time: TimeInterval, exact: Bool)
    func skip(by interval: TimeInterval)
    func setVolume(_ volume: Float)
    func setMuted(_ isMuted: Bool)
    func setPlaybackRate(_ rate: Float)
    func setVideoScalingMode(_ mode: VideoScalingMode)
    func setAspectRatio(_ ratio: VideoRatio)
    func setCropRatio(_ ratio: VideoRatio)
    func setRotation(_ rotation: VideoRotation)
    func setHardwareDecoding(_ isEnabled: Bool)
    func setDeinterlacing(_ isEnabled: Bool)
    func setVideoEqualizer(_ equalizer: VideoEqualizer)
    func audioTracks() -> [AudioTrack]
    func subtitleStreams() -> [SubtitleStream]
    func selectAudioTrack(_ id: Int64)
    func setAudioDelay(_ delay: TimeInterval)
    func chapters() -> [PlaybackChapter]
    func cycleABLoop(at time: TimeInterval)
    func clearABLoop()
}
