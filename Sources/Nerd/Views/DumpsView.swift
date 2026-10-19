import SwiftUI
import WebKit

/// Live feed of dump() / dd() calls from the sites, grouped by request.
struct DumpsView: View {
    @Environment(AppState.self) private var state
    @State private var filter = ""
    @State private var site: String?

    private var siteNames: [String] {
        var seen = Set<String>()
        return state.dumps.compactMap { state.siteName(for: $0) }.filter { seen.insert($0).inserted }.sorted()
    }

    private var entries: [DumpEntry] {
        state.dumps.filter { d in
            (site == nil || state.siteName(for: d) == site)
                && (filter.isEmpty || d.text.localizedCaseInsensitiveContains(filter)
                    || (d.file ?? "").localizedCaseInsensitiveContains(filter)
                    || (d.uri ?? d.command ?? "").localizedCaseInsensitiveContains(filter))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Group {
                if state.dumps.isEmpty {
                    ContentUnavailableView {
                        Label { Text("Henüz dump yok") } icon: { NerdIcon(name: "ladybug", size: 34) }
                    } description: {
                        Text("Sitelerinizde dump() ya da dd() çağırdığınızda çıktı burada anında görünür. symfony/var-dumper kullanan her proje (Laravel, Symfony…) desteklenir.")
                    }
                } else {
                    DumpFeed(entries: entries, siteName: { state.siteName(for: $0) }) { url, line in
                        state.openInEditor(url, line: line)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
            .padding([.horizontal, .bottom], 14)
        }
    }

    private var toolbar: some View {
        @Bindable var state = state
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Dumps").font(.system(size: 17, weight: .semibold))
                HStack(spacing: 5) {
                    StatusDot(on: state.dumpsRunning && !state.dumpsPaused)
                    Text(state.dumpsRunning
                         ? (state.dumpsPaused ? String(localized: "Duraklatıldı") : "127.0.0.1:\(String(state.config.dumpPort))")
                         : String(localized: "Dinleyici başlatılamadı"))
                    Text(verbatim: "·")
                    Text("\(state.dumps.count) dump")
                }
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if siteNames.count > 1 {
                Picker("", selection: $site) {
                    Text("Tüm siteler").tag(String?.none)
                    ForEach(siteNames, id: \.self) { Text(verbatim: $0).tag(String?.some($0)) }
                }
                .labelsHidden().fixedSize()
            }
            TextField("Filtrele", text: $filter)
                .textFieldStyle(.roundedBorder).frame(width: 160)
            Group {
                Button { state.dumpsPaused.toggle() } label: { NerdIcon(name: state.dumpsPaused ? "play.fill" : "pause.circle", size: 13) }
                    .help(state.dumpsPaused ? "Devam et" : "Duraklat")
                Menu {
                    Toggle("Dump'ları sayfada da göster", isOn: Binding(
                        get: { state.config.dumpsInBrowser },
                        set: { state.config.dumpsInBrowser = $0; state.writeDumpHook() }))
                    Toggle("Artisan, Tinker ve test dump'larını da yakala", isOn: Binding(
                        get: { state.config.dumpsCLI },
                        set: { state.config.dumpsCLI = $0; state.writeDumpHook() }))
                } label: { NerdIcon(name: "ellipsis", size: 13) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Seçenekler")
                Button { state.dumps.removeAll() } label: { NerdIcon(name: "eraser", size: 13) }
                    .help("Temizle")
                    .disabled(state.dumps.isEmpty)
            }
            .buttonStyle(QuietButtonStyle())
        }
        .controlSize(.small)
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
    }
}

/// One web view for the whole feed: new dumps are appended with JavaScript so
/// expanded nodes and the scroll position survive, and Symfony's own dump
/// script (folding, search) keeps working.
struct DumpFeed: NSViewRepresentable {
    let entries: [DumpEntry]            // newest first
    let siteName: (DumpEntry) -> String?
    let open: (URL, Int?) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        view.loadHTMLString(Self.page, baseURL: nil)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        let c = context.coordinator
        c.open = open
        let chronological = Array(entries.reversed())
        let ids = chronological.map(\.id)
        var script = ""
        var start = c.rendered.count
        if !ids.starts(with: c.rendered) {
            script += "nerdReset();"
            start = 0
        }
        guard start < ids.count || script != "" else { return }
        for e in chronological[start...] {
            script += "nerdAdd(\(Self.json(item(e))));"
        }
        c.rendered = ids
        c.run(script, in: view)
    }

    func makeCoordinator() -> Coordinator { Coordinator(open: open) }

    private func item(_ e: DumpEntry) -> [String: String] {
        let source: String
        if let file = e.file {
            let shown = e.root.flatMap { root in file.hasPrefix(root + "/") ? String(file.dropFirst(root.count + 1)) : nil } ?? file
            var c = URLComponents()
            c.scheme = "nerd-open"
            c.path = file
            if let line = e.line { c.queryItems = [URLQueryItem(name: "line", value: String(line))] }
            source = "<a href=\"\(Self.escape(c.url?.absoluteString ?? ""))\" title=\"\(Self.escape(file))\">\(Self.escape(shown))\(e.line.map { ":\($0)" } ?? "")</a>"
        } else {
            source = ""
        }
        let time = e.date.formatted(.dateTime.hour().minute().second())
        let target = e.command ?? [e.method, e.uri].compactMap { $0 }.joined(separator: " ")
        let header = "<b>\(Self.escape(siteName(e) ?? "PHP"))</b><span class=target>\(Self.escape(target))</span><span>\(Self.escape(time))</span>"
        let meta = "\(source)<span>\(e.kind == "dd" ? "<i>dd</i>" : "")\(Self.escape(time))</span>"
        return ["request": e.request, "header": header, "meta": meta, "html": e.html]
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func json(_ object: [String: String]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var open: (URL, Int?) -> Void
        var rendered: [String] = []
        private var ready = false
        private var pending = ""

        init(open: @escaping (URL, Int?) -> Void) { self.open = open }

        func run(_ script: String, in view: WKWebView) {
            guard ready else { pending += script; return }
            evaluate(script, in: view)
        }

        private func evaluate(_ script: String, in view: WKWebView) {
            view.evaluateJavaScript(script) { _, error in
                if let error { NSLog("Nerd dumps feed: %@", String(describing: error)) }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            if !pending.isEmpty { evaluate(pending, in: webView); pending = "" }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard action.navigationType == .linkActivated, let url = action.request.url else {
                return decisionHandler(.allow)
            }
            if url.scheme == "nerd-open", let c = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                open(URL(fileURLWithPath: c.path), c.queryItems?.first { $0.name == "line" }?.value.flatMap(Int.init))
            } else {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        }
    }

    private static let page = """
    <!doctype html><html><head><meta charset="utf-8"><style>
    :root { color-scheme: light dark; --muted: #6e6e73; --line: rgba(0,0,0,.09); --card: rgba(255,255,255,.9); }
    @media (prefers-color-scheme: dark) { :root { --muted: #98989d; --line: rgba(255,255,255,.1); --card: rgba(255,255,255,.04); } }
    body { margin: 0; padding: 14px; font: 12px -apple-system, sans-serif; background: transparent; }
    section { margin-bottom: 18px; }
    section > header { display: flex; gap: 8px; align-items: baseline; color: var(--muted); padding: 0 2px 6px; }
    section > header b { color: CanvasText; font-weight: 600; font-size: 12.5px; }
    section > header .target { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-family: ui-monospace, Menlo, monospace; font-size: 11px; }
    .dump { border: 1px solid var(--line); border-radius: 9px; margin-bottom: 8px; overflow: hidden; background: var(--card); }
    .dump .meta { display: flex; justify-content: space-between; gap: 10px; padding: 5px 10px; color: var(--muted); font-size: 11px; }
    .dump .meta a { color: inherit; text-decoration: none; font-family: ui-monospace, Menlo, monospace; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .dump .meta a:hover { color: CanvasText; text-decoration: underline; }
    .dump .meta i { font-style: normal; font-weight: 600; color: #fff; background: #e5484d; border-radius: 4px; padding: 0 5px; margin-right: 6px; }
    .dump pre.sf-dump { margin: 0 !important; border-radius: 0 !important; }
    </style></head><body><div id="feed"></div><script>
    const feed = document.getElementById('feed');
    function nerdReset() { feed.innerHTML = ''; }
    function nerdAdd(d) {
        let group = document.getElementById('r-' + d.request);
        if (!group) {
            group = document.createElement('section');
            group.id = 'r-' + d.request;
            group.innerHTML = '<header>' + d.header + '</header><div class="items"></div>';
        }
        feed.prepend(group);
        const item = document.createElement('div');
        item.className = 'dump';
        item.innerHTML = '<div class="meta">' + d.meta + '</div>';
        // A contextual fragment runs the <script> tags Symfony's dumper emits
        item.appendChild(document.createRange().createContextualFragment(d.html));
        group.querySelector('.items').appendChild(item);
    }
    </script></body></html>
    """
}
