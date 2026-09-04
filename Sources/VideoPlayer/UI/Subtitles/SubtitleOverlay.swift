import SwiftUI

struct SubtitleOverlay: View {
    let cues: [SubtitleCue]
    let styleForTrack: (UUID) -> SubtitleStyle

    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach(cues) { cue in
                let style = styleForTrack(cue.trackID)

                Text(cue.text)
                    .font(.system(size: style.fontSize, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(style.textColor.color)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        .black.opacity(style.backgroundOpacity),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .padding(.bottom, style.bottomPadding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 72)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}
