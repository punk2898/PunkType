import SwiftUI

// MARK: - Notebook Window
// Left: day list. Right: selected day's report + entries. Top: global search.

struct NotebookView: View {
    @ObservedObject var store = NotebookStore.shared
    weak var appDelegate: AppDelegate?

    @State private var selectedDay: String?
    @State private var query = ""
    @State private var generating = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .frame(minWidth: 210)
        } detail: {
            detail
        }
        .frame(minWidth: 740, minHeight: 500)
        .onAppear { if selectedDay == nil { selectedDay = store.availableDates.first } }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        Group {
            if store.availableDates.isEmpty {
                ContentUnavailableView(
                    "还没有记录",
                    systemImage: "book.closed",
                    description: Text("语音输入后内容会自动收进这里。")
                )
            } else {
                List(store.availableDates, id: \.self, selection: $selectedDay) { day in
                    dayRow(day)
                }
                .listStyle(.sidebar)
            }
        }
        .navigationTitle("记事本")
    }

    private func dayRow(_ day: String) -> some View {
        let note = store.loadDay(day)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(weekday(day))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(shortDate(day))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if let c = note?.entries.count, c > 0 {
                    Text("\(c)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            Text(note?.summary?.title ?? "未生成日报")
                .font(.caption)
                .foregroundStyle(note?.summary == nil ? .tertiary : .secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 3)
        .tag(day)
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索全部记录…", text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(.regularMaterial)

            Divider()

            if !query.isEmpty {
                searchResults
            } else if let day = selectedDay, let note = store.loadDay(day) {
                dayContent(day: day, note: note)
            } else {
                ContentUnavailableView("选择左侧的某一天", systemImage: "calendar")
            }
        }
    }

    private func dayContent(day: String, note: DailyNote) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Day header
                HStack(alignment: .firstTextBaseline) {
                    Text(longDate(day)).font(.system(size: 20, weight: .bold))
                    Spacer()
                    Text("\(note.entries.count) 条").font(.caption).foregroundStyle(.secondary)
                }

                reportCard(day: day, note: note)

                // Entries
                VStack(spacing: 8) {
                    ForEach(note.entries.reversed()) { entry in
                        EntryRow(day: day, entry: entry, store: store)
                    }
                }
            }
            .padding(20)
        }
    }

    private func reportCard(day: String, note: DailyNote) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("今日总结", systemImage: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tint)
                Spacer()
                Button { generate(day: day) } label: {
                    HStack(spacing: 4) {
                        if generating { ProgressView().scaleEffect(0.5).frame(width: 12, height: 12) }
                        Text(note.summary == nil ? "生成日报" : "重新生成")
                    }
                }
                .controlSize(.small)
                .disabled(generating || note.entries.isEmpty)
            }
            if let s = note.summary {
                Text(s.title).font(.system(size: 15, weight: .semibold))
                ReportBodyView(text: s.body)
            } else {
                Text(note.entries.isEmpty ? "今天还没有记录。" : "还没生成日报，点右上角生成。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.accentColor.opacity(0.07))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor.opacity(0.15)))
        )
    }

    private var searchResults: some View {
        let hits = store.search(query)
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if hits.isEmpty {
                    Text("没有匹配的记录").foregroundStyle(.secondary).padding(.top, 40)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("\(hits.count) 条结果").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(hits.enumerated()), id: \.offset) { _, hit in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(shortDate(hit.day)) · \(hit.entry.timeLabel) · \(hit.entry.sourceApp)")
                                .font(.caption2).foregroundStyle(.secondary)
                            Text(hit.entry.text).font(.system(size: 13))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.secondary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - Actions

    private func generate(day: String) {
        guard let note = store.loadDay(day), !note.entries.isEmpty else { return }
        generating = true
        let text = note.entries
            .map { "\($0.timeLabel) [\($0.sourceApp)] \($0.text)" }
            .joined(separator: "\n")
        appDelegate?.generateDailyReport(day: day, entriesText: text) { generating = false }
    }

    // MARK: - Date formatting

    private func date(_ key: String) -> Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: key)
    }
    private func fmt(_ key: String, _ pattern: String) -> String {
        guard let d = date(key) else { return key }
        let f = DateFormatter(); f.dateFormat = pattern; f.locale = Locale(identifier: "zh_CN")
        return f.string(from: d)
    }
    private func weekday(_ key: String) -> String { fmt(key, "EEE") }
    private func shortDate(_ key: String) -> String { fmt(key, "M月d日") }
    private func longDate(_ key: String) -> String { fmt(key, "M月d日 EEEE") }
}

// MARK: - Report body (lightweight markdown rendering)

private struct ReportBodyView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                row(line)
            }
        }
    }

    private var lines: [String] {
        text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    @ViewBuilder private func row(_ raw: String) -> some View {
        let t = raw.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("#") || (t.hasPrefix("**") && t.hasSuffix("**")) {
            Text(strip(t))
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 4)
        } else if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("• ") {
            HStack(alignment: .top, spacing: 6) {
                Text("•").foregroundStyle(.secondary)
                Text(LocalizedStringKey(String(t.dropFirst(2)))).font(.system(size: 13))
            }
        } else {
            Text(LocalizedStringKey(t)).font(.system(size: 13))
        }
    }

    private func strip(_ s: String) -> String {
        s.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Entry row (inline editable)

private struct EntryRow: View {
    let day: String
    @State var entry: NotebookEntry
    let store: NotebookStore
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(entry.timeLabel)
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Text(entry.sourceApp)
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundStyle(.tint)
                    .clipShape(Capsule())
                Spacer()
                Button {
                    if editing { store.updateEntry(day: day, entry) }
                    editing.toggle()
                } label: {
                    Image(systemName: editing ? "checkmark.circle.fill" : "pencil").font(.caption)
                }
                .buttonStyle(.borderless)
                Button { store.deleteEntry(day: day, id: entry.id) } label: {
                    Image(systemName: "trash").font(.caption).foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
            }
            if editing {
                TextEditor(text: $entry.text)
                    .font(.system(size: 13)).frame(minHeight: 60).padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.3)))
            } else {
                Text(entry.text)
                    .font(.system(size: 13)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}
