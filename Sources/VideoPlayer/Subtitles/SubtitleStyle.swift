import SwiftUI

enum SubtitleColor: String, CaseIterable, Codable, Identifiable, Sendable {
    case white
    case yellow
    case cyan
    case green
    case black
    case red
    case blue

    var id: Self { self }
    var title: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .white: .white
        case .yellow: .yellow
        case .cyan: .cyan
        case .green: .green
        case .black: .black
        case .red: .red
        case .blue: .blue
        }
    }
}

enum SubtitleFontDesign: String, CaseIterable, Codable, Identifiable, Sendable {
    case standard
    case rounded
    case serif
    case monospaced

    var id: Self { self }
    var title: String { rawValue.capitalized }

    var fontDesign: Font.Design {
        switch self {
        case .standard: .default
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        }
    }
}

enum SubtitleFontWeight: String, CaseIterable, Codable, Identifiable, Sendable {
    case regular
    case medium
    case semibold
    case bold

    var id: Self { self }
    var title: String { rawValue.capitalized }

    var fontWeight: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}

enum SubtitlePosition: String, CaseIterable, Codable, Identifiable, Sendable {
    case top
    case bottom
    case custom

    var id: Self { self }
    var title: String { rawValue.capitalized }
}

enum SubtitleAlignment: String, CaseIterable, Codable, Identifiable, Sendable {
    case leading
    case center
    case trailing

    var id: Self { self }
    var title: String { rawValue.capitalized }

    var textAlignment: TextAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    var bottomAlignment: Alignment {
        switch self {
        case .leading: .bottomLeading
        case .center: .bottom
        case .trailing: .bottomTrailing
        }
    }
}

struct SubtitleStyle: Codable, Equatable, Sendable {
    var fontSize: Double
    var fontDesign: SubtitleFontDesign = .standard
    var fontWeight: SubtitleFontWeight = .semibold
    var textColor: SubtitleColor
    var outlineColor: SubtitleColor = .black
    var outlineWidth: Double = 1
    var backgroundColor: SubtitleColor = .black
    var backgroundOpacity: Double
    var position: SubtitlePosition = .custom
    var verticalOffset: Double
    var alignment: SubtitleAlignment = .center

    static let primary = SubtitleStyle(
        fontSize: 28,
        textColor: .white,
        backgroundOpacity: 0.72,
        position: .bottom,
        verticalOffset: 60
    )

    static let secondary = SubtitleStyle(
        fontSize: 24,
        textColor: .yellow,
        backgroundOpacity: 0.64,
        position: .bottom,
        verticalOffset: 112
    )

    static let tertiary = SubtitleStyle(
        fontSize: 22,
        textColor: .cyan,
        backgroundOpacity: 0.56,
        position: .bottom,
        verticalOffset: 164
    )

    static let defaults = [primary, secondary, tertiary]

    static func padded(_ styles: [SubtitleStyle]) -> [SubtitleStyle] {
        var result = styles.map { $0.normalized() }
        while result.count < defaults.count {
            result.append(defaults[result.count])
        }
        return Array(result.prefix(defaults.count))
    }

    func normalized() -> SubtitleStyle {
        var style = self
        style.fontSize = min(max(fontSize, 14), 52)
        style.outlineWidth = min(max(outlineWidth, 0), 4)
        style.backgroundOpacity = min(max(backgroundOpacity, 0), 0.9)
        style.verticalOffset = min(max(verticalOffset, 20), 360)
        return style
    }

    private enum CodingKeys: String, CodingKey {
        case fontSize
        case fontDesign
        case fontWeight
        case textColor
        case outlineColor
        case outlineWidth
        case backgroundColor
        case backgroundOpacity
        case position
        case verticalOffset
        case bottomPadding
        case alignment
    }

    init(
        fontSize: Double,
        fontDesign: SubtitleFontDesign = .standard,
        fontWeight: SubtitleFontWeight = .semibold,
        textColor: SubtitleColor,
        outlineColor: SubtitleColor = .black,
        outlineWidth: Double = 1,
        backgroundColor: SubtitleColor = .black,
        backgroundOpacity: Double,
        position: SubtitlePosition = .custom,
        verticalOffset: Double,
        alignment: SubtitleAlignment = .center
    ) {
        self.fontSize = fontSize
        self.fontDesign = fontDesign
        self.fontWeight = fontWeight
        self.textColor = textColor
        self.outlineColor = outlineColor
        self.outlineWidth = outlineWidth
        self.backgroundColor = backgroundColor
        self.backgroundOpacity = backgroundOpacity
        self.position = position
        self.verticalOffset = verticalOffset
        self.alignment = alignment
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fontSize = try values.decode(Double.self, forKey: .fontSize)
        fontDesign = try values.decodeIfPresent(SubtitleFontDesign.self, forKey: .fontDesign) ?? .standard
        fontWeight = try values.decodeIfPresent(SubtitleFontWeight.self, forKey: .fontWeight) ?? .semibold
        textColor = try values.decode(SubtitleColor.self, forKey: .textColor)
        outlineColor = try values.decodeIfPresent(SubtitleColor.self, forKey: .outlineColor) ?? .black
        outlineWidth = try values.decodeIfPresent(Double.self, forKey: .outlineWidth) ?? 1
        backgroundColor = try values.decodeIfPresent(SubtitleColor.self, forKey: .backgroundColor) ?? .black
        backgroundOpacity = try values.decode(Double.self, forKey: .backgroundOpacity)
        position = try values.decodeIfPresent(SubtitlePosition.self, forKey: .position) ?? .custom
        verticalOffset = try values.decodeIfPresent(Double.self, forKey: .verticalOffset)
            ?? values.decodeIfPresent(Double.self, forKey: .bottomPadding)
            ?? 180
        alignment = try values.decodeIfPresent(SubtitleAlignment.self, forKey: .alignment) ?? .center
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(fontSize, forKey: .fontSize)
        try values.encode(fontDesign, forKey: .fontDesign)
        try values.encode(fontWeight, forKey: .fontWeight)
        try values.encode(textColor, forKey: .textColor)
        try values.encode(outlineColor, forKey: .outlineColor)
        try values.encode(outlineWidth, forKey: .outlineWidth)
        try values.encode(backgroundColor, forKey: .backgroundColor)
        try values.encode(backgroundOpacity, forKey: .backgroundOpacity)
        try values.encode(position, forKey: .position)
        try values.encode(verticalOffset, forKey: .verticalOffset)
        try values.encode(alignment, forKey: .alignment)
    }
}

struct SubtitleStyleProfile: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var styles: [SubtitleStyle]
}
