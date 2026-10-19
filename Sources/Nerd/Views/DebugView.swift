import SwiftUI
import AppKit

/// A log the debug window can follow.
struct DebugSource: Identifiable, Hashable {
    var id: String { url.path }
    let title: String
    let group: String
    let icon: String
    let url: URL
}

extension AppState {
    var debugSources: [DebugSource] {
        let logs = Paths.logs
        var list = [DebugSource(title: "Caddy", group: String(localized: "Sunucu logları"), icon: "network", url: logs.appendingPathComponent("caddy.log"))]
        for v in installedPHP {
            list.append(DebugSource(title: "PHP \(v.version) · FPM", group: String(localized: "Sunucu logları"), icon: "chevron.left.forwardslash.chevron.right",
                                    url: logs.appendingPathComponent("\(v.key)-fpm-error.log")))
            list.append(DebugSource(title: String(localized: "PHP \(v.version) · hatalar"), group: String(localized: "Sunucu logları"), icon: "exclamationmark.triangle",
                                    url: logs.appendingPathComponent("\(v.key)-php-error.log")))
        }
        for site in sites {
            if site.isLaravel {
                list.append(DebugSource(title: site.name, group: String(localized: "Laravel logları"), icon: "leaf",
                                        url: site.path.appendingPathComponent("storage/logs/laravel.log")))
            }
            if site.hasPackageJSON || site.kind == .dotnet {
                list.append(DebugSource(title: site.name, group: String(localized: "Dev sunucuları"), icon: "play.fill",
                                        url: logs.appendingPathComponent("dev-\(site.name).log")))
            }
        }
        return list
    }
}

struct DebugView: View {
    @Environment(AppState.self) private var state
    @State private var selection: DebugSource.ID?
    @State private var text = ""
    @State private var filter = ""
    @State private var level = 0          // 0 all, 1 warnings and errors, 2 errors
    @State private var paused = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var source: DebugSource? { state.debugSources.first { $0.id == selection } ?? state.debugSources.first }

    private var lines: [Substring] {
        text.split(separator: "\n", omittingEmptySubsequences: false).suffix(2000).filter { line in
            (filter.isEmpty || line.localizedCaseInsensitiveContains(filter))
                && (level == 0 || Self.severity(line) >= level)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(Dictionary(grouping: state.debugSources, by: \.group).sorted { $0.key < $1.key }, id: \.key) { group in
                    Section(group.key) {
                        ForEach(group.value) { s in
                            Label { Text(verbatim: s.title) } icon: { NerdIcon(name: s.icon, size: 13) }
                                .tag(s.id)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        } detail: {
            VStack(spacing: 0) {
                toolbar
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                Text(verbatim: String(line).isEmpty ? " " : String(line))
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(Self.color(line))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Color.clear.frame(height: 1).id("end")
                        }
                        .padding(14)
                    }
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
                    .padding([.horizontal, .bottom], 14)
                    .onChange(of: text) { if !paused { proxy.scrollTo("end", anchor: .bottom) } }
                }
            }
            .background(Backdrop())
        }
        .tint(.brand)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .onAppear { reload() }
        .onChange(of: selection) { reload() }
        .onReceive(timer) { _ in if !paused { reload() } }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: source?.title ?? "Debug").font(.system(size: 17, weight: .semibold))
                Text(verbatim: (source?.url.path as NSString?)?.abbreviatingWithTildeInPath ?? "")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Picker("", selection: $level) {
                Text("Tümü").tag(0)
                Text("Uyarılar").tag(1)
                Text("Hatalar").tag(2)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            TextField("Filtrele", text: $filter)
                .textFieldStyle(.roundedBorder).frame(width: 160)
            Group {
                Button { paused.toggle() } label: { NerdIcon(name: paused ? "play.fill" : "pause.circle", size: 13) }
                    .help(paused ? "Devam et" : "Duraklat")
                Button { if let source { state.reveal(source.url) } } label: { NerdIcon(name: "folder", size: 13) }
                    .help("Finder'da göster")
                Button { clear() } label: { NerdIcon(name: "eraser", size: 13) }
                    .help("Logu temizle")
            }
            .buttonStyle(QuietButtonStyle())
        }
        .controlSize(.small)
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
    }

    private func reload() {
        guard let url = source?.url, let h = try? FileHandle(forReadingFrom: url) else { text = ""; return }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: size > 300_000 ? size - 300_000 : 0)
        let data = (try? h.readToEnd()) ?? Data()
        let new = Shell.stripANSI(String(decoding: data, as: UTF8.self))
        if new != text { text = new }
    }

    private func clear() {
        guard let url = source?.url else { return }
        try? Data().write(to: url)
        text = ""
    }

    /// 2 error, 1 warning, 0 other.
    static func severity(_ line: Substring) -> Int {
        let l = line.lowercased()
        if l.contains("error") || l.contains("fatal") || l.contains("exception") || l.contains("critical") || l.contains("fail") { return 2 }
        if l.contains("warn") || l.contains("deprecated") || l.contains("notice") { return 1 }
        return 0
    }

    static func color(_ line: Substring) -> Color {
        switch severity(line) {
        case 2: .red
        case 1: .orange
        default: .primary.opacity(0.85)
        }
    }
}
