import SwiftUI

struct SubtitleTrackList: View {
    let viewModel: PlayerViewModel
    var maxVisibleRows: Int?

    @State private var errorMessage: String?

    private static let rowHeight: CGFloat = 22
    private static let rowSpacing: CGFloat = 12

    init(viewModel: PlayerViewModel, maxVisibleRows: Int? = nil) {
        self.viewModel = viewModel
        self.maxVisibleRows = maxVisibleRows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            if viewModel.subtitleTracks.isEmpty {
                Text("No subtitle tracks available")
                    .foregroundStyle(.secondary)
            } else if let maxVisibleRows, viewModel.subtitleTracks.count > maxVisibleRows {
                ScrollView {
                    rows
                }
                .frame(height: Self.visibleHeight(rows: maxVisibleRows))
            } else {
                rows
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
        .alert("Subtitle File Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
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
                .frame(height: Self.rowHeight)
            }
        }
    }

    private static func visibleHeight(rows: Int) -> CGFloat {
        CGFloat(rows) * rowHeight + CGFloat(rows - 1) * rowSpacing
    }
}
