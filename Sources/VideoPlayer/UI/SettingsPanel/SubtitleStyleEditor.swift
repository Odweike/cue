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
                Picker("Font", selection: fontDesign) {
                    ForEach(SubtitleFontDesign.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }

                Picker("Weight", selection: fontWeight) {
                    ForEach(SubtitleFontWeight.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }

                LabeledContent("Size") {
                    HStack {
                        Slider(value: fontSize, in: 14...52, step: 1)
                        Text("\(Int(style.wrappedValue.fontSize)) pt")
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                }

                Picker("Color", selection: textColor) {
                    colorOptions()
                }
            }

            Section("Outline") {
                Picker("Color", selection: outlineColor) {
                    colorOptions()
                }

                LabeledContent("Width") {
                    HStack {
                        Slider(value: outlineWidth, in: 0...4, step: 0.5)
                        Text(String(format: "%.1f", style.wrappedValue.outlineWidth))
                            .monospacedDigit()
                            .frame(width: 28, alignment: .trailing)
                    }
                }
            }

            Section("Background") {
                Picker("Color", selection: backgroundColor) {
                    colorOptions()
                }

                LabeledContent("Opacity") {
                    Slider(value: backgroundOpacity, in: 0...0.9, step: 0.05)
                }
            }

            Section("Placement") {
                Picker("Position", selection: position) {
                    ForEach(SubtitlePosition.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Alignment", selection: alignment) {
                    ForEach(SubtitleAlignment.allCases) { option in
                        HStack {
                            Image(systemName: alignmentIcon(option))
                            Text(option.title)
                        }
                        .tag(option)
                    }
                }
                .pickerStyle(.segmented)

                if style.wrappedValue.position == .custom {
                    LabeledContent("Height") {
                        Slider(value: verticalOffset, in: 20...360, step: 5)
                    }
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

    private var fontDesign: Binding<SubtitleFontDesign> {
        Binding(
            get: { style.wrappedValue.fontDesign },
            set: { style.wrappedValue.fontDesign = $0 }
        )
    }

    private var fontWeight: Binding<SubtitleFontWeight> {
        Binding(
            get: { style.wrappedValue.fontWeight },
            set: { style.wrappedValue.fontWeight = $0 }
        )
    }

    private var textColor: Binding<SubtitleColor> {
        Binding(
            get: { style.wrappedValue.textColor },
            set: { style.wrappedValue.textColor = $0 }
        )
    }

    private var outlineColor: Binding<SubtitleColor> {
        Binding(
            get: { style.wrappedValue.outlineColor },
            set: { style.wrappedValue.outlineColor = $0 }
        )
    }

    private var outlineWidth: Binding<Double> {
        Binding(
            get: { style.wrappedValue.outlineWidth },
            set: { style.wrappedValue.outlineWidth = $0 }
        )
    }

    private var backgroundColor: Binding<SubtitleColor> {
        Binding(
            get: { style.wrappedValue.backgroundColor },
            set: { style.wrappedValue.backgroundColor = $0 }
        )
    }

    private var backgroundOpacity: Binding<Double> {
        Binding(
            get: { style.wrappedValue.backgroundOpacity },
            set: { style.wrappedValue.backgroundOpacity = $0 }
        )
    }

    private var position: Binding<SubtitlePosition> {
        Binding(
            get: { style.wrappedValue.position },
            set: { style.wrappedValue.position = $0 }
        )
    }

    private var verticalOffset: Binding<Double> {
        Binding(
            get: { style.wrappedValue.verticalOffset },
            set: { style.wrappedValue.verticalOffset = $0 }
        )
    }

    private var alignment: Binding<SubtitleAlignment> {
        Binding(
            get: { style.wrappedValue.alignment },
            set: { style.wrappedValue.alignment = $0 }
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
