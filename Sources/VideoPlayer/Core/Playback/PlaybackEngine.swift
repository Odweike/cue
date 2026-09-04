import AppKit
import Foundation

struct PlaybackState: Equatable, Sendable {
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var isPlaying = false
    var volume: Float = 1
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
}
