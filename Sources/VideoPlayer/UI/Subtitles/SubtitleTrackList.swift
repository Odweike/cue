import SwiftUI

struct SubtitleTrackList: View {
    let viewModel: PlayerViewModel
    var maxVisibleRows: Int?

    @State private var errorMessage: String?

    private static let rowHeight: CGFloat = 22
    private static let rowSpacing: CGFloat = 10

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
                Button {
                    viewModel.setSubtitleTrack(track.id, enabled: !track.isEnabled)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: track.isEnabled ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(track.isEnabled ? Color.accentColor : .secondary)
                            .frame(width: 16)
                        Text(track.name)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(height: Self.rowHeight)
            }
        }
    }

    private static func visibleHeight(rows: Int) -> CGFloat {
        CGFloat(rows) * rowHeight + CGFloat(max(rows - 1, 0)) * rowSpacing
    }
}
