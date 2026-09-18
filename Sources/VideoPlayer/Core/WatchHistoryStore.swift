import Foundation

struct WatchHistoryItem: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var bookmark: Data
    var fileName: String
    var position: TimeInterval
    var duration: TimeInterval
    var updatedAt: Date
    var settings: VideoPlaybackSettings?
}

struct VideoPlaybackSettings: Codable, Equatable, Sendable {
    var audioTrackID: Int64?
    var audioLanguage: String?
    var volume: Float?
    var isMuted: Bool?
    var playbackRate: Float?
    var audioDelay: TimeInterval?
    var subtitleDelay: TimeInterval?
    var videoScalingMode: VideoScalingMode?
    var aspectRatio: VideoRatio?
    var cropRatio: VideoRatio?
    var rotation: VideoRotation?
    var hardwareDecoding: Bool?
    var deinterlacing: Bool?
    var videoEqualizer: VideoEqualizer?

    func matchingAudioTrack(in tracks: [AudioTrack]) -> AudioTrack? {
        if let audioTrackID, let track = tracks.first(where: { $0.id == audioTrackID }) {
            return track
        }
        if let audioLanguage {
            let language = audioLanguage.lowercased()
            return tracks.first { $0.language?.lowercased() == language }
        }
        return nil
    }
}

@MainActor
final class WatchHistoryStore {
    static let live = WatchHistoryStore(fileURL: defaultFileURL())
    static func ephemeral() -> WatchHistoryStore {
        WatchHistoryStore(fileURL: nil)
    }

    private let fileURL: URL?
    private let limit = 20
    private var items: [WatchHistoryItem]

    init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL {
            Self.prepareDirectory(fileURL)
            items = Self.load(from: fileURL)
        } else {
            items = []
        }
    }

    func unfinished() -> [WatchHistoryItem] {
        items.filter { !$0.isFinished }
    }

    func item(for url: URL) -> WatchHistoryItem? {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return items.first { $0.id == path }
    }

    func upsert(
        url: URL,
        position: TimeInterval,
        duration: TimeInterval,
        settings: VideoPlaybackSettings? = nil
    ) {
        let fileURL = url.resolvingSymlinksInPath().standardizedFileURL
        let previous = items.first { $0.id == fileURL.path }
        let item = WatchHistoryItem(
            id: fileURL.path,
            bookmark: (try? fileURL.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )) ?? previous?.bookmark ?? Data(),
            fileName: fileURL.lastPathComponent,
            position: max(position, 0),
            duration: max(duration, 0),
            updatedAt: Date(),
            settings: settings ?? previous?.settings
        )
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
        if items.count > limit {
            items = Array(items.prefix(limit))
        }
        save()
    }

    func resolve(_ item: WatchHistoryItem) -> URL? {
        if !item.bookmark.isEmpty {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: item.bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if FileManager.default.fileExists(atPath: url.path) {
                    return url.resolvingSymlinksInPath().standardizedFileURL
                }
            }
        }
        let url = URL(fileURLWithPath: item.id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func remove(_ id: String) {
        items.removeAll { $0.id == id }
        save()
    }

    private func save() {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    private static func load(from fileURL: URL) -> [WatchHistoryItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([WatchHistoryItem].self, from: data)) ?? []
    }

    private static func defaultFileURL() -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cue", isDirectory: true)
        return directory.appendingPathComponent("watch-history.json")
    }

    private static func prepareDirectory(_ fileURL: URL) {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directoryURL = directory
        try? directoryURL.setResourceValues(values)
    }
}

extension WatchHistoryItem {
    var isFinished: Bool {
        duration > 0 && (duration - position <= 5 || position / duration >= 0.97)
    }
}
