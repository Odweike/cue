import AppKit
import Libmpv
import OpenGL.GL

final class MPVOpenGLView: NSOpenGLView {
    nonisolated(unsafe) private var renderContext: OpaquePointer?

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
        if event.keyCode == 49 {
            return
        }
        super.keyDown(with: event)
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
        if let renderContext {
            mpv_render_context_set_update_callback(renderContext, nil, nil)
            mpv_render_context_free(renderContext)
        }
    }

    func attach(to playerContext: OpaquePointer) {
        wantsBestResolutionOpenGLSurface = true
        openGLContext?.makeCurrentContext()

        var openGLParameters = mpv_opengl_init_params(
            get_proc_address: cueOpenGLProcAddress,
            get_proc_address_ctx: nil
        )
        let api = UnsafeMutableRawPointer(
            mutating: (MPV_RENDER_API_TYPE_OPENGL as NSString).utf8String
        )

        withUnsafeMutablePointer(to: &openGLParameters) { parameters in
            var renderParameters = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: api),
                mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: parameters),
                mpv_render_param()
            ]
            let status = mpv_render_context_create(&renderContext, playerContext, &renderParameters)
            precondition(status >= 0, "Could not initialize the mpv OpenGL renderer")
        }

        mpv_render_context_set_update_callback(
            renderContext,
            cueMPVRenderUpdate,
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    private var lastBackingSize = CGSize.zero

    override func reshape() {
        super.reshape()
        let size = convertToBacking(bounds).size
        guard size != lastBackingSize else { return }
        lastBackingSize = size
        openGLContext?.update()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let renderContext, let openGLContext else { return }
        openGLContext.makeCurrentContext()

        let size = convertToBacking(bounds).size
        glViewport(0, 0, GLsizei(size.width), GLsizei(size.height))
        glClearColor(0, 0, 0, 1)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))

        var framebuffer: GLint = 0
        glGetIntegerv(GLenum(GL_FRAMEBUFFER_BINDING), &framebuffer)
        var target = mpv_opengl_fbo(
            fbo: framebuffer,
            w: Int32(size.width),
            h: Int32(size.height),
            internal_format: 0
        )
        var flipY: Int32 = 1

        withUnsafeMutablePointer(to: &target) { target in
            withUnsafeMutablePointer(to: &flipY) { flipY in
                var parameters = [
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: target),
                    mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: flipY),
                    mpv_render_param()
                ]
                mpv_render_context_render(renderContext, &parameters)
            }
        }

        openGLContext.flushBuffer()
    }
}

private func cueMPVRenderUpdate(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let view = Unmanaged<MPVOpenGLView>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async {
        view.needsDisplay = true
    }
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
