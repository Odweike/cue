import SwiftUI

enum SubtitleTextColor: String, CaseIterable, Codable, Identifiable, Sendable {
    case white
    case yellow
    case cyan
    case green

    var id: Self { self }

    var title: String {
        rawValue.capitalized
    }

    var color: Color {
        switch self {
        case .white: .white
        case .yellow: .yellow
        case .cyan: .cyan
        case .green: .green
        }
    }
}

struct SubtitleStyle: Codable, Equatable, Sendable {
    var fontSize: Double
    var textColor: SubtitleTextColor
    var backgroundOpacity: Double
    var bottomPadding: Double

    static let primary = SubtitleStyle(
        fontSize: 28,
        textColor: .white,
        backgroundOpacity: 0.72,
        bottomPadding: 180
    )

    static let secondary = SubtitleStyle(
        fontSize: 24,
        textColor: .yellow,
        backgroundOpacity: 0.64,
        bottomPadding: 235
    )

    func normalized() -> SubtitleStyle {
        SubtitleStyle(
            fontSize: min(max(fontSize, 14), 52),
            textColor: textColor,
            backgroundOpacity: min(max(backgroundOpacity, 0), 0.9),
            bottomPadding: min(max(bottomPadding, 60), 360)
        )
    }
}
