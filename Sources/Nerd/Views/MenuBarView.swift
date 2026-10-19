import SwiftUI
import AppKit

struct MenuBarView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let version = Updater.shared.readyVersion {
                Button { Updater.shared.installAndRelaunch() } label: {
                    HStack(spacing: 8) {
                        Glyph(systemName: "arrow.down.circle", color: .accentColor)
                        Text("Nerd \(version) hazır")
                        Spacer()
                        Text("Yeniden başlat").foregroundStyle(Color.accentColor)
                    }
                    .font(.callout)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.08))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if let err = state.webError {
                Text(err).font(.caption).foregroundStyle(.red).lineLimit(3)
                    .padding(.horizontal, 12).padding(.bottom, 8)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    sitesSection
                    if !state.installedServices.isEmpty { servicesSection }
                }
                .padding(.vertical, 10)
            }
            .frame(maxHeight: 420)
            Divider()
            versions.padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            footer
        }
        .frame(width: 320)
        .tint(.brand)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Tile(systemName: "cube.fill", size: 26, emphasized: true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Nerd").font(.system(size: 13, weight: .semibold))
                HStack(spacing: 5) {
                    StatusDot(on: state.webRunning)
                    Text(state.webRunning ? "Çalışıyor" : "Durdu").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if state.caddyInstalled {
                Button { Task { await state.restartWebServer() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Yeniden başlat")
                Button {
                    Task { if state.webRunning { state.stopWebServer() } else { await state.startWebServer() } }
                } label: {
                    Image(systemName: "power").foregroundStyle(state.webRunning ? .green : .secondary)
                }
                .help(state.webRunning ? "Durdur" : "Başlat")
            } else {
                Button("Caddy kur") { Task { await state.installCaddy() } }.controlSize(.small)
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private func sectionTitle(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary).padding(.horizontal, 12)
    }

    private var sitesSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionTitle("SİTELER")
            if state.sites.isEmpty {
                Button("İlk projeni oluştur") { openMain(.newProject) }
                    .buttonStyle(.link).font(.callout).padding(.horizontal, 12).padding(.top, 4)
            }
            ForEach(state.sites.prefix(10)) { site in
                MenuSiteRow(site: site) { openMain(.sites, site: site.name) }
            }
            if state.sites.count > 10 {
                Button("Tümü (\(state.sites.count))") { openMain(.sites) }
                    .buttonStyle(.link).font(.caption).padding(.horizontal, 12)
            }
        }
    }

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle("SERVİSLER")
            ForEach(state.installedServices) { def in
                let running = state.services[def.formula]?.isRunning ?? false
                HStack(spacing: 8) {
                    Tile(systemName: def.icon, size: 16)
                    Text(def.name)
                    Spacer()
                    if state.busy.contains(def.formula) { ProgressView().controlSize(.mini) }
                    Toggle("", isOn: Binding(get: { running }, set: { _ in Task { await state.toggleService(def) } }))
                        .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                        .disabled(state.busy.contains(def.formula))
                }
                .font(.callout)
                .padding(.horizontal, 12)
            }
        }
    }

    private var versions: some View {
        HStack(spacing: 10) {
            Picker(selection: Binding(
                get: { state.defaultPHP?.version ?? "" },
                set: { v in if let p = state.phpVersion(v) { state.setDefaultPHP(p) } })) {
                ForEach(state.installedPHP) { Text("PHP \($0.version)").tag($0.version) }
                if state.installedPHP.isEmpty { Text("PHP yok").tag("") }
            } label: { EmptyView() }
            Picker(selection: Binding(
                get: { state.defaultNode?.version ?? "" },
                set: { v in if let n = state.nodeVersion(v) { state.setDefaultNode(n) } })) {
                ForEach(state.nodeVersions) { Text("Node \($0.version)").tag($0.version) }
                if state.nodeVersions.isEmpty { Text("Node yok").tag("") }
            } label: { EmptyView() }
        }
        .labelsHidden()
        .controlSize(.small)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button { openMain(.newProject) } label: { Label("Yeni proje", systemImage: "plus") }
            Spacer()
            Button { openMain(.mail) } label: {
                Image(systemName: state.unreadMailCount > 0 ? "envelope.badge" : "envelope")
                    .symbolRenderingMode(.multicolor)
            }
            .help(state.unreadMailCount > 0 ? "\(state.unreadMailCount) okunmamış e-posta" : "Mail")
            Button { openMain(.database) } label: { Image(systemName: "tablecells") }.help("Veritabanı")
            Button { openMain(.dashboard) } label: { Image(systemName: "macwindow") }.help("Nerd'i aç")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power.circle") }.help("Çıkış")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12).padding(.vertical, 9)
    }

    private func openMain(_ item: SidebarItem, site: String? = nil) {
        state.selection = item
        if let site { state.selectedSiteID = site }
        openWindow(id: "main")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct MenuSiteRow: View {
    @Environment(AppState.self) private var state
    let site: Site
    let details: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            SiteIcon(kind: site.kind, size: 16)
            Text(state.host(for: site)).lineLimit(1)
            if site.config.secure { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary) }
            if state.isDevRunning(site) { StatusDot(on: true).help("Dev sunucusu çalışıyor") }
            Spacer()
            if hover {
                Group {
                    Button { state.openInEditor(site.path) } label: { Image(systemName: "chevron.left.forwardslash.chevron.right") }.help("Editör")
                    Button { state.openInTerminal(site.path) } label: { Image(systemName: "terminal") }.help("Terminal")
                    Menu {
                        Button("Finder'da göster") { state.reveal(site.path) }
                        if site.hasPackageJSON {
                            Button(state.isDevRunning(site) ? "Dev sunucusunu durdur" : "Dev sunucusunu başlat") { state.toggleDev(site) }
                        }
                        Divider()
                        Button("Ayrıntılar…", action: details)
                    } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            } else if site.kind.isProxied {
                Text(site.kind.title).font(.caption).foregroundStyle(.tertiary)
            } else if let php = state.php(for: site) {
                Text(php.version).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(hover ? Color.primary.opacity(0.06) : .clear)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { state.openSite(site) }
    }
}
