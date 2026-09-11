import SwiftUI

struct SubtitleTracksPanel: View {
    let viewModel: PlayerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subtitles")
                .font(.headline)

            SubtitleTrackList(viewModel: viewModel, maxVisibleRows: 3)
        }
        .padding(16)
        .frame(width: 300)
    }
}
