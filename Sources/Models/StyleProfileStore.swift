import SwiftUI
import Foundation

// MARK: - Style Profile Store
// A short (≤~150 字) description of the user's expression style, learned
// incrementally after each output and injected into the polish prompt so the
// cleaned text sounds like the user. Fully local, viewable and editable.

@MainActor
final class StyleProfileStore: ObservableObject {
    static let shared = StyleProfileStore()

    @Published var profile: String = ""

    private let storageURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("PunkType")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        storageURL = folder.appendingPathComponent("style.txt")
        load()
    }

    var hasProfile: Bool {
        !profile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Set the profile (with a safety cap) and persist.
    func set(_ text: String) {
        profile = String(text.prefix(400))
        save()
    }

    func reset() {
        profile = ""
        save()
    }

    /// Style block appended to the polish prompt when "套用我的风格" is on.
    var promptBlock: String? {
        let p = profile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return nil }
        return "\n\n【我的表达风格】请在整理时贴合以下风格习惯，但不要改变原意、不要照搬示例词：\n\(p)"
    }

    // MARK: - Persistence

    private func save() {
        try? profile.write(to: storageURL, atomically: true, encoding: .utf8)
    }

    private func load() {
        profile = (try? String(contentsOf: storageURL, encoding: .utf8)) ?? ""
    }
}
