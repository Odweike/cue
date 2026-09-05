import AppKit
import Combine
import SwiftUI

struct FloatingControlBar: View {
    let viewModel: PlayerViewModel
    private let refreshTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()
    @State private var showsSubtitles = false
    @State private var showsSettings = false

    var body: some View {
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
        .onReceive(refreshTimer) { _ in
            viewModel.refreshPlaybackState()
        }
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
                Image(systemName: viewModel.playbackState.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 29, weight: .medium))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.playbackState.isPlaying ? "Pause" : "Play")

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
                showsSettings.toggle()
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .help("Playback Settings")
            .popover(isPresented: $showsSettings, arrowEdge: .leading) {
                PlaybackSettingsPanel(viewModel: viewModel)
            }
        }
        .font(.system(size: 17, weight: .medium))
        .buttonStyle(.plain)
        .frame(maxWidth: 100, alignment: .trailing)
    }

    private var timeline: some View {
        HStack(spacing: 10) {
            Text(format(viewModel.playbackState.currentTime))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 62, alignment: .leading)

            Slider(
                value: Binding(
                    get: { viewModel.playbackState.currentTime },
                    set: { viewModel.seek(to: $0) }
                ),
                in: 0...max(viewModel.playbackState.duration, 0.01)
            )
            .tint(.white.opacity(0.9))
            .accessibilityLabel("Timeline")

            Text(format(viewModel.playbackState.duration))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 62, alignment: .trailing)
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

    private func format(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded(.down)), 0)
        let hours = total / 3_600
        let minutes = total % 3_600 / 60
        let remainingSeconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
            : String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

struct FloatingControlsOverlay: View {
    let viewModel: PlayerViewModel

    private static let minimumPanelWidth: CGFloat = 360
    private static let minimumPanelHeight: CGFloat = 84
    private static let regularPanelWidth: CGFloat = 500
    private static let regularPanelHeight: CGFloat = 116

    @AppStorage("FloatingControlsOffsetX") private var storedOffsetX = 0.0
    @AppStorage("FloatingControlsOffsetY") private var storedOffsetY = 0.0
    @AppStorage("CueControlsWidth") private var storedWidth = 620.0
    @AppStorage("CueControlsHeight") private var storedHeight = 132.0
    @GestureState private var moveOffset = CGSize.zero
    @GestureState private var resizeOffset = CGSize.zero

    var body: some View {
        GeometryReader { geometry in
            let panelSize = panelSize(in: geometry.size)
            let resizeDelta = CGSize(
                width: panelSize.width - storedWidth,
                height: panelSize.height - storedHeight
            )
            let resizeOffsetAdjustment = Self.offsetAdjustment(for: resizeDelta)
            let controlsScale = Self.controlsScale(for: panelSize)

            VStack {
                Spacer()

                FloatingControlBar(viewModel: viewModel)
                    .frame(
                        width: panelSize.width / controlsScale,
                        height: panelSize.height / controlsScale
                    )
                    .scaleEffect(controlsScale)
                    .frame(width: panelSize.width, height: panelSize.height)
                    .background {
                        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
                        shape
                            .fill(.regularMaterial)
                            .overlay {
                                shape.fill(.black.opacity(0.22))
                            }
                    }
                    .overlay(alignment: .top) {
                        moveHandle(in: geometry.size)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        resizeHandle(in: geometry.size)
                    }
                    .offset(
                        x: storedOffsetX + moveOffset.width + resizeOffsetAdjustment.width,
                        y: storedOffsetY + moveOffset.height + resizeOffsetAdjustment.height
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                keepPanelVisible(in: geometry.size)
            }
            .onChange(of: geometry.size) { _, newSize in
                keepPanelVisible(in: newSize)
            }
        }
    }

    private func moveHandle(in availableSize: CGSize) -> some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 20)
            .contentShape(Rectangle())
            .gesture(moveGesture(in: availableSize))
            .accessibilityLabel("Move controls")
            .help("Drag to move")
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

    private func panelSize(in availableSize: CGSize) -> CGSize {
        resizedPanelSize(for: resizeOffset, in: availableSize)
    }

    private func resizedPanelSize(for translation: CGSize, in availableSize: CGSize) -> CGSize {
        let currentLeft = (availableSize.width - storedWidth) / 2 + storedOffsetX
        let currentTop = availableSize.height - 24 - storedHeight + storedOffsetY
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

        let maxHorizontalOffset = max((availableSize.width - storedWidth) / 2 - 16, 0)
        let maximumUpwardOffset = max(availableSize.height - storedHeight - 48, 0)

        storedOffsetX = min(max(storedOffsetX, -maxHorizontalOffset), maxHorizontalOffset)
        storedOffsetY = min(max(storedOffsetY, -maximumUpwardOffset), 8)
    }
}
