import SwiftUI

struct LanguageAssetSheet: View {
    let languageName: String
    let progress: Double
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Preparing \(languageName)", systemImage: "waveform.badge.mic")
                .font(.title3.weight(.semibold))

            Text("macOS is downloading the on-device language package. This only happens once.")
                .foregroundStyle(.secondary)

            ProgressView(value: min(max(progress, 0), 1))

            HStack {
                Text("\(Int(min(max(progress, 0), 1) * 100))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
            }
        }
        .padding(24)
        .frame(width: 390)
        .interactiveDismissDisabled()
    }
}
