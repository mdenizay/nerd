import SwiftUI

/// Overview in the Herd / System Settings idiom: a native grouped form.
struct DashboardView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

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
        if state.composerPath == nil {
            items.append(SetupItem(text: String(localized: "Composer kurulu değil"), button: String(localized: "Kur"),
                                   busy: state.busy.contains("composer")) { await state.installComposer() })
        }
        if state.installedPHP.isEmpty {
            items.append(SetupItem(text: String(localized: "Kurulu PHP sürümü yok"), button: "PHP", busy: false) { state.selection = .php })
        }
        return items
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Nerd").font(.system(size: 18, weight: .semibold))
                        HStack(spacing: 5) {
                            StatusDot(on: state.webRunning)
                            Text(state.webRunning ? "Çalışıyor" : "Durdu")
                            Text(verbatim: "· Caddy · .\(state.config.tld)").foregroundStyle(.secondary)
                        }
                        .font(.system(size: 12))
                        Text(verbatim: "PHP \(state.defaultPHP?.version ?? "—")  ·  Node \(state.defaultNode?.version ?? "—")"
                             + (state.defaultDotnet.map { "  ·  .NET \($0.major)" } ?? ""))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if state.webRunning {
                        Button("Yeniden başlat") { Task { await state.restartWebServer() } }
                        Button("Durdur") { state.stopWebServer() }
                    } else {
                        Button("Başlat") { Task { await state.startWebServer() } }
                            .primaryButton()
                            .disabled(!state.caddyInstalled)
                    }
                }
                .padding(.vertical, 4)
                if let err = state.webError {
                    Text(err).font(.system(size: 11, design: .monospaced)).foregroundStyle(.red).textSelection(.enabled)
                }
            }

            Section {
                HStack(spacing: 10) {
                    action("plus", "Yeni proje", .purple) { state.selection = .newProject }
                    action("globe", "Siteler", .blue) { state.selection = .sites }
                    action("cylinder.split.1x2", "Veritabanı", .teal) { state.selection = .database }
                    action("envelope", "Mail", .pink) { state.selection = .mail }
                    action("ladybug", "Debug", .orange) { openWindow(id: "debug") }
                }
                .padding(.vertical, 2)
            }

            if !setupItems.isEmpty {
                Section("Kurulum") {
                    ForEach(setupItems, id: \.text) { item in
                        LabeledContent {
                            BusyButton(title: "\(item.button)", busy: item.busy, action: item.action)
                        } label: {
                            Label { Text(item.text) } icon: { SettingsIcon(name: "exclamationmark", color: .orange) }
                        }
                    }
                }
            }

            Section {
                if state.sites.isEmpty {
                    LabeledContent("Henüz site yok.") {
                        Button("Yeni proje") { state.selection = .newProject }
                    }
                }
                ForEach(state.sites.prefix(6)) { site in
                    LabeledContent {
                        HStack(spacing: 8) {
                            if state.isDevRunning(site) { StatusDot(on: true) }
                            Text(site.kind.title).foregroundStyle(.secondary)
                            Button { state.openSite(site) } label: { NerdIcon(name: "arrow.up.right", size: 12) }
                                .buttonStyle(.borderless)
                                .help("Tarayıcıda aç")
                        }
                    } label: {
                        Label { Text(state.host(for: site)) } icon: { SiteIcon(kind: site.kind, size: 22) }
                    }
                }
            } header: {
                HStack {
                    Text("Siteler")
                    Spacer()
                    Button("Tümü") { state.selection = .sites }.buttonStyle(.link).font(.system(size: 11))
                }
            }

            if !state.installedServices.isEmpty {
                Section {
                    ForEach(state.installedServices) { def in
                        let running = state.services[def.formula]?.isRunning ?? false
                        Toggle(isOn: Binding(get: { running }, set: { _ in Task { await state.toggleService(def) } })) {
                            Label {
                                HStack(spacing: 6) {
                                    Text(def.name)
                                    if let port = def.port { Text(verbatim: ":\(port)").foregroundStyle(.tertiary) }
                                }
                            } icon: {
                                Tile(systemName: def.icon, brand: def.brand, size: 22)
                            }
                        }
                        .toggleStyle(.switch)
                        .disabled(state.busy.contains(def.formula))
                    }
                } header: {
                    HStack {
                        Text("Servisler")
                        Spacer()
                        Button("Tümü") { state.selection = .services }.buttonStyle(.link).font(.system(size: 11))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem {
                Button { state.reveal(Paths.logs) } label: { Label("Loglar", systemImage: "doc.text.magnifyingglass") }
            }
            ToolbarItem {
                Button { state.openInEditor(Paths.caddyfile) } label: { Label("Caddyfile", systemImage: "doc.badge.gearshape") }
            }
        }
    }

    private func action(_ icon: String, _ title: LocalizedStringKey, _ color: Color, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 6) {
                SettingsIcon(name: icon, color: color, size: 28)
                Text(title).font(.system(size: 11)).foregroundStyle(.primary).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
