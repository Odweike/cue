import SwiftUI

struct SubtitleOverlay: View {
    let cues: [SubtitleCue]

    var body: some View {
        VStack(spacing: 8) {
            Spacer()

            ForEach(cues) { cue in
                Text(cue.text)
                    .font(.system(size: 28, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 72)
        .padding(.bottom, 180)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}
