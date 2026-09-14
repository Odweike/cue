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
                .onTapGesture {
                    if viewModel.isSettingsPresented {
                        viewModel.toggleSettingsPresented()
                    }
                }

            if viewModel.currentURL == nil {
                WelcomeView(viewModel: viewModel)
            } else {
                SubtitleOverlay(
                    cues: viewModel.visibleSubtitleCues,
                    styleForTrack: viewModel.subtitleStyle(for:)
                )

                FloatingControlsOverlay(viewModel: viewModel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .topLeading) {
            if viewModel.currentURL != nil, let percent = viewModel.volumeHUDPercent {
                Text("\(percent)%")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(.top, 14)
                    .padding(.leading, 16)
                    .allowsHitTesting(false)
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
            PlaybackKeyCatcher(viewModel: viewModel)
        }
        .alert("Playback Error", isPresented: Binding(
            get: { viewModel.playbackError != nil },
            set: { if !$0 { viewModel.dismissPlaybackError() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.playbackError ?? "Unknown error")
        }
        .navigationTitle(viewModel.currentURL?.lastPathComponent ?? "Cue")
    }
}

private struct PlaybackKeyCatcher: NSViewRepresentable {
    let viewModel: PlayerViewModel

    func makeNSView(context: Context) -> PlaybackKeyCatcherView {
        let view = PlaybackKeyCatcherView()
        view.viewModel = viewModel
        return view
    }

    func updateNSView(_ nsView: PlaybackKeyCatcherView, context: Context) {
        nsView.viewModel = viewModel
    }
}

private final class PlaybackKeyCatcherView: NSView {
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
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function])
        guard modifiers.isEmpty else { return event }
        if Self.isEditingText { return event }
        switch event.keyCode {
        case 49: // Space
            if !event.isARepeat {
                viewModel?.togglePlayback()
            }
            return nil
        case 123: // Left arrow
            viewModel?.skip(by: -10)
            return nil
        case 124: // Right arrow
            viewModel?.skip(by: 10)
            return nil
        case 125: // Down arrow
            viewModel?.nudgeVolume(by: -0.05)
            return nil
        case 126: // Up arrow
            viewModel?.nudgeVolume(by: 0.05)
            return nil
        case 37: // L
            if !event.isARepeat {
                viewModel?.cycleABLoop()
            }
            return nil
        default:
            return event
        }
    }

    private static var isEditingText: Bool {
        let responder = NSApp.keyWindow?.firstResponder
        return responder is NSTextView || responder is NSTextField
    }
}

private struct WelcomeView: View {
    let viewModel: PlayerViewModel

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 16) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .symbolRenderingMode(.hierarchical)

                Text("Open a video to start watching")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                Button("Open Video…") {
                    if let url = VideoFilePicker.chooseVideo() {
                        viewModel.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("o")
            }

            if !viewModel.continueWatching.isEmpty {
                continueWatchingPanel
            }
        }
        .padding(40)
        .accessibilityElement(children: .contain)
    }

    private var continueWatchingPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Continue watching")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 6)

            ForEach(Array(viewModel.continueWatching.prefix(6).enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Divider()
                        .overlay(Color.primary.opacity(0.12))
                        .padding(.leading, 52)
                }
                ContinueWatchingRow(item: item) {
                    viewModel.resumeWatching(item)
                } onRemove: {
                    viewModel.forgetWatchHistory(item.id)
                }
            }
        }
        .frame(width: 440)
        .padding(.bottom, 8)
        .background {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            shape
                .fill(.regularMaterial)
                .overlay {
                    shape.fill(.black.opacity(0.28))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        }
    }
}

private struct ContinueWatchingRow: View {
    let item: WatchHistoryItem
    let onResume: () -> Void
    let onRemove: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onResume) {
                HStack(spacing: 12) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.white.opacity(0.16)))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.fileName)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            progressBar
                                .frame(maxWidth: .infinity)
                            Text(progressText)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.72))
                                .fixedSize()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(.white.opacity(isHovered ? 0.14 : 0.08)))
            }
            .buttonStyle(.plain)
            .help("Remove from history")
            .opacity(isHovered ? 1 : 0.55)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isHovered ? Color.white.opacity(0.06) : Color.clear)
        .onHover { isHovered = $0 }
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(.white.opacity(0.16))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.9))
                        .frame(width: max(geometry.size.width * progress, 3))
                }
        }
        .frame(height: 3)
    }

    private var progress: CGFloat {
        guard item.duration > 0 else { return 0 }
        return CGFloat(min(max(item.position / item.duration, 0), 1))
    }

    private var progressText: String {
        let watched = PlaybackTimeFormat.string(
            from: item.position,
            includingHours: item.duration >= 3_600
        )
        if item.duration > 0 {
            let total = PlaybackTimeFormat.string(
                from: item.duration,
                includingHours: item.duration >= 3_600
            )
            return "\(watched) / \(total)"
        }
        return watched
    }
}
