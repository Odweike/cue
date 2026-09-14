import Foundation

@MainActor
enum SleepPreventer {
    private static var activity: NSObjectProtocol?

    static func update(isPlaying: Bool) {
        if isPlaying {
            guard activity == nil else { return }
            activity = ProcessInfo.processInfo.beginActivity(
                options: .idleDisplaySleepDisabled,
                reason: "Cue playback is in progress"
            )
        } else {
            guard let activity else { return }
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }
}
