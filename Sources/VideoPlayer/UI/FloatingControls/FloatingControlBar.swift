import AppKit
import SwiftUI

struct FloatingControlBar: View {
    let viewModel: PlayerViewModel
    @State private var showsSubtitles = false

    var body: some View {
        TimelineView(
            .animation(
                paused: CueMainControlsDrag.isActive
                    || (!viewModel.isPlaying && !viewModel.isScrubbing)
            )
        ) { _ in
            controlBar
        }
    }

    private var controlBar: some View {
        let _ = viewModel.refreshPlaybackState()
        return VStack(spacing: 8) {
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
        HStack(spacing: 15) {
            Button {
                NSApp.keyWindow?.toggleFullScreen(nil)
            } label: {
                Image(systemName: "pip.enter")
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
        .frame(maxWidth: 100, alignment: .trailing)
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

            Slider(
                value: Binding(
                    get: { displayedTime },
                    set: { viewModel.updateScrubbing(to: $0) }
                ),
                in: 0...max(viewModel.duration, 0.01),
                onEditingChanged: { isEditing in
                    if isEditing {
                        viewModel.beginScrubbing()
                    } else {
                        viewModel.endScrubbing()
                    }
                }
            )
            .tint(.white.opacity(0.9))
            .accessibilityLabel("Timeline")

            Text(PlaybackTimeFormat.string(from: viewModel.duration, includingHours: showsHours))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(minWidth: 82, alignment: .trailing)
                .fixedSize(horizontal: true, vertical: false)
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

    var body: some View {
        GeometryReader { geometry in
            let panelSize = panelSize(in: geometry.size)
            let resizeDelta = CGSize(
                width: panelSize.width - storedWidth,
                height: panelSize.height - storedHeight
            )
            let displayedOffset = CGSize(
                width: storedOffsetX + Self.offsetAdjustment(for: resizeDelta).width,
                height: storedOffsetY + Self.offsetAdjustment(for: resizeDelta).height
            )

            FloatingPanelCanvas(
                panelSize: panelSize,
                offset: displayedOffset,
                onMoveEnded: { newOffset in
                    storedOffsetX = newOffset.width
                    storedOffsetY = newOffset.height
                    keepPanelVisible(in: geometry.size)
                }
            ) {
                panelChrome(panelSize: panelSize, in: geometry.size)
            }
            .onAppear {
                keepPanelVisible(in: geometry.size)
            }
            .onChange(of: geometry.size) { _, newSize in
                keepPanelVisible(in: newSize)
            }
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
            .background(.clear)
            .overlay(alignment: .bottomTrailing) {
                resizeHandle(in: availableSize)
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

private struct FloatingPanelCanvas<Content: View>: NSViewRepresentable {
    var panelSize: CGSize
    var offset: CGSize
    var onMoveEnded: (CGSize) -> Void
    @ViewBuilder var content: Content

    func makeNSView(context: Context) -> FloatingPanelCanvasView {
        let view = FloatingPanelCanvasView()
        view.hostingView.rootView = AnyView(content)
        view.onMoveEnded = onMoveEnded
        return view
    }

    func updateNSView(_ view: FloatingPanelCanvasView, context: Context) {
        view.onMoveEnded = onMoveEnded
        view.panelSize = panelSize
        view.storedOffset = offset
        if !view.isMoving {
            view.hostingView.rootView = AnyView(content)
            view.needsLayout = true
        }
    }
}

enum CueMainControlsDrag {
    nonisolated(unsafe) static var isActive = false
}

private final class FloatingPanelCanvasView: NSView {
    let panelView = NSView()
    let effectView = NSVisualEffectView()
    let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private let moveHandle = MoveHandleView()
    var panelSize: CGSize = .zero
    var storedOffset: CGSize = .zero
    var onMoveEnded: ((CGSize) -> Void)?
    private(set) var isMoving = false
    private var moveStartMouse = CGPoint.zero
    private var moveStartOrigin = CGPoint.zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        panelView.wantsLayer = true
        panelView.layer?.cornerRadius = 18
        panelView.layer?.cornerCurve = .continuous
        panelView.layer?.masksToBounds = true

        effectView.material = .hudWindow
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.appearance = NSAppearance(named: .darkAqua)
        effectView.autoresizingMask = [.width, .height]

        hostingView.autoresizingMask = [.width, .height]
        hostingView.safeAreaRegions = []

        addSubview(panelView)
        panelView.addSubview(effectView)
        panelView.addSubview(hostingView)
        moveHandle.canvas = self
        moveHandle.setAccessibilityLabel("Move controls")
        moveHandle.toolTip = "Drag to move"
        moveHandle.autoresizingMask = [.width]
        panelView.addSubview(moveHandle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    override func layout() {
        super.layout()
        guard !isMoving else { return }
        panelView.frame = CGRect(
            origin: FloatingControlsOverlay.origin(
                for: storedOffset,
                panelSize: panelSize,
                availableSize: bounds.size
            ),
            size: panelSize
        )
        effectView.frame = panelView.bounds
        hostingView.frame = panelView.bounds
        moveHandle.frame = CGRect(x: 0, y: 0, width: panelSize.width, height: 20)
    }

    func beginMove(with event: NSEvent) {
        CueMainControlsDrag.isActive = true
        isMoving = true
        moveStartMouse = convert(event.locationInWindow, from: nil)
        moveStartOrigin = panelView.frame.origin
    }

    func continueMove(with event: NSEvent) {
        let mouse = convert(event.locationInWindow, from: nil)
        let proposed = CGPoint(
            x: moveStartOrigin.x + mouse.x - moveStartMouse.x,
            y: moveStartOrigin.y + mouse.y - moveStartMouse.y
        )
        let size = panelView.frame.size
        let offset = FloatingControlsOverlay.clampedOffset(
            FloatingControlsOverlay.offset(
                from: proposed,
                panelSize: size,
                availableSize: bounds.size
            ),
            panelSize: size,
            availableSize: bounds.size
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panelView.setFrameOrigin(
            FloatingControlsOverlay.origin(
                for: offset,
                panelSize: size,
                availableSize: bounds.size
            )
        )
        CATransaction.commit()
    }

    func endMove() {
        isMoving = false
        CueMainControlsDrag.isActive = false
        onMoveEnded?(
            FloatingControlsOverlay.offset(
                from: panelView.frame.origin,
                panelSize: panelView.frame.size,
                availableSize: bounds.size
            )
        )
    }
}

private final class MoveHandleView: NSView {
    weak var canvas: FloatingPanelCanvasView?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        NSCursor.closedHand.push()
        canvas?.beginMove(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        canvas?.continueMove(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        canvas?.endMove()
        NSCursor.pop()
    }
}
