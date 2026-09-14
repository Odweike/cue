import Foundation

struct AudioTrack: Identifiable, Equatable, Sendable {
    let id: Int64
    let title: String?
    let language: String?
    let codec: String?
    let channelCount: Int
    let isSelected: Bool

    var displayName: String {
        displayName(locale: .current)
    }

    func displayName(locale: Locale) -> String {
        var parts: [String] = []
        if let language, !language.isEmpty {
            parts.append(LanguageName.displayName(for: language, locale: locale))
        }
        if let title, !title.isEmpty, !Self.isGenericTitle(title, language: language, codec: codec, locale: locale) {
            parts.append(title)
        }
        if channelCount > 0 {
            parts.append("\(channelCount) ch")
        }
        return parts.isEmpty ? "Audio Track \(id)" : parts.joined(separator: " • ")
    }

    private static let genericTitles: Set<String> = [
        "mov", "mp4", "m4a", "mkv", "und", "audio", "track", "unknown"
    ]

    private static func isGenericTitle(
        _ title: String,
        language: String?,
        codec: String?,
        locale: Locale
    ) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if genericTitles.contains(lower) { return true }
        if let codec, lower == codec.lowercased() { return true }
        if let language {
            if lower == language.lowercased() { return true }
            if lower == LanguageName.displayName(for: language, locale: locale).lowercased() {
                return true
            }
        }
        return false
    }
}
