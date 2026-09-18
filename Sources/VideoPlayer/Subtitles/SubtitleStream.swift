import Foundation

struct SubtitleStream: Identifiable, Equatable, Sendable {
    let id: Int64
    let title: String?
    let language: String?
    let codec: String?
    let isForced: Bool
    let isDefault: Bool

    var displayName: String {
        var parts: [String] = []
        if let language, !language.isEmpty {
            parts.append(LanguageName.displayName(for: language))
        }
        if let title, !title.isEmpty {
            parts.append(title)
        }
        if isForced {
            parts.append("Forced")
        }
        if parts.isEmpty {
            parts.append("Subtitle \(id)")
        }
        return parts.joined(separator: " • ")
    }
}
