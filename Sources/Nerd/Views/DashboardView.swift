import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var state

    private var setupItems: [(String, String, () async -> Void)] {
        var items: [(String, String, () async -> Void)] = []
        if !state.caddyInstalled {
            items.append(("Web sunucusu (Caddy) kurulu değil", "Kur", { await state.installCaddy() }))
        }
        if state.config.tld != "localhost" && !state.resolverInstalled {
            items.append((".\(state.config.tld) alan adları için DNS çözümleyici", "Kur", { await state.installResolver() }))
        }
        if !state.pathConfigured {
            items.append(("Terminal için ~/.nerd/bin PATH'e eklenmeli", "Ekle", { state.addNerdToPath() }))
        }
        if state.installedPHP.isEmpty {
            items.append(("Kurulu PHP sürümü yok", "PHP", { state.selection = .php }))
        }
        return items
    }

    var body: some View {
        Form {
            Section {
            } header: {
                HStack(spacing: 10) {
                    StatTile(icon: "server.rack", color: state.webRunning ? .green : .gray,
                             title: "Web sunucusu", value: state.webRunning ? "Çalışıyor" : "Durdu", on: state.webRunning)
                    StatTile(icon: "chevron.left.forwardslash.chevron.right", color: .indigo,
                             title: "Varsayılan PHP", value: state.defaultPHP.map { "PHP \($0.version)" } ?? "—")
                    StatTile(icon: "hexagon.fill", color: .green,
                             title: "Varsayılan Node", value: state.defaultNode?.version ?? "—")
                    StatTile(icon: "envelope.fill", color: .pink,
                             title: "Okunmamış mail", value: "\(state.unreadMailCount)")
                }
                .textCase(nil)
                .foregroundStyle(.primary)
                .padding(.bottom, 4)
            }

            Section {
                HStack {
                    IconBadge(systemName: "network", color: state.webRunning ? .green : .gray, size: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Web sunucusu")
                        Text(webDetail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if state.webRunning {
                        Button("Yeniden başlat") { Task { await state.restartWebServer() } }
                        Button("Durdur") { state.stopWebServer() }
                    } else {
                        Button("Başlat") { Task { await state.startWebServer() } }.disabled(!state.caddyInstalled)
                    }
                }
                if let err = state.webError {
                    Text(err).font(.caption.monospaced()).foregroundStyle(.red).textSelection(.enabled)
                }
            } header: {
                HStack {
                    Text("Durum")
                    Spacer()
                    Button("Caddyfile") { state.openInEditor(Paths.caddyfile) }.buttonStyle(.link)
                    Button("Loglar") { state.reveal(Paths.logs) }.buttonStyle(.link)
                }
            }

            if !setupItems.isEmpty {
                Section("Kurulum") {
                    ForEach(setupItems, id: \.0) { item in
                        HStack {
                            IconBadge(systemName: "exclamationmark", color: .orange, size: 22)
                            Text(item.0)
                            Spacer()
                            BusyButton(title: item.1, busy: state.busy.contains("caddy") && item.1 == "Kur" && !state.caddyInstalled, action: item.2)
                        }
                    }
                }
            }

            Section {
                if state.sites.isEmpty {
                    HStack {
                        Text("Henüz site yok.").foregroundStyle(.secondary)
                        Spacer()
                        Button("Yeni proje") { state.selection = .newProject }
                    }
                }
                ForEach(state.sites.prefix(8)) { site in
                    HStack(spacing: 10) {
                        SiteIcon(kind: site.kind)
                        Text(state.host(for: site))
                        if state.isDevRunning(site) { StatusDot(on: true) }
                        Spacer()
                        Text(site.kind.title).font(.caption).foregroundStyle(.secondary)
                        Button { state.openSite(site) } label: { Image(systemName: "arrow.up.right") }
                            .buttonStyle(.borderless)
                    }
                }
            } header: {
                HStack {
                    Text("Siteler · \(state.sites.count)")
                    Spacer()
                    Button("Tümü") { state.selection = .sites }.buttonStyle(.link)
                }
            }

            if !state.installedServices.isEmpty {
                Section("Servisler") {
                    ForEach(state.installedServices) { def in
                        let running = state.services[def.formula]?.isRunning ?? false
                        Toggle(isOn: Binding(get: { running }, set: { _ in Task { await state.toggleService(def) } })) {
                            HStack(spacing: 10) {
                                IconBadge(systemName: def.icon, color: def.color, size: 22)
                                Text(def.name)
                                if let port = def.port { Text(":\(String(port))").foregroundStyle(.tertiary) }
                            }
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(state.busy.contains(def.formula))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Genel Bakış")
    }

    private var webDetail: String {
        var parts = ["Caddy", ".\(state.config.tld)"]
        if state.config.tld != "localhost" { parts.append("DNS :\(String(state.config.dnsPort))") }
        let fpm = state.neededPHP.filter { state.isFPMRunning($0) }.map { "FPM \($0.version)" }
        return (parts + fpm).joined(separator: " · ")
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
