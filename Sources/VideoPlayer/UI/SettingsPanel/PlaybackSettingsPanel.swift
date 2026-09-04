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

            switch selectedTab {
            case .video:
                videoSettings
            case .audio:
                audioSettings
            case .subtitles:
                SubtitleStyleEditor(viewModel: viewModel)
            }
        }
        .padding(16)
        .frame(width: 380, height: 330)
    }

    private var videoSettings: some View {
        Form {
            Section("Picture") {
                Picker("Scaling", selection: scalingMode) {
                    Text("Fit").tag(VideoScalingMode.fit)
                    Text("Fill").tag(VideoScalingMode.fill)
                }
                .pickerStyle(.segmented)
            }

            Section("Playback speed") {
                HStack {
                    Slider(value: playbackRate, in: 0.25...2, step: 0.25)
                    Text(String(format: "%.2f×", viewModel.playbackState.playbackRate))
                        .monospacedDigit()
                        .fixedSize()
                        .frame(width: 58, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var audioSettings: some View {
        Form {
            Section("Audio") {
                Toggle("Mute", isOn: muted)

                HStack {
                    Slider(value: volume, in: 0...1)
                    Text("\(Int(viewModel.playbackState.volume * 100))%")
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
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
