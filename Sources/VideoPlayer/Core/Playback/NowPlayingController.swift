import AppKit
import MediaPlayer

@MainActor
final class NowPlayingController {
    private weak var viewModel: PlayerViewModel?
    private var isActive = false

    func attach(_ viewModel: PlayerViewModel) {
        self.viewModel = viewModel
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in
            self?.viewModel?.playIfNeeded()
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            self?.viewModel?.pauseIfNeeded()
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.viewModel?.togglePlayback()
            return .success
        }
        commands.skipForwardCommand.preferredIntervals = [10]
        commands.skipForwardCommand.addTarget { [weak self] _ in
            self?.viewModel?.skip(by: 10)
            return .success
        }
        commands.skipBackwardCommand.preferredIntervals = [10]
        commands.skipBackwardCommand.addTarget { [weak self] _ in
            self?.viewModel?.skip(by: -10)
            return .success
        }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.viewModel?.seek(to: event.positionTime)
            return .success
        }
    }

    func update(title: String, time: TimeInterval, duration: TimeInterval, isPlaying: Bool, rate: Float) {
        guard isActive else { return }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = title
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(rate) : 0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = Double(rate)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    func start(title: String) {
        isActive = true
        MPNowPlayingInfoCenter.default().playbackState = .paused
        update(title: title, time: 0, duration: 0, isPlaying: false, rate: 1)
    }

    func stop() {
        isActive = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
}
