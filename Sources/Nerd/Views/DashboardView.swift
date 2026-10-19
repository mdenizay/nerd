import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Genel Bakış", subtitle: "Yerel PHP geliştirme ortamınız")
                setupWarnings
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14, alignment: .top)], spacing: 14) {
                    webCard
                    versionsCard
                    servicesCard
                    sitesCard
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private var setupWarnings: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !state.caddyInstalled {
                warning("Web sunucusu (Caddy) kurulu değil.", "Caddy'yi kur", busy: state.busy.contains("caddy")) {
                    await state.installCaddy()
                }
            }
            if state.config.tld != "localhost" && !state.resolverInstalled {
                warning(".\(state.config.tld) alan adları için DNS çözümleyici kurulmadı (tek seferlik, yönetici şifresi ister).", "Kur", busy: false) {
                    await state.installResolver()
                }
            }
            if !state.pathConfigured {
                warning("~/.nerd/bin PATH'e eklenmemiş; terminalde php/node varsayılanları kullanılamaz.", "~/.zshrc'ye ekle", busy: false) {
                    state.addNerdToPath()
                }
            }
            if state.installedPHP.isEmpty {
                warning("Kurulu PHP sürümü yok.", "PHP sekmesine git", busy: false) { state.selection = .php }
            }
        }
    }

    private func warning(_ text: String, _ button: String, busy: Bool, action: @escaping () async -> Void) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text)
            Spacer()
            BusyButton(title: button, busy: busy, action: action)
        }
        .padding(10)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private var webCard: some View {
        Card(title: "Web Sunucusu", icon: "network") {
            HStack {
                StatusDot(on: state.webRunning)
                Text(state.webRunning ? "Caddy çalışıyor" : "Durdu")
                Spacer()
                Pill(text: ".\(state.config.tld)", color: .blue)
            }
            HStack {
                StatusDot(on: state.dnsRunning || state.config.tld == "localhost")
                Text(state.config.tld == "localhost" ? "DNS gerekmiyor (.localhost)" : "DNS 127.0.0.1:\(String(state.config.dnsPort))")
                    .foregroundStyle(.secondary)
            }
            ForEach(state.neededPHP) { v in
                HStack {
                    StatusDot(on: state.isFPMRunning(v))
                    Text("PHP-FPM \(v.version)").foregroundStyle(.secondary)
                }
            }
            if let err = state.webError {
                Text(err).font(.caption.monospaced()).foregroundStyle(.red).textSelection(.enabled)
            }
            HStack {
                if state.webRunning {
                    Button("Durdur") { state.stopWebServer() }
                    Button("Yeniden başlat") { Task { await state.restartWebServer() } }
                } else {
                    Button("Başlat") { Task { await state.startWebServer() } }.disabled(!state.caddyInstalled)
                }
                Spacer()
                Button("Caddyfile") { state.openInEditor(Paths.caddyfile) }.buttonStyle(.link)
                Button("Loglar") { state.reveal(Paths.logs) }.buttonStyle(.link)
            }
        }
    }

    private var versionsCard: some View {
        Card(title: "Sürümler", icon: "square.stack.3d.up") {
            LabeledContent("Varsayılan PHP", value: state.defaultPHP.map { "PHP \($0.version)" } ?? "—")
            LabeledContent("Kurulu PHP", value: state.installedPHP.map(\.version).joined(separator: ", ").ifEmpty("—"))
            LabeledContent("Varsayılan Node", value: state.defaultNode?.version ?? "—")
            LabeledContent("Kurulu Node", value: "\(state.nodeVersions.count)")
            HStack {
                Button("PHP") { state.selection = .php }
                Button("Node") { state.selection = .node }
            }
        }
    }

    private var servicesCard: some View {
        Card(title: "Servisler", icon: "server.rack") {
            if state.installedServices.isEmpty {
                Text("Kurulu servis yok.").foregroundStyle(.secondary)
            }
            ForEach(state.installedServices) { def in
                HStack {
                    StatusDot(on: state.services[def.formula]?.isRunning ?? false)
                    Text(def.name)
                    Spacer()
                    Button((state.services[def.formula]?.isRunning ?? false) ? "Durdur" : "Başlat") {
                        Task { await state.toggleService(def) }
                    }
                    .controlSize(.small)
                    .disabled(state.busy.contains(def.formula))
                }
            }
            Button("Tüm servisler") { state.selection = .services }.buttonStyle(.link)
        }
    }

    private var sitesCard: some View {
        Card(title: "Siteler", icon: "globe") {
            Text("\(state.sites.count) site · \(state.sites.filter(\.isLaravel).count) Laravel").foregroundStyle(.secondary)
            ForEach(state.sites.prefix(6)) { site in
                Button { state.open(state.url(for: site)) } label: {
                    HStack {
                        Image(systemName: site.isLaravel ? "leaf.fill" : "folder")
                        Text(state.host(for: site))
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }
                }
                .buttonStyle(.plain)
            }
            HStack {
                Button("Yeni proje") { state.selection = .newProject }.buttonStyle(.borderedProminent)
                Button("Siteler") { state.selection = .sites }
            }
        }
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
