import AppKit
import CoreVideo
import Libmpv
import OpenGL.GL

final class MPVOpenGLView: NSOpenGLView {
    private let renderer = MPVFrameRenderer()
    nonisolated(unsafe) private var displayLink: CVDisplayLink?
    nonisolated(unsafe) private var idleTimer: Timer?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            window?.toggleFullScreen(nil)
            return
        }
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49, 123, 124, 125, 126:
            return
        default:
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.keyCode == 49,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else {
            return super.performKeyEquivalent(with: event)
        }
        let responder = window?.firstResponder
        if responder is NSTextView || responder is NSTextField {
            return false
        }
        return true
    }

    override class func defaultPixelFormat() -> NSOpenGLPixelFormat {
        let attributes: [NSOpenGLPixelFormatAttribute] = [
            NSOpenGLPixelFormatAttribute(NSOpenGLPFADoubleBuffer),
            NSOpenGLPixelFormatAttribute(NSOpenGLPFAAccelerated),
            NSOpenGLPixelFormatAttribute(NSOpenGLPFAColorSize),
            NSOpenGLPixelFormatAttribute(24),
            NSOpenGLPixelFormatAttribute(NSOpenGLPFAAlphaSize),
            NSOpenGLPixelFormatAttribute(8),
            NSOpenGLPixelFormatAttribute(0)
        ]
        return NSOpenGLPixelFormat(attributes: attributes)!
    }

    deinit {
        idleTimer?.invalidate()
        stopDisplayLink()
        renderer.shutdown()
    }

    func attach(to playerContext: OpaquePointer) {
        wantsBestResolutionOpenGLSurface = true
        guard let glContext = openGLContext else { return }
        glContext.makeCurrentContext()
        var swapInterval: GLint = 1
        glContext.setValues(&swapInterval, for: .swapInterval)
        renderer.attach(playerContext: playerContext, glContext: glContext)
    }

    func displayActive() {
        idleTimer?.invalidate()
        idleTimer = nil
        startDisplayLinkIfNeeded()
    }

    func displayIdle() {
        idleTimer?.invalidate()
        // ponytail: 6s matches IINA/QuickTime so short pause/seek doesn't flap the link
        idleTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            self?.stopDisplayLink()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        renderer.backingSize = convertToBacking(bounds).size
        if window == nil {
            idleTimer?.invalidate()
            idleTimer = nil
            stopDisplayLink()
        } else {
            renderer.schedulePaint()
        }
    }

    override func reshape() {
        super.reshape()
        let size = convertToBacking(bounds).size
        guard size != renderer.backingSize else { return }
        renderer.backingSize = size
        openGLContext?.update()
        renderer.schedulePaint()
    }

    override func draw(_ dirtyRect: NSRect) {
        renderer.schedulePaint()
    }

    private func startDisplayLinkIfNeeded() {
        if let displayLink, CVDisplayLinkIsRunning(displayLink) { return }
        let link: CVDisplayLink
        if let displayLink {
            link = displayLink
        } else {
            var created: CVDisplayLink?
            CVDisplayLinkCreateWithActiveCGDisplays(&created)
            guard let created else { return }
            CVDisplayLinkSetOutputCallback(
                created,
                cueDisplayLinkCallback,
                Unmanaged.passUnretained(renderer).toOpaque()
            )
            displayLink = created
            link = created
        }
        CVDisplayLinkStart(link)
    }

    nonisolated private func stopDisplayLink() {
        guard let displayLink, CVDisplayLinkIsRunning(displayLink) else { return }
        CVDisplayLinkStop(displayLink)
    }
}

/// Draws mpv frames off the main thread, same idea as IINA's ViewLayer + mpvGLQueue.
private final class MPVFrameRenderer: @unchecked Sendable {
    let queue = DispatchQueue(label: "dev.maxim.cue.mpv-gl", qos: .userInteractive)
    var backingSize = CGSize.zero
    private var renderContext: OpaquePointer?
    private var glContext: NSOpenGLContext?

