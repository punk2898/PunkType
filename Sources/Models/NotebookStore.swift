import SwiftUI
import Foundation

// MARK: - Notebook models

struct NotebookEntry: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var text: String
    var sourceApp: String
    var sourceBundleID: String
    var tier: String
    var timestamp: Date

    var timeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: timestamp)
    }
}

struct DailySummary: Codable, Equatable {
    var title: String
    var body: String      // markdown
    var generatedAt: Date
}

struct DailyNote: Codable {
    var date: String      // "yyyy-MM-dd"
    var entries: [NotebookEntry] = []
    var summary: DailySummary?
}

// MARK: - Notebook Store
// Passive capture of every dictation, grouped by day (one file per day), plus
// an optional AI "daily report". Apps can be excluded (e.g. 微信). Fully local.

@MainActor
final class NotebookStore: ObservableObject {
    static let shared = NotebookStore()

    @Published private(set) var availableDates: [String] = []   // newest first
    @Published var excludedBundleIDs: Set<String> = []
    @Published private(set) var knownApps: [String: String] = [:] // bundleID → name

    private let folder: URL
    private let configURL: URL

    /// In-memory cache of loaded days (this process is the only writer, so it
    /// stays consistent). Avoids re-reading files on every SwiftUI render.
    private var cache: [String: DailyNote] = [:]

    // 微信 default-excluded (personal chat, usually not work).
    private static let defaultExcluded: Set<String> = ["com.tencent.xinwechat"]

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        folder = appSupport.appendingPathComponent("PunkType/notebook")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        configURL = folder.appendingPathComponent("_config.json")
        loadConfig()
        refreshDates()
    }

    // MARK: - Keys

    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
    private func fileURL(_ key: String) -> URL { folder.appendingPathComponent("\(key).json") }

    func isExcluded(bundleID: String) -> Bool {
        excludedBundleIDs.contains(bundleID.lowercased())
    }

    // MARK: - Recording

    /// Append a dictation output to today's note (unless its app is excluded).
    func record(text: String, app: String, bundleID: String, tier: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Register the app so it shows up in the exclusion list, even if excluded.
        if !bundleID.isEmpty, knownApps[bundleID.lowercased()] != app {
            knownApps[bundleID.lowercased()] = app
            saveConfig()
        }
        guard !isExcluded(bundleID: bundleID) else { return }

        let key = Self.dayKey(Date())
        var note = loadDay(key) ?? DailyNote(date: key)
        note.entries.append(NotebookEntry(
            text: trimmed, sourceApp: app, sourceBundleID: bundleID,
            tier: tier, timestamp: Date()
        ))
        saveDay(note)
        refreshDates()
    }

    // MARK: - Day access

    func loadDay(_ key: String) -> DailyNote? {
        if let cached = cache[key] { return cached }
        guard let data = try? Data(contentsOf: fileURL(key)),
              let note = try? JSONDecoder().decode(DailyNote.self, from: data) else { return nil }
        cache[key] = note
        return note
    }

    func saveDay(_ note: DailyNote) {
        cache[note.date] = note
        if let data = try? JSONEncoder().encode(note) {
            try? data.write(to: fileURL(note.date))
        }
    }

    func updateEntry(day: String, _ entry: NotebookEntry) {
        guard var note = loadDay(day),
              let idx = note.entries.firstIndex(where: { $0.id == entry.id }) else { return }
        note.entries[idx] = entry
        saveDay(note)
        objectWillChange.send()
    }

    func deleteEntry(day: String, id: UUID) {
        guard var note = loadDay(day) else { return }
        note.entries.removeAll { $0.id == id }
        if note.entries.isEmpty && note.summary == nil {
            cache[day] = nil
            try? FileManager.default.removeItem(at: fileURL(day))
            refreshDates()
        } else {
            saveDay(note)
        }
        objectWillChange.send()
    }

    func setSummary(day: String, _ summary: DailySummary) {
        guard var note = loadDay(day) else { return }
        note.summary = summary
        saveDay(note)
        objectWillChange.send()
    }

    /// Full-text search across all days. Returns (day, entry) pairs.
    func search(_ query: String) -> [(day: String, entry: NotebookEntry)] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        var hits: [(String, NotebookEntry)] = []
        for day in availableDates {
            guard let note = loadDay(day) else { continue }
            for e in note.entries where e.text.lowercased().contains(q) {
                hits.append((day, e))
            }
        }
        return hits
    }

    // MARK: - Exclusions

    func setExcluded(_ bundleID: String, excluded: Bool) {
        let key = bundleID.lowercased()
        if excluded { excludedBundleIDs.insert(key) } else { excludedBundleIDs.remove(key) }
        saveConfig()
    }

    // MARK: - Persistence

    private struct Config: Codable { var excluded: [String]; var known: [String: String] }

    private func loadConfig() {
        if let data = try? Data(contentsOf: configURL),
           let c = try? JSONDecoder().decode(Config.self, from: data) {
            excludedBundleIDs = Set(c.excluded)
            knownApps = c.known
        } else {
            excludedBundleIDs = Self.defaultExcluded
            saveConfig()
        }
    }

    private func saveConfig() {
        let c = Config(excluded: Array(excludedBundleIDs), known: knownApps)
        if let data = try? JSONEncoder().encode(c) {
            try? data.write(to: configURL)
        }
    }

    private func refreshDates() {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        availableDates = files
            .filter { $0.hasSuffix(".json") && !$0.hasPrefix("_") }
            .map { String($0.dropLast(5)) }
            .sorted(by: >)
    }
}
