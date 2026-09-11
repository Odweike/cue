import SwiftUI

struct SubtitleStyleEditor: View {
    let viewModel: PlayerViewModel
    @State private var selectedTrack = 0
    @State private var profileName = ""

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
                        Text(activityDescription(viewModel.transcriptionActivity))
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

                Toggle("Recognize While Watching", isOn: progressiveTranscription)
                    .disabled(
                        viewModel.currentURL == nil
                            || viewModel.supportedTranscriptionLocales.isEmpty
                    )

                if viewModel.isProgressiveTranscriptionEnabled,
                   let activity = viewModel.progressiveTranscriptionActivity {
                    Label(activityDescription(activity), systemImage: "waveform")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                if let message = viewModel.progressiveTranscriptionError {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                transcriptionResult
            }

            Picker("Track style", selection: $selectedTrack) {
                Text("First").tag(0)
                Text("Second").tag(1)
            }
            .pickerStyle(.segmented)

            Section("Style Profiles") {
                HStack {
                    TextField("Profile name", text: $profileName)
                    Button("Save") {
                        if viewModel.saveSubtitleStyleProfile(named: profileName) {
                            profileName = ""
                        }
                    }
                    .disabled(profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                ForEach(viewModel.subtitleStyleProfiles) { profile in
                    HStack {
                        Button(profile.name) {
                            viewModel.applySubtitleStyleProfile(profile.id)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button(role: .destructive) {
                            viewModel.deleteSubtitleStyleProfile(profile.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .help("Delete profile")
                        .accessibilityLabel("Delete \(profile.name)")
                    }
                }
            }

            Section("Text") {
                Picker("Font", selection: styleBinding(\.fontDesign)) {
                    ForEach(SubtitleFontDesign.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }

                Picker("Weight", selection: styleBinding(\.fontWeight)) {
                    ForEach(SubtitleFontWeight.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }

                LabeledContent("Size") {
                    HStack {
                        Slider(value: styleBinding(\.fontSize), in: 14...52)
                        Text("\(Int(style.fontSize)) pt")
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                }

                Picker("Color", selection: styleBinding(\.textColor)) {
                    colorOptions()
                }
            }

            Section("Outline") {
                Picker("Color", selection: styleBinding(\.outlineColor)) {
                    colorOptions()
                }

                LabeledContent("Width") {
                    HStack {
                        Slider(value: styleBinding(\.outlineWidth), in: 0...4)
                        Text(String(format: "%.1f", style.outlineWidth))
                            .monospacedDigit()
                            .frame(width: 28, alignment: .trailing)
                    }
                }
            }

            Section("Background") {
                Picker("Color", selection: styleBinding(\.backgroundColor)) {
                    colorOptions()
                }

                LabeledContent("Opacity") {
                    Slider(value: styleBinding(\.backgroundOpacity), in: 0...0.9)
                }
            }

            Section("Placement") {
                Picker("Position", selection: styleBinding(\.position)) {
                    ForEach(SubtitlePosition.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Alignment", selection: styleBinding(\.alignment)) {
                    ForEach(SubtitleAlignment.allCases) { option in
                        HStack {
                            Image(systemName: alignmentIcon(option))
                            Text(option.title)
                        }
                        .tag(option)
                    }
                }
                .pickerStyle(.segmented)

                if style.position == .custom {
                    LabeledContent("Height") {
                        Slider(value: styleBinding(\.verticalOffset), in: 20...360)
                    }
                }
            }

            Button("Reset This Track") {
                viewModel.resetSubtitleStyle(at: selectedTrack)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: languageAssetSheetPresented) {
            LanguageAssetSheet(
                languageName: viewModel.localeName(
                    Locale(identifier: viewModel.selectedTranscriptionLocaleIdentifier)
                ),
                progress: viewModel.languageAssetDownloadProgress ?? 0,
                cancel: viewModel.cancelLanguageAssetPreparation
            )
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

    private var progressiveTranscription: Binding<Bool> {
        Binding(
            get: { viewModel.isProgressiveTranscriptionEnabled },
            set: { viewModel.setProgressiveTranscriptionEnabled($0) }
        )
    }

    private var languageAssetSheetPresented: Binding<Bool> {
        Binding(
            get: { viewModel.languageAssetDownloadProgress != nil },
            set: { _ in }
        )
    }

    private func activityDescription(_ activity: TranscriptionActivity?) -> String {
        switch activity {
        case .extractingAudio:
            "Preparing audio…"
        case .preparingLanguage:
            "Preparing language package…"
        case .recognizing:
            "Recognizing speech on this Mac…"
        case nil:
            "Starting…"
        }
    }

    private var style: SubtitleStyle {
        viewModel.subtitleStyles[selectedTrack]
    }

    private func styleBinding<T>(_ keyPath: WritableKeyPath<SubtitleStyle, T>) -> Binding<T> {
        Binding(
            get: { viewModel.subtitleStyles[selectedTrack][keyPath: keyPath] },
            set: { value in
                var style = viewModel.subtitleStyles[selectedTrack]
                style[keyPath: keyPath] = value
                viewModel.setSubtitleStyle(style, at: selectedTrack)
            }
        )
    }

    @ViewBuilder
    private func colorOptions() -> some View {
        ForEach(SubtitleColor.allCases) { option in
            HStack {
                Circle()
                    .fill(option.color)
                    .frame(width: 10, height: 10)
                Text(option.title)
            }
            .tag(option)
        }
    }

    private func alignmentIcon(_ alignment: SubtitleAlignment) -> String {
        switch alignment {
        case .leading: "text.alignleft"
        case .center: "text.aligncenter"
        case .trailing: "text.alignright"
        }
    }
}
