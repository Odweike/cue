import Foundation

struct SubtitleCue: Identifiable, Hashable, Sendable {
    let id: UUID
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
    let trackID: UUID

    init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String,
        trackID: UUID
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.trackID = trackID
    }
}

