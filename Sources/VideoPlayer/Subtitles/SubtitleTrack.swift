import Foundation

struct SubtitleTrack: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    var cues: [SubtitleCue]
    var isEnabled: Bool
    var mpvID: Int64? = nil
}
