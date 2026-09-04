import Combine
import SwiftUI

struct FloatingControlBar: View {
    let viewModel: PlayerViewModel
    private let refreshTimer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    volumeControl
                    Spacer(minLength: 12)
                    playbackButtons
                    Spacer(minLength: 12)
                    fileName
                }

                HStack(spacing: 12) {
                    compactVolumeControl
                    Spacer(minLength: 4)
                    playbackButtons
                }
            }

            timeline
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .onReceive(refreshTimer) { _ in
            viewModel.refreshPlaybackState()
        }
    }

    private var fileName: some View {
        Text(viewModel.currentURL?.lastPathComponent ?? "")
            .font(.caption)
            .lineLimit(1)
            .frame(maxWidth: 150, alignment: .trailing)
    }

    private var volumeControl: some View {
        HStack(spacing: 8) {
            Image(systemName: volumeSymbol)
                .frame(width: 18)
            Slider(
                value: Binding(
                    get: { Double(viewModel.playbackState.volume) },
                    set: { viewModel.setVolume(Float($0)) }
                ),
                in: 0...1
            )
            .frame(width: 90)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Volume")
    }

    private var compactVolumeControl: some View {
        HStack(spacing: 6) {
            Image(systemName: volumeSymbol)
            Slider(
                value: Binding(
                    get: { Double(viewModel.playbackState.volume) },
                    set: { viewModel.setVolume(Float($0)) }
                ),
                in: 0...1
            )
            .frame(width: 64)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Volume")
    }

    private var playbackButtons: some View {
        HStack(spacing: 18) {
            controlButton("gobackward.10", label: "Back 10 seconds") {
                viewModel.skip(by: -10)
            }

            Button {
                viewModel.togglePlayback()
            } label: {
                Image(systemName: viewModel.playbackState.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.playbackState.isPlaying ? "Pause" : "Play")

            controlButton("goforward.10", label: "Forward 10 seconds") {
                viewModel.skip(by: 10)
            }
        }
    }

    private var timeline: some View {
        HStack(spacing: 10) {
            Text(format(viewModel.playbackState.currentTime))
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { viewModel.playbackState.currentTime },
                    set: { viewModel.seek(to: $0) }
                ),
                in: 0...max(viewModel.playbackState.duration, 0.01)
            )
            .accessibilityLabel("Timeline")

            Text(format(viewModel.playbackState.duration))
                .monospacedDigit()
                .frame(width: 48, alignment: .leading)
        }
        .font(.caption)
    }

    private var volumeSymbol: String {
        switch viewModel.playbackState.volume {
        case 0: "speaker.slash.fill"
        case ..<0.5: "speaker.wave.1.fill"
        default: "speaker.wave.2.fill"
        }
    }

    private func controlButton(
        _ systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3)
                .frame(width: 28, height: 28)
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

    @AppStorage("FloatingControlsOffsetX") private var storedOffsetX = 0.0
    @AppStorage("FloatingControlsOffsetY") private var storedOffsetY = 0.0
    @AppStorage("FloatingControlsWidth") private var storedWidth = 520.0
    @AppStorage("FloatingControlsHeight") private var storedHeight = 96.0
    @GestureState private var moveOffset = CGSize.zero
    @GestureState private var resizeOffset = CGSize.zero

    var body: some View {
        GeometryReader { geometry in
            let panelSize = panelSize(in: geometry.size)

            VStack {
                Spacer()

                FloatingControlBar(viewModel: viewModel)
                    .frame(width: panelSize.width, height: panelSize.height)
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white.opacity(0.14), lineWidth: 1)
                    }
                    .overlay(alignment: .top) {
                        moveHandle(in: geometry.size)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        resizeHandle(in: geometry.size)
                    }
                    .offset(
                        x: storedOffsetX + moveOffset.width,
                        y: storedOffsetY + moveOffset.height
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
            .onAppear {
                keepPanelVisible(in: geometry.size)
            }
            .onChange(of: geometry.size) { _, newSize in
                keepPanelVisible(in: newSize)
            }
        }
    }

    private func moveHandle(in availableSize: CGSize) -> some View {
        Capsule()
            .fill(.white.opacity(0.35))
            .frame(width: 38, height: 4)
            .padding(.top, 7)
            .frame(width: 90, height: 22)
            .contentShape(Rectangle())
            .gesture(moveGesture(in: availableSize))
            .accessibilityLabel("Move controls")
    }

    private func resizeHandle(in availableSize: CGSize) -> some View {
        Image(systemName: "arrow.down.right.and.arrow.up.left")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.65))
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .gesture(resizeGesture(in: availableSize))
            .accessibilityLabel("Resize controls")
            .help("Drag to resize")
    }

    private func moveGesture(in availableSize: CGSize) -> some Gesture {
        DragGesture()
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
        DragGesture()
            .updating($resizeOffset) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                storedWidth += value.translation.width
                storedHeight += value.translation.height
                keepPanelVisible(in: availableSize)
            }
    }

    private func panelSize(in availableSize: CGSize) -> CGSize {
        CGSize(
            width: min(max(storedWidth + resizeOffset.width, 380), max(availableSize.width - 32, 380)),
            height: min(max(storedHeight + resizeOffset.height, 88), 150)
        )
    }

    private func keepPanelVisible(in availableSize: CGSize) {
        storedWidth = min(max(storedWidth, 380), max(availableSize.width - 32, 380))
        storedHeight = min(max(storedHeight, 88), 150)

        let maxHorizontalOffset = max((availableSize.width - storedWidth) / 2 - 16, 0)
        let maximumUpwardOffset = max(availableSize.height - storedHeight - 48, 0)

        storedOffsetX = min(max(storedOffsetX, -maxHorizontalOffset), maxHorizontalOffset)
        storedOffsetY = min(max(storedOffsetY, -maximumUpwardOffset), 0)
    }
}
