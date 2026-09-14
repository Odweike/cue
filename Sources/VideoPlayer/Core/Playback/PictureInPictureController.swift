import AppKit

/// Picture-in-Picture via AppKit's private PIPViewController, same path as IINA.
@MainActor
final class PictureInPictureController: NSObject {
    private weak var viewModel: PlayerViewModel?
    private var pip: NSViewController?
    private var hosted: NSViewController?
    private weak var home: NSView?
    private(set) var isActive = false

    func attach(_ viewModel: PlayerViewModel) {
        self.viewModel = viewModel
    }

    func toggle() {
        if isActive {
            exit()
        } else {
            enter()
        }
    }

    func exitIfNeeded() {
        if isActive { exit() }
    }

    private func enter() {
        guard !isActive, let renderView = viewModel?.playbackEngine.renderView, let home = renderView.superview else {
            return
        }
        guard let pipClass = NSClassFromString("PIPViewController") as? NSViewController.Type else {
            return
        }
        self.home = home
        renderView.removeFromSuperview()

        let hosted = NSViewController()
        hosted.view = renderView
        self.hosted = hosted

        let pip = pipClass.init()
        pip.setValue(self, forKey: "delegate")
        pip.setValue(NSSize(width: 16, height: 9), forKey: "aspectRatio")
        pip.setValue(viewModel?.isPlaying ?? false, forKey: "playing")
        if pip.responds(to: NSSelectorFromString("setTitle:")) {
            pip.setValue(renderView.window?.title ?? "Cue", forKey: "title")
        }
        self.pip = pip
        pip.perform(NSSelectorFromString("presentViewControllerAsPictureInPicture:"), with: hosted)
        isActive = true
        viewModel?.setPictureInPicture(true)
    }

    private func restoreVideoView() {
        guard let renderView = viewModel?.playbackEngine.renderView, let home else { return }
        renderView.removeFromSuperview()
        renderView.translatesAutoresizingMaskIntoConstraints = false
        home.addSubview(renderView)
        NSLayoutConstraint.activate([
            renderView.leadingAnchor.constraint(equalTo: home.leadingAnchor),
            renderView.trailingAnchor.constraint(equalTo: home.trailingAnchor),
            renderView.topAnchor.constraint(equalTo: home.topAnchor),
            renderView.bottomAnchor.constraint(equalTo: home.bottomAnchor)
        ])
        self.home = nil
    }

    private func exit() {
        guard isActive, let pip, let hosted else { return }
        pip.perform(NSSelectorFromString("dismissViewController:"), with: hosted)
        if isActive {
            finishExit()
        }
    }

    private func finishExit() {
        guard isActive || home != nil else { return }
        restoreVideoView()
        pip = nil
        hosted = nil
        isActive = false
        viewModel?.setPictureInPicture(false)
    }

    func syncPlaying(_ isPlaying: Bool) {
        pip?.setValue(isPlaying, forKey: "playing")
    }

    @objc func pipShouldClose(_ pip: NSViewController) -> Bool { true }

    @objc func pipDidClose(_ pip: NSViewController) {
        finishExit()
    }

    @objc func pipActionPlay(_ pip: NSViewController) {
        viewModel?.playIfNeeded()
        self.pip?.setValue(true, forKey: "playing")
    }

    @objc func pipActionPause(_ pip: NSViewController) {
        viewModel?.pauseIfNeeded()
        self.pip?.setValue(false, forKey: "playing")
    }

    @objc func pipActionStop(_ pip: NSViewController) {
        viewModel?.pauseIfNeeded()
        exit()
    }
}
