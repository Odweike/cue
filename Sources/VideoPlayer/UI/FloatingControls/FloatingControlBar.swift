import Combine
import SwiftUI

struct FloatingControlBar: View {
    let viewModel: PlayerViewModel
    private let refreshTimer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 16) {
                volumeControl
                Spacer(minLength: 12)
                playbackButtons
                Spacer(minLength: 12)
                Text(viewModel.currentURL?.lastPathComponent ?? "")
                    .font(.caption)
                    .lineLimit(1)
                    .frame(maxWidth: 150, alignment: .trailing)
            }

            timeline
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: 620)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .onReceive(refreshTimer) { _ in
            viewModel.refreshPlaybackState()
        }
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
    @GestureState private var dragOffset = CGSize.zero

    var body: some View {
        GeometryReader { geometry in
            VStack {
                Spacer()

                FloatingControlBar(viewModel: viewModel)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    .offset(
                        x: storedOffsetX + dragOffset.width,
                        y: storedOffsetY + dragOffset.height
                    )
                    .gesture(dragGesture(in: geometry.size))
            }
            .onAppear {
                keepPanelVisible(in: geometry.size)
            }
            .onChange(of: geometry.size) { _, newSize in
                keepPanelVisible(in: newSize)
            }
        }
    }

    private func dragGesture(in availableSize: CGSize) -> some Gesture {
        DragGesture()
            .updating($dragOffset) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                storedOffsetX += value.translation.width
                storedOffsetY += value.translation.height
                keepPanelVisible(in: availableSize)
            }
    }

    private func keepPanelVisible(in availableSize: CGSize) {
        let panelWidth = min(620, max(availableSize.width - 32, 0))
        let maxHorizontalOffset = max((availableSize.width - panelWidth) / 2 - 16, 0)
        let maximumUpwardOffset = max(availableSize.height - 150, 0)

        storedOffsetX = min(max(storedOffsetX, -maxHorizontalOffset), maxHorizontalOffset)
        storedOffsetY = min(max(storedOffsetY, -maximumUpwardOffset), 0)
    }
}
