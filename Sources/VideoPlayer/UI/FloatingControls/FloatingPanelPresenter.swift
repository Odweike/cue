import AppKit
import SwiftUI

struct FloatingPanelPresenter: NSViewRepresentable {
    let viewModel: PlayerViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> PanelAnchorView {
        let anchor = PanelAnchorView()
        anchor.windowDidChange = { window in
            context.coordinator.attach(to: window)
        }
        return anchor
    }

    func updateNSView(_ nsView: PanelAnchorView, context: Context) {
        context.coordinator.setVisible(viewModel.currentURL != nil)
    }

    static func dismantleNSView(_ nsView: PanelAnchorView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        private weak var parentWindow: NSWindow?
        private let panel: NSPanel
        private var shouldBeVisible = false

        init(viewModel: PlayerViewModel) {
            panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 104),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.contentView = NSHostingView(rootView: FloatingControlBar(viewModel: viewModel))
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.isFloatingPanel = true
            panel.isMovableByWindowBackground = true
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.fullScreenAuxiliary]
            panel.setFrameAutosaveName("VideoPlayerFloatingControls")
        }

        func attach(to window: NSWindow?) {
            guard parentWindow !== window else { return }
            detach()
            guard let window else { return }

            parentWindow = window
            window.addChildWindow(panel, ordered: .above)
            let restoredFrame = panel.setFrameUsingName("VideoPlayerFloatingControls")
            let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            let visiblePanelArea = visibleFrame.intersection(panel.frame)
            let restoredFrameIsUsable = visiblePanelArea.width >= panel.frame.width * 0.8
                && visiblePanelArea.height >= panel.frame.height * 0.8
            if !restoredFrame || !restoredFrameIsUsable {
                positionNearBottom(of: window)
            }
            updateVisibility()
        }

        func setVisible(_ visible: Bool) {
            shouldBeVisible = visible
            updateVisibility()
        }

        func detach() {
            parentWindow?.removeChildWindow(panel)
            parentWindow = nil
            panel.orderOut(nil)
        }

        private func updateVisibility() {
            guard parentWindow != nil else { return }
            shouldBeVisible ? panel.orderFront(nil) : panel.orderOut(nil)
        }

        private func positionNearBottom(of window: NSWindow) {
            let parentFrame = window.frame
            let origin = NSPoint(
                x: parentFrame.midX - panel.frame.width / 2,
                y: parentFrame.minY + 36
            )
            panel.setFrameOrigin(origin)
        }
    }
}

final class PanelAnchorView: NSView {
    var windowDidChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowDidChange?(window)
    }
}
