import AppKit
import Libmpv

/// Background filmstrip for timeline hover. Own mpv + software renderer, never seeks the playing file.
final class VideoThumbnailCache: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.maxim.cue.thumbs", qos: .utility)
    private let lock = NSLock()
    private var generation = UUID()
    private var thumbs: [(time: TimeInterval, image: NSImage)] = []

    func cancel() {
        lock.lock()
        generation = UUID()
        thumbs = []
        lock.unlock()
    }

    func image(at time: TimeInterval) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        return thumbs.min(by: { abs($0.time - time) < abs($1.time - time) })?.image
    }

    func prepare(url: URL, duration: TimeInterval) {
        let token = UUID()
        lock.lock()
        generation = token
        thumbs = []
        lock.unlock()
        queue.async { [weak self] in
            self?.generate(url: url, duration: duration, token: token)
        }
    }

    private func generate(url: URL, duration: TimeInterval, token: UUID) {
        guard duration > 1, let ctx = mpv_create() else { return }
        defer { mpv_terminate_destroy(ctx) }

        _ = MPV.setOption("config", to: "no", on: ctx)
        _ = MPV.setOption("terminal", to: "no", on: ctx)
        _ = MPV.setOption("vo", to: "libmpv", on: ctx)
        _ = MPV.setOption("hwdec", to: "no", on: ctx)
        _ = MPV.setOption("aid", to: "no", on: ctx)
        _ = MPV.setOption("sid", to: "no", on: ctx)
        _ = MPV.setOption("pause", to: "yes", on: ctx)
        _ = MPV.setOption("osc", to: "no", on: ctx)
        _ = MPV.setOption("osd-level", to: "0", on: ctx)
        _ = MPV.setOption("hr-seek", to: "yes", on: ctx)
        _ = MPV.setOption("keepaspect", to: "yes", on: ctx)
        guard mpv_initialize(ctx) >= 0 else { return }

        let api = UnsafeMutableRawPointer(mutating: (MPV_RENDER_API_TYPE_SW as NSString).utf8String)
        var renderContext: OpaquePointer?
        var params = [
            mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: api),
            mpv_render_param()
        ]
        guard mpv_render_context_create(&renderContext, ctx, &params) >= 0,
              let renderContext else { return }
        defer { mpv_render_context_free(renderContext) }

        _ = MPV.command(["loadfile", url.path(percentEncoded: false), "replace"], on: ctx)
        guard wait(ctx, for: MPV_EVENT_FILE_LOADED, timeout: 8) else { return }

        let count = min(24, max(8, Int(duration / 15)))
        let videoWidth = int64("dwidth", on: ctx)
        let videoHeight = int64("dheight", on: ctx)
        let points = Self.pointSize(
            videoWidth: videoWidth > 0 ? videoWidth : 16,
            videoHeight: videoHeight > 0 ? videoHeight : 9
        )
        let width = max(2, Int(points.width) * 2)
        let height = max(2, Int(points.height) * 2)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var size = [Int32(width), Int32(height)]
        var stride = Int32(width * 4)
        let format = strdup("bgr0")
        defer { free(format) }

        for index in 0..<count {
            guard isCurrent(token) else { return }
            let time = duration * (Double(index) + 0.5) / Double(count)
            _ = MPV.command(["seek", String(time), "absolute+exact"], on: ctx)
            _ = wait(ctx, for: MPV_EVENT_PLAYBACK_RESTART, timeout: 2)
            _ = mpv_render_context_update(renderContext)

            let rendered: Bool = pixels.withUnsafeMutableBytes { buffer in
                guard let pointer = buffer.baseAddress else { return false }
                return size.withUnsafeMutableBufferPointer { size in
                    withUnsafeMutablePointer(to: &stride) { stride in
                        var renderParams = [
                            mpv_render_param(type: MPV_RENDER_PARAM_SW_SIZE, data: size.baseAddress),
                            mpv_render_param(type: MPV_RENDER_PARAM_SW_FORMAT, data: format),
                            mpv_render_param(type: MPV_RENDER_PARAM_SW_STRIDE, data: stride),
                            mpv_render_param(type: MPV_RENDER_PARAM_SW_POINTER, data: pointer),
                            mpv_render_param()
                        ]
                        return mpv_render_context_render(renderContext, &renderParams) >= 0
                    }
                }
            }
            guard rendered, let image = nsImage(from: pixels, pixelWidth: width, pixelHeight: height, pointSize: points) else { continue }
            lock.lock()
            if generation == token {
                thumbs.append((time, image))
            }
            lock.unlock()
        }
    }

    private func isCurrent(_ token: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == token
    }

    private func wait(_ ctx: OpaquePointer, for event: mpv_event_id, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let received = mpv_wait_event(ctx, 0.05).pointee.event_id
            if received == event { return true }
            if received == MPV_EVENT_END_FILE { return false }
        }
        return false
    }

    private func nsImage(from pixels: [UInt8], pixelWidth: Int, pixelHeight: Int, pointSize: NSSize) -> NSImage? {
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: pixelWidth * 4,
            bitsPerPixel: 32
        ), let dest = representation.bitmapData else { return nil }

        for y in 0..<pixelHeight {
            for x in 0..<pixelWidth {
                let i = (y * pixelWidth + x) * 4
                dest[i] = pixels[i + 2]
                dest[i + 1] = pixels[i + 1]
                dest[i + 2] = pixels[i]
                dest[i + 3] = 255
            }
        }
        representation.size = pointSize
        let image = NSImage(size: pointSize)
        image.addRepresentation(representation)
        return image
    }

    private func int64(_ name: String, on ctx: OpaquePointer) -> Int {
        var value: Int64 = 0
        guard mpv_get_property(ctx, name, MPV_FORMAT_INT64, &value) >= 0 else { return 0 }
        return Int(value)
    }

    static func pointSize(videoWidth: Int, videoHeight: Int, maxEdge: CGFloat = 240) -> NSSize {
        let width = max(videoWidth, 1)
        let height = max(videoHeight, 1)
        if width >= height {
            let pointWidth = maxEdge
            return NSSize(width: pointWidth, height: max(1, (pointWidth * CGFloat(height) / CGFloat(width)).rounded()))
        }
        let pointHeight = maxEdge
        return NSSize(width: max(1, (pointHeight * CGFloat(width) / CGFloat(height)).rounded()), height: pointHeight)
    }
}
