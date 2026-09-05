import SwiftUI

struct SubtitleStyleEditor: View {
    let viewModel: PlayerViewModel
    @State private var selectedTrack = 0

    var body: some View {
        Form {
            Section("Generate Subtitles") {
                if viewModel.supportedTranscriptionLocales.isEmpty {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking available languages…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Picker("Language", selection: transcriptionLocale) {
                        ForEach(viewModel.supportedTranscriptionLocales, id: \.identifier) { locale in
                            Text(viewModel.localeName(locale))
                                .tag(locale.identifier)
                        }
                    }
                }

                HStack {
                    if viewModel.transcriptionStatus.isRunning {
                        ProgressView()
                            .controlSize(.small)
                        Text("Recognizing speech on this Mac…")
                        Spacer()
                        Button("Cancel") {
                            viewModel.cancelTranscription()
                        }
                    } else {
                        Button("Generate from Audio", systemImage: "waveform.badge.mic") {
                            viewModel.startTranscription()
                        }
                        .disabled(
                            viewModel.currentURL == nil
                                || viewModel.supportedTranscriptionLocales.isEmpty
                        )
                    }
                }

                transcriptionResult
            }

            Picker("Track style", selection: $selectedTrack) {
                Text("First").tag(0)
                Text("Second").tag(1)
            }
            .pickerStyle(.segmented)

            Section("Text") {
                LabeledContent("Size") {
                    HStack {
                        Slider(value: fontSize, in: 14...52, step: 1)
                        Text("\(Int(style.wrappedValue.fontSize)) pt")
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                }

                Picker("Color", selection: textColor) {
                    ForEach(SubtitleTextColor.allCases) { option in
                        HStack {
                            Circle()
                                .fill(option.color)
                                .frame(width: 10, height: 10)
                            Text(option.title)
                        }
                        .tag(option)
                    }
                }
            }

            Section("Placement") {
                LabeledContent("Background") {
                    Slider(value: backgroundOpacity, in: 0...0.9, step: 0.05)
                }

                LabeledContent("Height") {
                    Slider(value: bottomPadding, in: 60...360, step: 5)
                }
            }

            Button("Reset This Track") {
                viewModel.resetSubtitleStyle(at: selectedTrack)
            }
        }
        .formStyle(.grouped)
        .task {
            await viewModel.loadSupportedTranscriptionLocales()
        }
    }

    @ViewBuilder
    private var transcriptionResult: some View {
        switch viewModel.transcriptionStatus {
        case .completed(let url):
            Label("Saved as \(url.lastPathComponent)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        case .idle, .running:
            EmptyView()
        }
    }

    private var transcriptionLocale: Binding<String> {
        Binding(
            get: { viewModel.selectedTranscriptionLocaleIdentifier },
            set: { viewModel.selectTranscriptionLocale($0) }
        )
    }

    private var style: Binding<SubtitleStyle> {
        Binding(
            get: { viewModel.subtitleStyles[selectedTrack] },
            set: { viewModel.setSubtitleStyle($0, at: selectedTrack) }
        )
    }

    private var fontSize: Binding<Double> {
        Binding(
            get: { style.wrappedValue.fontSize },
            set: { style.wrappedValue.fontSize = $0 }
        )
    }

    private var textColor: Binding<SubtitleTextColor> {
        Binding(
            get: { style.wrappedValue.textColor },
            set: { style.wrappedValue.textColor = $0 }
        )
    }

    private var backgroundOpacity: Binding<Double> {
        Binding(
            get: { style.wrappedValue.backgroundOpacity },
            set: { style.wrappedValue.backgroundOpacity = $0 }
        )
    }

    private var bottomPadding: Binding<Double> {
        Binding(
            get: { style.wrappedValue.bottomPadding },
            set: { style.wrappedValue.bottomPadding = $0 }
        )
    }
}
