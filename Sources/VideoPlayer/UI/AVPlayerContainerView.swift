import AppKit
import SwiftUI

struct AVPlayerContainerView: NSViewRepresentable {
    let playerView: NSView

    func makeNSView(context: Context) -> NSView {
        playerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

