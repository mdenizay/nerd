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
            Header(title: "Genel Bakış", icon: "square.grid.2x2", color: .blue) {
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
                        ListCard {
                            ForEach(setupItems, id: \.text) { item in
                                Row {
                                    TintIcon(systemName: "exclamationmark", color: .orange, size: 18)
                                    Text(item.text)
                                    Spacer()
                                    BusyButton(title: "\(item.button)", busy: item.busy, action: item.action)
                                        .controlSize(.small)
                                }
                            }
                        }
                    }

                    SectionLabel(text: "Siteler · \(state.sites.count)") {
                        Button("Tümü") { state.selection = .sites }
                    }
                    ListCard {
                        if state.sites.isEmpty {
                            Row {
                                Text("Henüz site yok.").foregroundStyle(.secondary)
                                Spacer()
                                Button("Yeni proje") { state.selection = .newProject }.controlSize(.small)
                            }
                        }
                        ForEach(state.sites.prefix(10)) { site in
                            Row(action: { state.openSite(site) }) {
                                SiteIcon(kind: site.kind, size: 18)
                                Text(state.host(for: site))
                                if state.isDevRunning(site) { Chip(text: "Dev", color: .green) }
                                Spacer()
                                Pill(text: "\(site.kind.title)", color: site.kind.badgeColor)
                                Glyph(systemName: "arrow.up.right", size: 10)
                            }
                        }
                    }

                    if !state.installedServices.isEmpty {
                        SectionLabel(text: "Servisler") {
                            Button("Tümü") { state.selection = .services }
                        }
                        ListCard {
                        ForEach(state.installedServices) { def in
                            let running = state.services[def.formula]?.isRunning ?? false
                            Row {
                                TintIcon(systemName: def.icon, color: def.color, size: 18)
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
                }
                .padding(.bottom, 16)
            }
        }
    }

    /// Coloured facts: web server, default PHP / Node, unread mail.
    private var statusStrip: some View {
        HStack(spacing: 6) {
            Chip(text: state.webRunning ? "Çalışıyor" : "Durdu", color: state.webRunning ? .green : .secondary,
                 systemImage: state.webRunning ? "circle.fill" : "circle")
            Chip(text: "Caddy · .\(state.config.tld)", color: .teal, systemImage: "network")
            Chip(text: "\(state.defaultPHP.map { "PHP \($0.version)" } ?? "PHP —")", color: .indigo,
                 systemImage: "chevron.left.forwardslash.chevron.right")
            Chip(text: "\("Node " + (state.defaultNode?.version ?? "—"))", color: .green, systemImage: "hexagon.fill")
            Button { state.selection = .mail } label: {
                Chip(text: "\(state.unreadMailCount)", color: .pink,
                     systemImage: state.unreadMailCount > 0 ? "envelope.badge.fill" : "envelope.fill")
            }
            .buttonStyle(.plain)
            .help("Okunmamış mail")
            Spacer()
        }
        .padding(.horizontal, Metrics.inset)
        .padding(.top, 14)
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
