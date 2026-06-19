import Foundation

// MARK: - Diagnostic Log (opt-in)
// Records per-stage *timings only* (no transcript content) to a file so rare,
// hard-to-reproduce hangs can be traced after the fact. Off by default; the
// user enables it in Settings, reproduces over normal use, then shares the log.

enum DiagnosticLog {
    nonisolated(unsafe) static var enabled = false

    static let path = NSHomeDirectory() + "/punktype-diagnostics.log"

    static func log(_ message: String) {
        guard enabled else { return }
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: path)
        if let fh = try? FileHandle(forWritingTo: url) {
            defer { try? fh.close() }
            fh.seekToEndOfFile()
            fh.write(data)
        } else {
            try? data.write(to: url)
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(atPath: path)
    }
}
