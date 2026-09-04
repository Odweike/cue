import Foundation

struct SubtitleTrack: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let cues: [SubtitleCue]
    var isEnabled: Bool
}
