import Foundation

struct AudioTrack: Identifiable, Equatable, Sendable {
    let id: Int64
    let title: String?
    let language: String?
    let codec: String?
    let channelCount: Int
    let isSelected: Bool

    var displayName: String {
        var details = [title, language?.uppercased(), codec?.uppercased()]
            .compactMap { $0 }
        if channelCount > 0 {
            details.append("\(channelCount) ch")
        }
        return details.isEmpty ? "Audio Track \(id)" : details.joined(separator: " • ")
    }
}
