import AppKit
import SwiftUI

struct FloatingControlBar: View {
    let viewModel: PlayerViewModel
    @State private var showsSubtitles = false

    var body: some View {
        TimelineView(
            .animation(
                paused: !viewModel.isPlaying && !viewModel.isScrubbing
            )
        ) { context in
            controlBar
                .onChange(of: context.date) { _, _ in
                    viewModel.refreshPlaybackState()
                }
                .transaction { $0.animation = nil }
        }
    }

    private var controlBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                volumeControl
                Spacer(minLength: 8)
                playbackButtons
                Spacer(minLength: 8)
                trailingActions
            }

            timeline
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
        .foregroundStyle(.white)
    }

    private var volumeControl: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.toggleMuted()
            } label: {
                Image(systemName: volumeSymbol)
                    .frame(width: 18)
            }
            .buttonStyle(.plain)
            .help(viewModel.playbackState.isMuted ? "Unmute" : "Mute")
            .accessibilityLabel(viewModel.playbackState.isMuted ? "Unmute" : "Mute")

            Slider(
                value: Binding(
                    get: { Double(viewModel.playbackState.volume) },
                    set: { viewModel.setVolume(Float($0)) }
                ),
                in: 0...1
            )
            .tint(.blue)
            .frame(minWidth: 48, maxWidth: 82)
        }
        .frame(maxWidth: 120)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Volume")
    }

    private var playbackButtons: some View {
        HStack(spacing: 20) {
            controlButton("backward.fill", size: 22, label: "Back 10 seconds") {
                viewModel.skip(by: -10)
            }

            Button {
                viewModel.togglePlayback()
            } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 29, weight: .medium))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")

            controlButton("forward.fill", size: 22, label: "Forward 10 seconds") {
                viewModel.skip(by: 10)
            }
        }
    }

    private var trailingActions: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.cycleABLoop()
            } label: {
                Text(abLoopTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .help("A–B Loop")
            .accessibilityLabel("A–B Loop")

            Button {
                viewModel.togglePictureInPicture()
            } label: {
                Image(systemName: viewModel.isPictureInPicture ? "pip.exit" : "pip.enter")
            }
            .help("Picture in Picture")

            Button {
                NSApp.keyWindow?.toggleFullScreen(nil)
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .help("Full Screen")

            Button {
                showsSubtitles.toggle()
            } label: {
                Image(systemName: "captions.bubble")
            }
            .help("Subtitles")
            .popover(isPresented: $showsSubtitles, arrowEdge: .leading) {
                SubtitleTracksPanel(viewModel: viewModel)
            }

            Button {
                viewModel.toggleSettingsPresented()
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .help("Playback Settings")
        }
        .font(.system(size: 17, weight: .medium))
        .buttonStyle(.plain)
        .frame(maxWidth: 180, alignment: .trailing)
    }

    private var abLoopTitle: String {
        if viewModel.loopA == nil { return "A–B" }
        if viewModel.loopB == nil { return "A·" }
        return "A–B·"
    }

    private var timeline: some View {
        let showsHours = viewModel.duration >= 3_600
        let displayedTime = viewModel.isScrubbing
            ? viewModel.scrubTime
            : viewModel.currentTime

        return HStack(spacing: 10) {
            Text(PlaybackTimeFormat.string(from: displayedTime, includingHours: showsHours))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(minWidth: 82, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
                .allowsHitTesting(false)

            TimelineSlider(
                value: displayedTime,
                range: 0...max(viewModel.duration, 0.01),
                chapters: viewModel.chapters,
                loopA: viewModel.loopA,
                loopB: viewModel.loopB,
                thumbnail: { viewModel.thumbnail(at: $0) },
                onBeginScrubbing: { viewModel.beginScrubbing() },
                onScrub: { viewModel.updateScrubbing(to: $0) },
                onEndScrubbing: { viewModel.endScrubbing() }
            )
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Timeline")

            Text(PlaybackTimeFormat.string(from: viewModel.duration, includingHours: showsHours))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(minWidth: 82, alignment: .trailing)
                .fixedSize(horizontal: true, vertical: false)
                .allowsHitTesting(false)
        }
    }

    private var volumeSymbol: String {
        if viewModel.playbackState.isMuted {
            return "speaker.slash.fill"
        }

        return switch viewModel.playbackState.volume {
        case 0: "speaker.slash.fill"
        case ..<0.5: "speaker.wave.1.fill"
        default: "speaker.wave.2.fill"
        }
    }

    private func controlButton(
        _ systemName: String,
        size: CGFloat,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .frame(width: 28, height: 34)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct FloatingControlsOverlay: View {
    let viewModel: PlayerViewModel

    static let minimumPanelWidth: CGFloat = 360
    static let minimumPanelHeight: CGFloat = 84
    static let regularPanelWidth: CGFloat = 500
    static let regularPanelHeight: CGFloat = 116
    static let bottomPadding: CGFloat = 24

    @AppStorage("FloatingControlsOffsetX") private var storedOffsetX = 0.0
    @AppStorage("FloatingControlsOffsetY") private var storedOffsetY = 0.0
    @AppStorage("CueControlsWidth") private var storedWidth = 620.0
    @AppStorage("CueControlsHeight") private var storedHeight = 132.0
    @GestureState private var resizeOffset = CGSize.zero
    @GestureState private var moveOffset = CGSize.zero
    @State private var isVisible = true
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            let panelSize = panelSize(in: geometry.size)
            let resizeDelta = CGSize(
                width: panelSize.width - storedWidth,
                height: panelSize.height - storedHeight
            )
            let baseOffset = CGSize(
                width: storedOffsetX + Self.offsetAdjustment(for: resizeDelta).width,
                height: storedOffsetY + Self.offsetAdjustment(for: resizeDelta).height
            )
            let displayedOffset = Self.clampedOffset(
                CGSize(
                    width: baseOffset.width + moveOffset.width,
                    height: baseOffset.height + moveOffset.height
                ),
                panelSize: panelSize,
                availableSize: geometry.size
            )
            let origin = Self.origin(
                for: displayedOffset,
                panelSize: panelSize,
                availableSize: geometry.size
            )

            panelChrome(panelSize: panelSize, in: geometry.size)
                .position(
                    x: origin.x + panelSize.width / 2,
                    y: origin.y + panelSize.height / 2
                )
                .opacity(isVisible ? 1 : 0)
                .allowsHitTesting(isVisible)
                .onAppear {
                    keepPanelVisible(in: geometry.size)
                    showControls()
                }
                .onChange(of: geometry.size) { _, newSize in
                    keepPanelVisible(in: newSize)
                }
                .onChange(of: viewModel.isPlaying) { _, playing in
                    if playing {
                        scheduleHide()
                    } else {
                        showControls()
                    }
                }
                .onChange(of: viewModel.isSettingsPresented) { _, isOpen in
                    if isOpen {
                        showControls()
                    } else {
                        scheduleHide()
                    }
                }
        }
        .background {
            MouseActivityCatcher(onActivity: showControls)
        }
        .animation(.easeOut(duration: 0.22), value: isVisible)
        .ignoresSafeArea()
    }

    private func showControls() {
        isVisible = true
        scheduleHide()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        guard viewModel.isPlaying, !viewModel.isSettingsPresented else {
            hideTask = nil
            isVisible = true
            return
        }
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            guard viewModel.isPlaying, !viewModel.isSettingsPresented else { return }
            isVisible = false
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }

    private func panelChrome(panelSize: CGSize, in availableSize: CGSize) -> some View {
        let controlsScale = Self.controlsScale(for: panelSize)

        return FloatingControlBar(viewModel: viewModel)
            .frame(
                width: panelSize.width / controlsScale,
                height: panelSize.height / controlsScale
            )
            .scaleEffect(controlsScale)
            .frame(width: panelSize.width, height: panelSize.height)
            .background {
                PanelBackground()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .gesture(moveGesture(in: availableSize))
            }
            .overlay(alignment: .bottomTrailing) {
                resizeHandle(in: availableSize)
            }
    }

    private func moveGesture(in availableSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .updating($moveOffset) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                storedOffsetX += value.translation.width
                storedOffsetY += value.translation.height
                keepPanelVisible(in: availableSize)
            }
    }

    private func resizeHandle(in availableSize: CGSize) -> some View {
        Color.clear
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .pointerStyle(.frameResize(position: .bottomTrailing))
            .gesture(resizeGesture(in: availableSize))
            .accessibilityHidden(true)
            .help("Drag to resize")
    }

    private func resizeGesture(in availableSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .updating($resizeOffset) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                let resizedSize = resizedPanelSize(for: value.translation, in: availableSize)
                let offsetAdjustment = Self.offsetAdjustment(
                    for: CGSize(
                        width: resizedSize.width - storedWidth,
                        height: resizedSize.height - storedHeight
                    )
                )

                storedWidth = resizedSize.width
                storedHeight = resizedSize.height
                storedOffsetX += offsetAdjustment.width
                storedOffsetY += offsetAdjustment.height
                keepPanelVisible(in: availableSize)
            }
    }

    static func offsetAdjustment(for sizeDelta: CGSize) -> CGSize {
        CGSize(width: sizeDelta.width / 2, height: sizeDelta.height)
    }

    static func controlsScale(for panelSize: CGSize) -> CGFloat {
        min(
            max(
                min(panelSize.width / regularPanelWidth, panelSize.height / regularPanelHeight),
                0.72
            ),
            1
        )
    }

    static func origin(
        for offset: CGSize,
        panelSize: CGSize,
        availableSize: CGSize
    ) -> CGPoint {
        CGPoint(
            x: (availableSize.width - panelSize.width) / 2 + offset.width,
            y: availableSize.height - bottomPadding - panelSize.height + offset.height
        )
    }

    static func offset(
        from origin: CGPoint,
        panelSize: CGSize,
        availableSize: CGSize
    ) -> CGSize {
        CGSize(
            width: origin.x - (availableSize.width - panelSize.width) / 2,
            height: origin.y - (availableSize.height - bottomPadding - panelSize.height)
        )
    }

    static func clampedOffset(
        _ offset: CGSize,
        panelSize: CGSize,
        availableSize: CGSize
    ) -> CGSize {
        let maxHorizontalOffset = max((availableSize.width - panelSize.width) / 2 - 16, 0)
        let maximumUpwardOffset = max(availableSize.height - panelSize.height - 48, 0)
        return CGSize(
            width: min(max(offset.width, -maxHorizontalOffset), maxHorizontalOffset),
            height: min(max(offset.height, -maximumUpwardOffset), 8)
        )
    }

    private func panelSize(in availableSize: CGSize) -> CGSize {
        resizedPanelSize(for: resizeOffset, in: availableSize)
    }

    private func resizedPanelSize(for translation: CGSize, in availableSize: CGSize) -> CGSize {
        let currentLeft = (availableSize.width - storedWidth) / 2 + storedOffsetX
        let currentTop = availableSize.height - Self.bottomPadding - storedHeight + storedOffsetY
        let maximumWidth = min(
            max(availableSize.width - 16 - currentLeft, Self.minimumPanelWidth),
            760
        )
        let maximumHeight = min(
            max(availableSize.height - 16 - currentTop, Self.minimumPanelHeight),
            168
        )

        return CGSize(
            width: min(max(storedWidth + translation.width, Self.minimumPanelWidth), maximumWidth),
            height: min(max(storedHeight + translation.height, Self.minimumPanelHeight), maximumHeight)
        )
    }

    private func keepPanelVisible(in availableSize: CGSize) {
        let maximumWidth = min(max(availableSize.width - 32, Self.minimumPanelWidth), 760)
        storedWidth = min(max(storedWidth, Self.minimumPanelWidth), maximumWidth)
        storedHeight = min(max(storedHeight, Self.minimumPanelHeight), 168)

        let clamped = Self.clampedOffset(
            CGSize(width: storedOffsetX, height: storedOffsetY),
            panelSize: CGSize(width: storedWidth, height: storedHeight),
            availableSize: availableSize
        )
        storedOffsetX = clamped.width
        storedOffsetY = clamped.height
    }
}

private struct MouseActivityCatcher: NSViewRepresentable {
    var onActivity: () -> Void

    func makeNSView(context: Context) -> MouseActivityCatcherView {
        let view = MouseActivityCatcherView()
        view.onActivity = onActivity
        return view
    }

    func updateNSView(_ nsView: MouseActivityCatcherView, context: Context) {
        nsView.onActivity = onActivity
    }
}

private final class MouseActivityCatcherView: NSView {
    var onActivity: (() -> Void)?
    nonisolated(unsafe) private var monitor: Any?
    private var lastMouseLocation = NSPoint.zero

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
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
        lastMouseLocation = NSEvent.mouseLocation
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    private func handle(_ event: NSEvent) {
        let location = NSEvent.mouseLocation
        let moved = hypot(location.x - lastMouseLocation.x, location.y - lastMouseLocation.y)
        guard moved >= 1 else { return }
        lastMouseLocation = location
        onActivity?()
    }

    private func stopMonitoring() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }
}

private struct PanelBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .withinWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
