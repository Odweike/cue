import AppKit
import SwiftUI

struct PlayerRootView: View {
    let viewModel: PlayerViewModel
    @State private var isDropTargeted = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            AVPlayerContainerView(playerView: viewModel.playbackEngine.renderView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transaction { $0.animation = nil }

            if viewModel.currentURL == nil {
                WelcomeView {
                    if let url = VideoFilePicker.chooseVideo() {
                        viewModel.open(url)
                    }
                }
            } else {
                SubtitleOverlay(
                    cues: viewModel.visibleSubtitleCues,
                    styleForTrack: viewModel.subtitleStyle(for:)
                )

                FloatingControlsOverlay(viewModel: viewModel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: viewModel.currentURL)
        .overlay(alignment: .trailing) {
            if viewModel.currentURL != nil {
                PlaybackSettingsPanel(viewModel: viewModel)
                    .frame(width: 400)
                    .frame(maxHeight: .infinity)
                    .background(Color(red: 0.13, green: 0.13, blue: 0.14))
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(.white.opacity(0.08))
                            .frame(width: 1)
                    }
                    .offset(x: viewModel.isSettingsPresented ? 0 : 400)
                    .opacity(viewModel.isSettingsPresented ? 1 : 0)
                    .allowsHitTesting(viewModel.isSettingsPresented)
                    .transaction { $0.animation = nil }
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.tint, lineWidth: 3)
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: VideoFilePicker.canOpen) else { return false }
            viewModel.open(url)
            return true
        } isTargeted: { isTargeted in
            isDropTargeted = isTargeted
        }
        .onOpenURL { url in
            if VideoFilePicker.canOpen(url) {
                viewModel.open(url)
            }
        }
        .background {
            SpacePlaybackCatcher(viewModel: viewModel)
        }
        .navigationTitle(viewModel.currentURL?.lastPathComponent ?? "Cue")
    }
}

private struct SpacePlaybackCatcher: NSViewRepresentable {
    let viewModel: PlayerViewModel

    func makeNSView(context: Context) -> SpacePlaybackCatcherView {
        let view = SpacePlaybackCatcherView()
        view.viewModel = viewModel
        return view
    }

    func updateNSView(_ nsView: SpacePlaybackCatcherView, context: Context) {
        nsView.viewModel = viewModel
    }
}

private final class SpacePlaybackCatcherView: NSView {
    var viewModel: PlayerViewModel?
    nonisolated(unsafe) private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func startMonitoring() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    private func stopMonitoring() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard viewModel?.currentURL != nil else { return event }
        guard event.keyCode == 49 else { return event }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.isEmpty else { return event }
        if Self.isEditingText { return event }
        if !event.isARepeat {
            viewModel?.togglePlayback()
        }
        return nil
    }

    private static var isEditingText: Bool {
        let responder = NSApp.keyWindow?.firstResponder
        return responder is NSTextView || responder is NSTextField
    }
}

private struct WelcomeView: View {
    let openVideo: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 58))
                .foregroundStyle(.white.opacity(0.9))

            Text("Open a video to start watching")
                .font(.title2.weight(.medium))
                .foregroundStyle(.white)

            Button("Open Video…", action: openVideo)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("o")
        }
        .padding(40)
        .accessibilityElement(children: .contain)
    }
}
