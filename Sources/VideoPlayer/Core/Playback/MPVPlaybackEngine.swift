import AppKit
import Libmpv

@MainActor
final class MPVPlaybackEngine: PlaybackEngine {
    private let playerView = MPVMetalView()
    nonisolated(unsafe) private let context: OpaquePointer
    private let eventDrainer: MPVEventDrainer
    private var playbackRate: Float = 1
    private var videoScalingMode = VideoScalingMode.fit

    private(set) var currentURL: URL?
    var renderView: NSView { playerView }
    var state: PlaybackState {
        let isPaused = boolProperty("pause", fallback: true)
        let isIdle = boolProperty("core-idle", fallback: true)

        return PlaybackState(
            currentTime: nonnegative(doubleProperty("time-pos")),
            duration: nonnegative(doubleProperty("duration")),
            isPlaying: !isPaused && !isIdle,
            volume: Float(doubleProperty("volume", fallback: 100) / 100),
            isMuted: boolProperty("mute"),
            playbackRate: playbackRate,
            videoScalingMode: videoScalingMode
        )
    }

    init() {
        guard let context = mpv_create() else {
            preconditionFailure("Could not create the mpv playback context")
        }
        self.context = context
        eventDrainer = MPVEventDrainer(context: context)

        setOption("config", to: "no")
        setOption("terminal", to: "no")
        setOption("osc", to: "no")
        setOption("input-default-bindings", to: "no")
        setOption("input-media-keys", to: "no")
        setOption("ytdl", to: "no")
        setOption("keep-open", to: "yes")
        setOption("vo", to: "gpu-next")
        setOption("gpu-api", to: "vulkan")
        setOption("gpu-context", to: "moltenvk")
        setOption("hwdec", to: "videotoolbox")

        var windowID = Int64(Int(bitPattern: Unmanaged.passUnretained(playerView.metalLayer).toOpaque()))
        mpv_set_option(context, "wid", MPV_FORMAT_INT64, &windowID)

        let status = mpv_initialize(context)
        precondition(status >= 0, "Could not initialize mpv: \(Self.errorMessage(for: status))")

        mpv_set_wakeup_callback(
            context,
            cueMPVWakeup,
            Unmanaged.passUnretained(eventDrainer).toOpaque()
        )
    }

    deinit {
        mpv_set_wakeup_callback(context, nil, nil)
        eventDrainer.invalidate()
        mpv_terminate_destroy(context)
    }

    func open(_ url: URL) {
        currentURL = url
        command("loadfile", url.path, "replace")
    }

    func play() {
        setFlag("pause", to: false)
    }

    func pause() {
        setFlag("pause", to: true)
    }

    func seek(to time: TimeInterval) {
        let target = min(max(time, 0), state.duration)
        command("seek", String(target), "absolute")
    }

    func skip(by interval: TimeInterval) {
        command("seek", String(interval), "relative")
    }

    func setVolume(_ volume: Float) {
        setDouble("volume", to: Double(min(max(volume, 0), 1) * 100))
    }

    func setMuted(_ isMuted: Bool) {
        setFlag("mute", to: isMuted)
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = min(max(rate, 0.25), 2)
        setDouble("speed", to: Double(playbackRate))
    }

    func setVideoScalingMode(_ mode: VideoScalingMode) {
        videoScalingMode = mode
        setDouble("panscan", to: mode == .fit ? 0 : 1)
    }

    private func command(_ values: String...) {
        var arguments = values.map { UnsafePointer<CChar>(strdup($0)) }
        arguments.append(nil)
        defer { arguments.compactMap { $0 }.forEach { free(UnsafeMutablePointer(mutating: $0)) } }
        mpv_command(context, &arguments)
    }

    private func setOption(_ name: String, to value: String) {
        let status = mpv_set_option_string(context, name, value)
        if status < 0 {
            assertionFailure("mpv option \(name) failed: \(Self.errorMessage(for: status))")
        }
    }

    private func setFlag(_ name: String, to value: Bool) {
        var flag: Int32 = value ? 1 : 0
        mpv_set_property(context, name, MPV_FORMAT_FLAG, &flag)
    }

    private func setDouble(_ name: String, to value: Double) {
        var value = value
        mpv_set_property(context, name, MPV_FORMAT_DOUBLE, &value)
    }

    private func boolProperty(_ name: String, fallback: Bool = false) -> Bool {
        var value: Int32 = fallback ? 1 : 0
        guard mpv_get_property(context, name, MPV_FORMAT_FLAG, &value) >= 0 else { return fallback }
        return value != 0
    }

    private func doubleProperty(_ name: String, fallback: Double = 0) -> Double {
        var value = fallback
        guard mpv_get_property(context, name, MPV_FORMAT_DOUBLE, &value) >= 0 else { return fallback }
        return value
    }

    private func nonnegative(_ value: Double) -> TimeInterval {
        value.isFinite ? max(value, 0) : 0
    }

    private static func errorMessage(for status: Int32) -> String {
        guard let message = mpv_error_string(status) else { return "unknown error \(status)" }
        return String(cString: message)
    }
}

private final class MPVEventDrainer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.maxim.cue.mpv-events")
    private var context: OpaquePointer?

    init(context: OpaquePointer) {
        self.context = context
    }

    func wakeUp() {
        queue.async { [self] in
            while let context,
                  mpv_wait_event(context, 0).pointee.event_id != MPV_EVENT_NONE {}
        }
    }

    func invalidate() {
        queue.sync {
            context = nil
        }
    }
}

private func cueMPVWakeup(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    Unmanaged<MPVEventDrainer>.fromOpaque(context).takeUnretainedValue().wakeUp()
}
