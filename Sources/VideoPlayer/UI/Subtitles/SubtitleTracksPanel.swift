import SwiftUI

struct SubtitleTracksPanel: View {
    let viewModel: PlayerViewModel
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subtitles")
                .font(.headline)

            if viewModel.subtitleTracks.isEmpty {
                Text("No subtitle files added")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.subtitleTracks) { track in
                    HStack {
                        Toggle(track.name, isOn: Binding(
                            get: { track.isEnabled },
                            set: { viewModel.setSubtitleTrack(track.id, enabled: $0) }
                        ))
                        .lineLimit(1)

                        Spacer(minLength: 8)

                        Button {
                            do {
                                _ = try SubtitleFilePicker.exportSRT(track)
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .buttonStyle(.plain)
                        .help("Export as SRT")
                        .accessibilityLabel("Export \(track.name) as SRT")
                    }
                }
            }

            Divider()

            Button("Add Subtitle File…", systemImage: "plus") {
                guard let url = SubtitleFilePicker.chooseSubtitle() else { return }
                do {
                    try viewModel.importSubtitles(url)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .padding(16)
        .frame(width: 300)
        .alert("Subtitle File Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }
}
