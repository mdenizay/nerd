import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var state

    private struct SetupItem {
        let text: String
        let button: String
        let busy: Bool
        let action: () async -> Void
    }

    private var setupItems: [SetupItem] {
        var items: [SetupItem] = []
        if !state.caddyInstalled {
            items.append(SetupItem(text: String(localized: "Web sunucusu (Caddy) kurulu değil"), button: String(localized: "Kur"),
                                   busy: state.busy.contains("caddy")) { await state.installCaddy() })
        }
        if state.config.tld != "localhost" && !state.resolverInstalled {
            items.append(SetupItem(text: String(localized: ".\(state.config.tld) alan adları için DNS çözümleyici"), button: String(localized: "Kur"),
                                   busy: false) { await state.installResolver() })
        }
        if !state.pathConfigured {
            items.append(SetupItem(text: String(localized: "Terminal için ~/.nerd/bin PATH'e eklenmeli"), button: String(localized: "Ekle"),
                                   busy: false) { state.addNerdToPath() })
        }
        if state.installedPHP.isEmpty {
            items.append(SetupItem(text: String(localized: "Kurulu PHP sürümü yok"), button: "PHP", busy: false) { state.selection = .php })
        }
        return items
    }

    var body: some View {
        VStack(spacing: 0) {
            Header(title: "Genel Bakış") {
                if state.webRunning {
                    Button { Task { await state.restartWebServer() } } label: { Image(systemName: "arrow.clockwise") }
                        .help("Yeniden başlat")
                    Button("Durdur") { state.stopWebServer() }
                } else {
                    Button("Başlat") { Task { await state.startWebServer() } }.disabled(!state.caddyInstalled)
                }
                MoreMenu {
                    Button("Caddyfile") { state.openInEditor(Paths.caddyfile) }
                    Button("Loglar") { state.reveal(Paths.logs) }
                }
            }
            ScrollView {
                VStack(spacing: 0) {
                    statusStrip
                    if let err = state.webError {
                        Text(err)
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.red)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Metrics.inset).padding(.bottom, 8)
                    }

                    if !setupItems.isEmpty {
                        SectionLabel("Kurulum")
                        ForEach(setupItems, id: \.text) { item in
                            Row {
                                Glyph(systemName: "exclamationmark.circle", color: .orange)
                                Text(item.text)
                                Spacer()
                                BusyButton(title: "\(item.button)", busy: item.busy, action: item.action)
                                    .controlSize(.small)
                            }
                        }
                    }

                    SectionLabel(text: "Siteler · \(state.sites.count)") {
                        Button("Tümü") { state.selection = .sites }
                    }
                    if state.sites.isEmpty {
                        Row {
                            Text("Henüz site yok.").foregroundStyle(.secondary)
                            Spacer()
                            Button("Yeni proje") { state.selection = .newProject }.controlSize(.small)
                        }
                    }
                    ForEach(state.sites.prefix(10)) { site in
                        Row(action: { state.openSite(site) }) {
                            SiteIcon(kind: site.kind)
                            Text(state.host(for: site))
                            if state.isDevRunning(site) { StatusDot(on: true) }
                            Spacer()
                            Detail(text: site.kind.title)
                            Glyph(systemName: "arrow.up.right", size: 10)
                        }
                    }

                    if !state.installedServices.isEmpty {
                        SectionLabel(text: "Servisler") {
                            Button("Tümü") { state.selection = .services }
                        }
                        ForEach(state.installedServices) { def in
                            let running = state.services[def.formula]?.isRunning ?? false
                            Row {
                                StatusDot(on: running)
                                Text(def.name)
                                if let port = def.port { Detail(text: ":\(port)") }
                                Spacer()
                                if state.busy.contains(def.formula) { ProgressView().controlSize(.mini) }
                                Toggle("", isOn: Binding(get: { running }, set: { _ in Task { await state.toggleService(def) } }))
                                    .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                                    .disabled(state.busy.contains(def.formula))
                            }
                        }
                    }
                }
                .padding(.bottom, 16)
            }
        }
    }

    /// One line: web server, default PHP / Node, unread mail.
    private var statusStrip: some View {
        HStack(spacing: 18) {
            HStack(spacing: 6) {
                StatusDot(on: state.webRunning)
                Text(state.webRunning ? "Çalışıyor" : "Durdu")
                Detail(text: "Caddy · .\(state.config.tld)")
            }
            HStack(spacing: 4) {
                Glyph(systemName: "chevron.left.forwardslash.chevron.right", size: 10)
                Text(verbatim: state.defaultPHP.map { "PHP \($0.version)" } ?? "PHP —")
            }
            HStack(spacing: 4) {
                Glyph(systemName: "hexagon", size: 10)
                Text(verbatim: "Node \(state.defaultNode?.version ?? "—")")
            }
            Button { state.selection = .mail } label: {
                HStack(spacing: 4) {
                    Glyph(systemName: state.unreadMailCount > 0 ? "envelope.badge" : "envelope", size: 10)
                    Text(verbatim: "\(state.unreadMailCount)")
                }
            }
            .buttonStyle(.plain)
            .help("Okunmamış mail")
            Spacer()
        }
        .font(.system(size: 12))
        .padding(.horizontal, Metrics.inset)
        .padding(.vertical, 12)
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
