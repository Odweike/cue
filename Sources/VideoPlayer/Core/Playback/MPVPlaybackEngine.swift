import AppKit
import Libmpv

@MainActor
final class MPVPlaybackEngine: PlaybackEngine {
    private let playerView = MPVOpenGLView(frame: .zero)
    nonisolated(unsafe) private let context: OpaquePointer
    private let eventDrainer: MPVEventDrainer
    private var playbackRate: Float = 1
    private var videoScalingMode = VideoScalingMode.fit
    private var aspectRatio = VideoRatio.automatic
    private var cropRatio = VideoRatio.automatic
    private var rotation = VideoRotation.degrees0
    private var hardwareDecoding = true
    private var deinterlacing = false
    private var videoEqualizer = VideoEqualizer()
    private var audioDelay: TimeInterval = 0

    private(set) var currentURL: URL?
    var renderView: NSView { playerView }
    var state: PlaybackState {
        let isPaused = boolProperty("pause")

        return PlaybackState(
            currentTime: nonnegative(doubleProperty("time-pos")),
            duration: nonnegative(doubleProperty("duration")),
            isPlaying: !isPaused,
            volume: Float(doubleProperty("volume", fallback: 100) / 100),
            isMuted: boolProperty("mute"),
            playbackRate: playbackRate,
            videoScalingMode: videoScalingMode,
            aspectRatio: aspectRatio,
            cropRatio: cropRatio,
            rotation: rotation,
            hardwareDecoding: hardwareDecoding,
            deinterlacing: deinterlacing,
            videoEqualizer: videoEqualizer,
            audioDelay: audioDelay
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
        setOption("input-vo-keyboard", to: "no")
        setOption("input-media-keys", to: "no")
        setOption("ytdl", to: "no")
        setOption("keep-open", to: "yes")
        setOption("keepaspect", to: "yes")
        setOption("video-unscaled", to: "no")
        setOption("panscan", to: "0")
        setOption("video-align-x", to: "0")
        setOption("video-align-y", to: "0")
        setOption("vo", to: "libmpv")
        setOption("hwdec", to: "videotoolbox-copy")
        setOption("sid", to: "no")
        setOption("sub-visibility", to: "no")

        let status = mpv_initialize(context)
        precondition(status >= 0, "Could not initialize mpv: \(Self.errorMessage(for: status))")
        playerView.attach(to: context)

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
        command("loadfile", url.path(percentEncoded: false), "replace")
        play()
    }

    func play() {
        setFlag("pause", to: false)
    }

    func pause() {
        setFlag("pause", to: true)
    }

    func seek(to time: TimeInterval, exact: Bool) {
        let mode = exact ? "absolute+exact" : "absolute+keyframes"
        command("seek", String(max(time, 0)), mode)
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
        playbackRate = min(max(rate, 0.25), 16)
        setDouble("speed", to: Double(playbackRate))
    }

    func setVideoScalingMode(_ mode: VideoScalingMode) {
        videoScalingMode = mode
        setDouble("panscan", to: mode == .fit ? 0 : 1)
    }

    func setAspectRatio(_ ratio: VideoRatio) {
        aspectRatio = ratio
        setString("video-aspect-override", to: ratio.mpvValue)
    }

    func setCropRatio(_ ratio: VideoRatio) {
        cropRatio = ratio
        setString("video-crop", to: ratio == .automatic ? "" : ratio.rawValue)
    }

    func setRotation(_ rotation: VideoRotation) {
        self.rotation = rotation
        setDouble("video-rotate", to: Double(rotation.rawValue))
    }

    func setHardwareDecoding(_ isEnabled: Bool) {
        hardwareDecoding = isEnabled
        setString("hwdec", to: isEnabled ? "videotoolbox-copy" : "no")
    }

    func setDeinterlacing(_ isEnabled: Bool) {
        deinterlacing = isEnabled
        setFlag("deinterlace", to: isEnabled)
    }

    func setVideoEqualizer(_ equalizer: VideoEqualizer) {
        videoEqualizer = equalizer
        setDouble("brightness", to: equalizer.brightness)
        setDouble("contrast", to: equalizer.contrast)
        setDouble("saturation", to: equalizer.saturation)
        setDouble("gamma", to: equalizer.gamma)
        setDouble("hue", to: equalizer.hue)
    }

    func audioTracks() -> [AudioTrack] {
        let count = max(int64Property("track-list/count"), 0)
        return (0..<count).compactMap { index in
            let prefix = "track-list/\(index)"
            guard stringProperty("\(prefix)/type") == "audio" else { return nil }
            return AudioTrack(
                id: int64Property("\(prefix)/id"),
                title: stringProperty("\(prefix)/title"),
                language: stringProperty("\(prefix)/lang"),
                codec: stringProperty("\(prefix)/codec"),
                channelCount: Int(int64Property("\(prefix)/demux-channel-count")),
                isSelected: boolProperty("\(prefix)/selected")
            )
        }
    }

    func subtitleStreams() -> [SubtitleStream] {
        let count = max(int64Property("track-list/count"), 0)
        var subtitleOrdinal = 0
        return (0..<count).compactMap { index in
            let prefix = "track-list/\(index)"
            guard stringProperty("\(prefix)/type") == "sub" else { return nil }
            defer { subtitleOrdinal += 1 }
            let title = stringProperty("\(prefix)/title")
            return SubtitleStream(
                id: int64Property("\(prefix)/id"),
                ffmpegMap: "0:s:\(subtitleOrdinal)",
                title: title,
                language: stringProperty("\(prefix)/lang"),
                codec: stringProperty("\(prefix)/codec"),
                isForced: boolProperty("\(prefix)/forced")
                    || title?.localizedCaseInsensitiveContains("forced") == true,
                isDefault: boolProperty("\(prefix)/default")
            )
        }
    }

    func selectAudioTrack(_ id: Int64) {
        setInt64("aid", to: id)
    }

    func setAudioDelay(_ delay: TimeInterval) {
        audioDelay = min(max(delay, -5), 5)
        setDouble("audio-delay", to: audioDelay)
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

    private func setString(_ name: String, to value: String) {
        mpv_set_property_string(context, name, value)
    }

    private func setInt64(_ name: String, to value: Int64) {
        var value = value
        mpv_set_property(context, name, MPV_FORMAT_INT64, &value)
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

    private func int64Property(_ name: String, fallback: Int64 = 0) -> Int64 {
        var value = fallback
        guard mpv_get_property(context, name, MPV_FORMAT_INT64, &value) >= 0 else { return fallback }
        return value
    }

    private func stringProperty(_ name: String) -> String? {
        guard let value = mpv_get_property_string(context, name) else { return nil }
        defer { mpv_free(value) }
        return String(cString: value)
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
