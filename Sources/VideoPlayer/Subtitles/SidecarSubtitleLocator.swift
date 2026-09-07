import Foundation

enum SidecarSubtitleLocator {
    static let extensions = ["srt", "vtt", "ass", "ssa"]

    static func urls(beside videoURL: URL) -> [URL] {
        let folder = videoURL.deletingLastPathComponent()
        let stem = videoURL.deletingPathExtension().lastPathComponent.lowercased()
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return contents
            .filter { url in
                extensions.contains(url.pathExtension.lowercased())
                    && url.deletingPathExtension().lastPathComponent.lowercased().hasPrefix(stem)
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