    func attach(playerContext: OpaquePointer, glContext: NSOpenGLContext) {
        self.glContext = glContext

        var openGLParameters = mpv_opengl_init_params(
            get_proc_address: cueOpenGLProcAddress,
            get_proc_address_ctx: nil
        )
        let api = UnsafeMutableRawPointer(
            mutating: (MPV_RENDER_API_TYPE_OPENGL as NSString).utf8String
        )
        var advanced: Int32 = 1

        withUnsafeMutablePointer(to: &openGLParameters) { parameters in
            withUnsafeMutablePointer(to: &advanced) { advanced in
                var renderParameters = [
                    mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: api),
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: parameters),
                    mpv_render_param(type: MPV_RENDER_PARAM_ADVANCED_CONTROL, data: advanced),
                    mpv_render_param()
                ]
                let status = mpv_render_context_create(&renderContext, playerContext, &renderParameters)
                precondition(status >= 0, "Could not initialize the mpv OpenGL renderer")
            }
        }

        mpv_render_context_set_update_callback(
            renderContext,
            cueMPVRenderUpdate,
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    func shutdown() {
        if let renderContext {
            mpv_render_context_set_update_callback(renderContext, nil, nil)
        }
        queue.sync {}
        if let renderContext {
            mpv_render_context_free(renderContext)
        }
        renderContext = nil
        glContext = nil
    }

    func schedulePaint() {
        queue.async { [self] in
            paint()
        }
    }

    func reportSwap() {
        queue.async { [self] in
            guard let renderContext else { return }
            mpv_render_context_report_swap(renderContext)
        }
    }

    private func paint() {
        guard let renderContext, let glContext else { return }
        glContext.lock()
        defer { glContext.unlock() }
        glContext.makeCurrentContext()

        let flags = mpv_render_context_update(renderContext)
        guard flags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) != 0 else { return }

        let size = backingSize
        guard size.width > 0, size.height > 0 else { return }

        glViewport(0, 0, GLsizei(size.width), GLsizei(size.height))
        glClearColor(0, 0, 0, 1)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))

        var target = mpv_opengl_fbo(
            fbo: 0,
            w: Int32(size.width),
            h: Int32(size.height),
            internal_format: 0
        )
        var flipY: Int32 = 1
        var blockForTarget: Int32 = 0

        withUnsafeMutablePointer(to: &target) { target in
            withUnsafeMutablePointer(to: &flipY) { flipY in
                withUnsafeMutablePointer(to: &blockForTarget) { blockForTarget in
                    var parameters = [
                        mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: target),
                        mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: flipY),
                        mpv_render_param(type: MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME, data: blockForTarget),
                        mpv_render_param()
                    ]
                    mpv_render_context_render(renderContext, &parameters)
                }
            }
        }

        glContext.flushBuffer()
    }
}

private func cueMPVRenderUpdate(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    Unmanaged<MPVFrameRenderer>.fromOpaque(context).takeUnretainedValue().schedulePaint()
}

private func cueDisplayLinkCallback(
    _ displayLink: CVDisplayLink,
    _ inNow: UnsafePointer<CVTimeStamp>,
    _ inOutputTime: UnsafePointer<CVTimeStamp>,
    _ flagsIn: CVOptionFlags,
    _ flagsOut: UnsafeMutablePointer<CVOptionFlags>,
    _ context: UnsafeMutableRawPointer?
) -> CVReturn {
    guard let context else { return kCVReturnSuccess }
    Unmanaged<MPVFrameRenderer>.fromOpaque(context).takeUnretainedValue().reportSwap()
    return kCVReturnSuccess
}

private func cueOpenGLProcAddress(
    _ context: UnsafeMutableRawPointer?,
    _ name: UnsafePointer<CChar>?
) -> UnsafeMutableRawPointer? {
    guard let name,
          let bundle = CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString),
          let symbol = CFStringCreateWithCString(
              kCFAllocatorDefault,
              name,
              CFStringBuiltInEncodings.ASCII.rawValue
          ) else {
        return nil
    }
    return CFBundleGetFunctionPointerForName(bundle, symbol)
}
