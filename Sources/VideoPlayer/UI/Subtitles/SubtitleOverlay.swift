import SwiftUI

struct SubtitleOverlay: View {
    let cues: [SubtitleCue]
    let styleForTrack: (UUID) -> SubtitleStyle

    var body: some View {
        ZStack {
            ForEach(cues) { cue in
                let style = styleForTrack(cue.trackID)

                subtitle(cue.text, style: style)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: frameAlignment(for: style)
                    )
                    .padding(positionEdge(for: style), positionPadding(for: style))
            }
        }
        .padding(.horizontal, 72)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    private func subtitle(_ text: String, style: SubtitleStyle) -> some View {
        Text(text)
            .font(.system(
                size: style.fontSize,
                weight: style.fontWeight.fontWeight,
                design: style.fontDesign.fontDesign
            ))
            .multilineTextAlignment(style.alignment.textAlignment)
            .foregroundStyle(style.textColor.color)
            .shadow(color: style.outlineColor.color, radius: 0, x: style.outlineWidth, y: 0)
            .shadow(color: style.outlineColor.color, radius: 0, x: -style.outlineWidth, y: 0)
            .shadow(color: style.outlineColor.color, radius: 0, x: 0, y: style.outlineWidth)
            .shadow(color: style.outlineColor.color, radius: 0, x: 0, y: -style.outlineWidth)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                style.backgroundColor.color.opacity(style.backgroundOpacity),
                in: RoundedRectangle(cornerRadius: 6)
            )
    }

    private func frameAlignment(for style: SubtitleStyle) -> Alignment {
        switch style.position {
        case .top:
            switch style.alignment {
            case .leading: .topLeading
            case .center: .top
            case .trailing: .topTrailing
            }
        case .bottom, .custom:
            style.alignment.bottomAlignment
        }
    }

    private func positionEdge(for style: SubtitleStyle) -> Edge.Set {
        style.position == .top ? .top : .bottom
    }

    private func positionPadding(for style: SubtitleStyle) -> Double {
        style.position == .custom ? style.verticalOffset : 60
    }
}
