import SwiftUI

struct PlaybackSettingsPanel: View {
    let viewModel: PlayerViewModel
    @State private var selectedTab = SettingsTab.video

    var body: some View {
        VStack(spacing: 12) {
            Picker("Settings", selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ZStack(alignment: .top) {
                videoSettings
                    .opacity(selectedTab == .video ? 1 : 0)
                    .allowsHitTesting(selectedTab == .video)

                audioSettings
                    .opacity(selectedTab == .audio ? 1 : 0)
                    .allowsHitTesting(selectedTab == .audio)

                SubtitleStyleEditor(viewModel: viewModel)
                    .opacity(selectedTab == .subtitles ? 1 : 0)
                    .allowsHitTesting(selectedTab == .subtitles)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transaction { $0.animation = nil }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            await viewModel.loadSupportedTranscriptionLocales()
        }
    }

    private var videoSettings: some View {
        Form {
            Section("Picture") {
                Picker("Scaling", selection: scalingMode) {
                    Text("Fit").tag(VideoScalingMode.fit)
                    Text("Fill").tag(VideoScalingMode.fill)
                }
                .pickerStyle(.segmented)

                Picker("Aspect Ratio", selection: aspectRatio) {
                    ratioOptions(automaticTitle: "Original")
                }

                Picker("Crop", selection: cropRatio) {
                    ratioOptions(automaticTitle: "None")
                }

                Picker("Rotation", selection: rotation) {
                    ForEach(VideoRotation.allCases) { rotation in
                        Text("\(rotation.rawValue)°").tag(rotation)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Playback") {
                HStack(alignment: .center) {
                    Text("Speed")
                    RulerSlider(value: playbackRate, range: 0.25...16, step: 0.25, majorEvery: 4)
                    Text(String(format: "%.2f×", viewModel.playbackState.playbackRate))
                        .monospacedDigit()
                        .fixedSize()
                        .frame(width: 58, alignment: .trailing)
                }

                Toggle("Hardware Decoding", isOn: hardwareDecoding)
                Toggle("Deinterlace", isOn: deinterlacing)
            }

            Section("Color") {
                AdjustmentRow("Brightness", value: equalizer(\.brightness))
                AdjustmentRow("Contrast", value: equalizer(\.contrast))
                AdjustmentRow("Saturation", value: equalizer(\.saturation))
                AdjustmentRow("Gamma", value: equalizer(\.gamma))
                AdjustmentRow("Hue", value: equalizer(\.hue))

                Button("Reset Color Adjustments") {
                    viewModel.setVideoEqualizer(VideoEqualizer())
                }
            }
        }
        .formStyle(.grouped)
    }

    private var audioSettings: some View {
        Form {
            Section("Track") {
                if viewModel.audioTracks.isEmpty {
                    Text("No audio tracks available")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Audio Track", selection: selectedAudioTrack) {
                        ForEach(viewModel.audioTracks) { track in
                            Text(track.displayName).tag(track.id)
                        }
                    }
                }
            }

            Section("Output") {
                Toggle("Mute", isOn: muted)

                HStack {
                    Text("Volume")
                    Slider(value: volume, in: 0...1)
                    Text("\(Int(viewModel.playbackState.volume * 100))%")
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
            }

            Section("Synchronization") {
                HStack(alignment: .center) {
                    Text("Audio Delay")
                    RulerSlider(value: audioDelay, range: -5...5, step: 0.1, majorEvery: 10)
                    Text(String(format: "%+.1f s", viewModel.playbackState.audioDelay))
                        .monospacedDigit()
                        .frame(width: 54, alignment: .trailing)
                }

                Button("Reset Audio Delay") {
                    viewModel.setAudioDelay(0)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var scalingMode: Binding<VideoScalingMode> {
        Binding(
            get: { viewModel.playbackState.videoScalingMode },
            set: { viewModel.setVideoScalingMode($0) }
        )
    }

    private var playbackRate: Binding<Double> {
        Binding(
            get: { Double(viewModel.playbackState.playbackRate) },
            set: { viewModel.setPlaybackRate(Float($0)) }
        )
    }

    private var aspectRatio: Binding<VideoRatio> {
        Binding(
            get: { viewModel.playbackState.aspectRatio },
            set: { viewModel.setAspectRatio($0) }
        )
    }

    private var cropRatio: Binding<VideoRatio> {
        Binding(
            get: { viewModel.playbackState.cropRatio },
            set: { viewModel.setCropRatio($0) }
        )
    }

    private var rotation: Binding<VideoRotation> {
        Binding(
            get: { viewModel.playbackState.rotation },
            set: { viewModel.setRotation($0) }
        )
    }

    private var hardwareDecoding: Binding<Bool> {
        Binding(
            get: { viewModel.playbackState.hardwareDecoding },
            set: { viewModel.setHardwareDecoding($0) }
        )
    }

    private var deinterlacing: Binding<Bool> {
        Binding(
            get: { viewModel.playbackState.deinterlacing },
            set: { viewModel.setDeinterlacing($0) }
        )
    }

    private func equalizer(_ keyPath: WritableKeyPath<VideoEqualizer, Double>) -> Binding<Double> {
        Binding(
            get: { viewModel.playbackState.videoEqualizer[keyPath: keyPath] },
            set: { value in
                var equalizer = viewModel.playbackState.videoEqualizer
                equalizer[keyPath: keyPath] = value
                viewModel.setVideoEqualizer(equalizer)
            }
        )
    }

    @ViewBuilder
    private func ratioOptions(automaticTitle: String) -> some View {
        Text(automaticTitle).tag(VideoRatio.automatic)
        ForEach(VideoRatio.allCases.filter { $0 != .automatic }) { ratio in
            Text(ratio.rawValue).tag(ratio)
        }
    }

    private var muted: Binding<Bool> {
        Binding(
            get: { viewModel.playbackState.isMuted },
            set: { viewModel.setMuted($0) }
        )
    }

    private var volume: Binding<Double> {
        Binding(
            get: { Double(viewModel.playbackState.volume) },
            set: { viewModel.setVolume(Float($0)) }
        )
    }

    private var selectedAudioTrack: Binding<Int64> {
        Binding(
            get: {
                viewModel.audioTracks.first(where: \.isSelected)?.id
                    ?? viewModel.audioTracks.first?.id
                    ?? 0
            },
            set: { viewModel.selectAudioTrack($0) }
        )
    }

    private var audioDelay: Binding<Double> {
        Binding(
            get: { viewModel.playbackState.audioDelay },
            set: { viewModel.setAudioDelay($0) }
        )
    }
}

private struct AdjustmentRow: View {
    let title: String
    @Binding var value: Double

    init(_ title: String, value: Binding<Double>) {
        self.title = title
        _value = value
    }

    var body: some View {
        HStack {
            Text(title)
                .frame(width: 76, alignment: .leading)
            Slider(value: $value, in: -100...100)
            Text("\(Int(value))")
                .monospacedDigit()
                .frame(width: 34, alignment: .trailing)
        }
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case video
    case audio
    case subtitles

    var id: Self { self }

    var title: String {
        switch self {
        case .video: "Video"
        case .audio: "Audio"
        case .subtitles: "Subtitles"
        }
    }

    var systemImage: String {
        switch self {
        case .video: "film"
        case .audio: "speaker.wave.2"
        case .subtitles: "captions.bubble"
        }
    }
}
