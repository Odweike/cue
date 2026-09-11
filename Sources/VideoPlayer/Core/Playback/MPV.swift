import Foundation
import Libmpv

/// Shared low-level helpers for talking to an mpv context.
/// Callers keep their own domain-specific error types; these return raw status codes.
enum MPV {
    static func errorMessage(for status: Int32) -> String {
        guard let message = mpv_error_string(status) else { return "unknown error \(status)" }
        return String(cString: message)
    }

    @discardableResult
    static func setOption(_ name: String, to value: String, on context: OpaquePointer) -> Int32 {
        mpv_set_option_string(context, name, value)
    }

    @discardableResult
    static func command(_ values: [String], on context: OpaquePointer) -> Int32 {
        var arguments = values.map { UnsafePointer<CChar>(strdup($0)) }
        arguments.append(nil)
        defer { arguments.compactMap { $0 }.forEach { free(UnsafeMutablePointer(mutating: $0)) } }
        return mpv_command(context, &arguments)
    }
}
