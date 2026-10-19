import SwiftUI
import Combine

/// Exceptions from the Laravel sites' storage/logs/laravel.log, newest first.
struct ExceptionsView: View {
    @Environment(AppState.self) private var state
    @State private var exceptions: [LoggedException] = []
    @State private var stamps: [String: [Double]] = [:]     // log path: [mtime, size]
    @State private var cache: [String: [LoggedException]] = [:]
    @State private var selection: LoggedException.ID?
    @State private var site: String?
    @State private var filter = ""
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var logs: [(site: String, url: URL)] {
        state.sites.filter(\.isLaravel).map { ($0.name, $0.path.appendingPathComponent("storage/logs/laravel.log")) }
    }

    private var filtered: [LoggedException] {
        exceptions.filter { e in
            (site == nil || e.site == site)
                && (filter.isEmpty || e.message.localizedCaseInsensitiveContains(filter)
                    || (e.exceptionClass ?? "").localizedCaseInsensitiveContains(filter))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            HStack(spacing: 0) {
                List(filtered, selection: $selection) { e in
                    ExceptionRow(exception: e).tag(e.id)
                }
                .scrollContentBackground(.hidden)
                .frame(width: 300)
                .overlay {
                    if filtered.isEmpty {
                        ContentUnavailableView {
                            Label { Text("İstisna yok") } icon: { NerdIcon(name: "exclamationmark.triangle", size: 34) }
                        } description: {
                            Text(logs.isEmpty ? "Laravel sitesi bulunamadı." : "Laravel sitelerinizin loglarına düşen hatalar burada listelenir.")
                        }
                    }
                }
                Divider()
                Group {
                    if let e = exceptions.first(where: { $0.id == selection }) {
                        ExceptionDetail(exception: e).id(e.id)
                    } else {
                        ContentUnavailableView("İstisna seçin", systemImage: "exclamationmark.triangle")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
            .padding([.horizontal, .bottom], 14)
        }
        .onAppear { reload() }
        .onReceive(timer) { _ in reload() }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("İstisnalar").font(.system(size: 17, weight: .semibold))
                Text("storage/logs/laravel.log · \(exceptions.count) kayıt")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if logs.count > 1 {
                Picker("", selection: $site) {
                    Text("Tüm siteler").tag(String?.none)
                    ForEach(logs, id: \.site) { Text(verbatim: $0.site).tag(String?.some($0.site)) }
                }
                .labelsHidden().fixedSize()
            }
            TextField("Filtrele", text: $filter)
                .textFieldStyle(.roundedBorder).frame(width: 160)
        }
        .controlSize(.small)
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
    }

    /// Re-parses only the logs whose size or date changed.
    private func reload() {
        var changed = false
        var seen = Set<String>()
        for log in logs {
            let path = log.url.path
            seen.insert(path)
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            let stamp = [(attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0, Double((attrs?[.size] as? Int) ?? 0)]
            guard stamps[path] != stamp else { continue }
            stamps[path] = stamp
            cache[path] = attrs == nil ? [] : LaravelLog.read(log.url, site: log.site)
            changed = true
        }
        for path in cache.keys where !seen.contains(path) { cache[path] = nil; stamps[path] = nil; changed = true }
        guard changed else { return }
        exceptions = cache.values.flatMap { $0 }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        if selection == nil || !exceptions.contains(where: { $0.id == selection }) { selection = filtered.first?.id }
    }
}

private struct ExceptionRow: View {
    let exception: LoggedException

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(verbatim: exception.shortClass ?? exception.level).font(.callout.weight(.semibold)).lineLimit(1)
                Spacer()
                if let date = exception.date {
                    Text(date, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(verbatim: exception.message).font(.callout).lineLimit(2).foregroundStyle(.primary.opacity(0.85))
            Text(verbatim: exception.site).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}

private struct ExceptionDetail: View {
    @Environment(AppState.self) private var state
    let exception: LoggedException
    @State private var expanded: Set<Int> = []    // first index of each opened vendor run

    /// App frames one by one, runs of vendor frames folded into one row.
    private var groups: [[LoggedException.Frame]] {
        var result: [[LoggedException.Frame]] = []
        for f in exception.frames {
            if f.isVendor, let last = result.last, last.first?.isVendor == true {
                result[result.count - 1].append(f)
            } else {
                result.append([f])
            }
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Chip(text: LocalizedStringKey(exception.level), tone: .negative)
                        if let cls = exception.exceptionClass {
                            Text(verbatim: cls).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                                .textSelection(.enabled).lineLimit(1).truncationMode(.head)
                        }
                        Spacer()
                        if let date = exception.date {
                            Text(date, format: .dateTime).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text(verbatim: exception.message)
                        .font(.system(size: 15, weight: .semibold)).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if let file = exception.file {
                        sourceButton(file, exception.line)
                    }
                    ForEach(exception.previous, id: \.self) { p in
                        Text(verbatim: "↳ " + p).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }

                if !exception.frames.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Yığın izi").font(.headline).padding(.bottom, 6)
                        ForEach(groups, id: \.first!.index) { group in
                            if group.count > 1 || group.first?.isVendor == true, let first = group.first?.index {
                                DisclosureGroup(isExpanded: Binding(
                                    get: { expanded.contains(first) },
                                    set: { if $0 { expanded.insert(first) } else { expanded.remove(first) } })) {
                                    ForEach(group, id: \.index) { frameRow($0) }
                                } label: {
                                    Text("\(group.count) vendor çerçevesi").font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 3)
                            } else if let f = group.first {
                                frameRow(f)
                            }
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func frameRow(_ f: LoggedException.Frame) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: "#\(f.index)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
                .frame(width: 28, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: f.call.isEmpty ? "—" : f.call)
                    .font(.system(size: 11.5, design: .monospaced)).textSelection(.enabled)
                    .foregroundStyle(f.isVendor ? .secondary : .primary)
                if let file = f.file { sourceButton(file, f.line) }
            }
        }
        .padding(.vertical, 3)
    }

    private func sourceButton(_ file: String, _ line: Int?) -> some View {
        let site = state.sites.first { file.hasPrefix($0.path.path + "/") }
        let shown = site.map { String(file.dropFirst($0.path.path.count + 1)) } ?? file
        return Button { state.openInEditor(URL(fileURLWithPath: file), line: line) } label: {
            Text(verbatim: shown + (line.map { ":\($0)" } ?? ""))
                .font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle)
        }
        .buttonStyle(.link)
        .help("Editörde aç")
    }
}
