import SwiftUI
import AppKit

struct MenuBarView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let err = state.webError {
                        Text(err).font(.caption).foregroundStyle(.red).lineLimit(4)
                    }
                    sitesSection
                    servicesSection
                    versionsSection
                }
                .padding(12)
            }
            .frame(maxHeight: 460)
            Divider()
            footer
        }
        .frame(width: 360)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "server.rack").font(.title2).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Nerd").font(.headline)
                HStack(spacing: 5) {
                    StatusDot(on: state.webRunning)
                    Text(state.webRunning ? "Web sunucusu çalışıyor" : "Web sunucusu durdu")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if state.caddyInstalled {
                Button {
                    Task {
                        if state.webRunning { state.stopWebServer() } else { await state.startWebServer() }
                    }
                } label: {
                    Image(systemName: "power").font(.title3)
                        .foregroundStyle(state.webRunning ? .green : .secondary)
                }
                .buttonStyle(.borderless)
                .help(state.webRunning ? "Durdur" : "Başlat")
                Button {
                    Task { await state.restartWebServer() }
                } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Yeniden başlat")
            } else {
                Button("Caddy kur") { Task { await state.installCaddy() } }
                    .controlSize(.small)
            }
        }
        .padding(12)
    }

    private var sitesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("SİTELER").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { state.scanSites(); Task { await state.reloadWebServer() } } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }.buttonStyle(.borderless).font(.caption)
            }
            if state.sites.isEmpty {
                Text("Park klasöründe site yok.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(state.sites.prefix(12)) { site in
                HStack(spacing: 6) {
                    Image(systemName: site.isLaravel ? "leaf.fill" : "folder.fill")
                        .foregroundStyle(site.isLaravel ? .red : .secondary)
                        .frame(width: 16)
                    Button(state.host(for: site)) { state.open(state.url(for: site)) }
                        .buttonStyle(.plain)
                        .lineLimit(1)
                    if site.config.secure { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.green) }
                    Spacer()
                    if let php = state.php(for: site) { Pill(text: php.version, color: .indigo) }
                    Menu {
                        Button("Tarayıcıda aç") { state.open(state.url(for: site)) }
                        Button("Editörde aç") { state.openInEditor(site.path) }
                        Button("Finder'da göster") { state.reveal(site.path) }
                        Button("Terminal") { state.openInTerminal(site.path) }
                        if site.hasPackageJSON {
                            Button(state.isViteRunning(site) ? "Vite'i durdur" : "npm run dev") { state.toggleVite(site) }
                        }
                        Divider()
                        Button("Detaylar…") { openMain(.sites, site: site.name) }
                    } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                }
                .font(.callout)
            }
            if state.sites.count > 12 {
                Button("Tümünü göster (\(state.sites.count))") { openMain(.sites) }
                    .buttonStyle(.link).font(.caption)
            }
        }
    }

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SERVİSLER").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if state.installedServices.isEmpty {
                Button("Servis kur…") { openMain(.services) }.buttonStyle(.link).font(.caption)
            }
            ForEach(state.installedServices) { def in
                let running = state.services[def.formula]?.isRunning ?? false
                HStack {
                    Image(systemName: def.icon).frame(width: 16).foregroundStyle(.secondary)
                    Text(def.name)
                    if let port = def.port { Text(":\(port)").font(.caption).foregroundStyle(.tertiary) }
                    Spacer()
                    if state.busy.contains(def.formula) { ProgressView().controlSize(.mini) }
                    Toggle("", isOn: Binding(get: { running }, set: { _ in Task { await state.toggleService(def) } }))
                        .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                        .disabled(state.busy.contains(def.formula))
                }
                .font(.callout)
            }
        }
    }

    private var versionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("VARSAYILANLAR").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack {
                Label("PHP", systemImage: "chevron.left.forwardslash.chevron.right").frame(width: 70, alignment: .leading)
                Picker("", selection: Binding(
                    get: { state.defaultPHP?.version ?? "" },
                    set: { v in if let p = state.phpVersion(v) { state.setDefaultPHP(p) } })) {
                    ForEach(state.installedPHP) { Text("PHP \($0.version)").tag($0.version) }
                    if state.installedPHP.isEmpty { Text("Kurulu değil").tag("") }
                }
                .labelsHidden()
            }
            HStack {
                Label("Node", systemImage: "hexagon").frame(width: 70, alignment: .leading)
                Picker("", selection: Binding(
                    get: { state.defaultNode?.version ?? "" },
                    set: { v in if let n = state.nodeVersion(v) { state.setDefaultNode(n) } })) {
                    ForEach(state.nodeVersions) { Text($0.label).tag($0.version) }
                    if state.nodeVersions.isEmpty { Text("Kurulu değil").tag("") }
                }
                .labelsHidden()
            }
        }
        .font(.callout)
    }

    private var footer: some View {
        HStack {
            Button { openMain(.newProject) } label: { Label("Yeni Proje", systemImage: "plus") }
            Button { openMain(.database) } label: { Label("DB", systemImage: "tablecells") }
            Spacer()
            Button { openMain(.dashboard) } label: { Label("Yönet", systemImage: "macwindow") }
            Button { NSApp.terminate(nil) } label: { Image(systemName: "xmark.circle") }
                .help("Çıkış")
        }
        .buttonStyle(.borderless)
        .padding(10)
    }

    private func openMain(_ item: SidebarItem, site: String? = nil) {
        state.selection = item
        if let site { state.selectedSiteID = site }
        openWindow(id: "main")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
