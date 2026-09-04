import AppKit
import Foundation

@MainActor
protocol PlaybackEngine: AnyObject {
    var renderView: NSView { get }
    var currentURL: URL? { get }

    func open(_ url: URL)
    func play()
    func pause()
}

