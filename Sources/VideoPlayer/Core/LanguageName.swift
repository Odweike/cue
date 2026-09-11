import Foundation

enum LanguageName {
    /// Full localized name for a language code ("rus"/"ru" → "Russian").
    /// Falls back to the uppercased code when the language is unknown.
    static func displayName(for code: String, locale: Locale = .current) -> String {
        let normalized = code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        guard !normalized.isEmpty else { return code }

        let primary = normalized.split(separator: "-").first.map(String.init) ?? normalized
        let canonical = Locale(identifier: primary).language.languageCode?.identifier ?? primary
        for candidate in [normalized, primary, canonical] where !candidate.isEmpty {
            if let name = locale.localizedString(forLanguageCode: candidate),
               name.lowercased() != candidate {
                return name.prefix(1).uppercased() + name.dropFirst()
            }
        }
        return code.uppercased()
    }
}
