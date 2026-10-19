import SwiftUI
import AppKit

/// The menu bar panel: status, quick actions, sites, services, versions.
struct MenuBarView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 10) {
            header
            if let version = Updater.shared.readyVersion { updateBanner(version) }
            if let err = state.webError {
                Text(err).font(.system(size: 11)).foregroundStyle(.red).lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            actions
            ScrollView {
                VStack(spacing: 10) {
                    sites
                    if !state.installedServices.isEmpty { services }
                }
            }
            .frame(maxHeight: 360)
            .fixedSize(horizontal: false, vertical: true)
            footer
        }
        .padding(12)
        .frame(width: 330)
        .tint(.brand)
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: 10) {
            Tile(systemName: "cube.fill", size: 30, emphasized: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Nerd").font(.system(size: 14, weight: .semibold))
                HStack(spacing: 5) {
                    StatusDot(on: state.webRunning)
                    Text(state.webRunning ? "Çalışıyor" : "Durdu").foregroundStyle(.secondary)
                    Text(verbatim: "· .\(state.config.tld)").foregroundStyle(.tertiary)
                }
                .font(.system(size: 11))
            }
            Spacer()
            if state.caddyInstalled {
                Button { Task { await state.restartWebServer() } } label: { NerdIcon(name: "arrow.clockwise", size: 13) }
                    .help("Yeniden başlat")
                Button {
                    Task { if state.webRunning { state.stopWebServer() } else { await state.startWebServer() } }
                } label: {
                    NerdIcon(name: "power", size: 13).foregroundStyle(state.webRunning ? Color.brand : .secondary)
                }
                .help(state.webRunning ? "Durdur" : "Başlat")
            } else {
                Button("Caddy kur") { Task { await state.installCaddy() } }
            }
        }
        .buttonStyle(QuietButtonStyle())
        .controlSize(.small)
        .padding(.horizontal, 2)
    }

    private func updateBanner(_ version: String) -> some View {
        Button { Updater.shared.installAndRelaunch() } label: {
            HStack(spacing: 8) {
                NerdIcon(name: "arrow.down.circle", size: 14).foregroundStyle(Color.brand)
                Text("Nerd \(version) hazır")
                Spacer()
                Text("Yeniden başlat").foregroundStyle(Color.brand)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12).frame(height: 32)
            .glassSurface(RoundedRectangle(cornerRadius: 10, style: .continuous), tint: .brand.opacity(0.25))
        }
        .buttonStyle(.plain)
    }

    /// Four quick actions in a row.
    private var actions: some View {
        HStack(spacing: 8) {
            QuickAction(icon: "plus", title: "Yeni proje") { openMain(.newProject) }
            QuickAction(icon: "cylinder.split.1x2", title: "Veritabanı") { openMain(.database) }
            QuickAction(icon: "envelope", title: "Mail", badge: state.unreadMailCount) { openMain(.mail) }
            QuickAction(icon: "ladybug", title: "Debug") { openDebug() }
        }
    }

    private var sites: some View {
        VStack(alignment: .leading, spacing: 4) {
            label("Siteler")
            VStack(spacing: 0) {
                if state.sites.isEmpty {
                    Button("İlk projeni oluştur") { openMain(.newProject) }
                        .buttonStyle(.link).font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                ForEach(state.sites.prefix(8)) { site in
                    MenuSiteRow(site: site) { openMain(.sites, site: site.name) }
                }
                if state.sites.count > 8 {
                    Button("Tümü (\(state.sites.count))") { openMain(.sites) }
                        .buttonStyle(.link).font(.system(size: 11))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                }
            }
            .glassSurface(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var services: some View {
        VStack(alignment: .leading, spacing: 4) {
            label("Servisler")
            VStack(spacing: 0) {
                ForEach(state.installedServices) { def in
                    let running = state.services[def.formula]?.isRunning ?? false
                    HStack(spacing: 8) {
                        Tile(systemName: def.icon, brand: def.brand, size: 20)
                        Text(def.name).font(.system(size: 12.5))
                        if let port = def.port { Text(verbatim: ":\(port)").font(.system(size: 11)).foregroundStyle(.tertiary) }
                        Spacer()
                        if state.busy.contains(def.formula) { ProgressView().controlSize(.mini) }
                        Toggle("", isOn: Binding(get: { running }, set: { _ in Task { await state.toggleService(def) } }))
                            .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                            .disabled(state.busy.contains(def.formula))
                    }
                    .padding(.horizontal, 10).frame(height: 32)
                }
            }
            .glassSurface(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            versionMenu(icon: "chevron.left.forwardslash.chevron.right",
                        title: state.defaultPHP.map { "PHP \($0.version)" } ?? "PHP —") {
                ForEach(state.installedPHP) { v in
                    Button("PHP \(v.version)") { state.setDefaultPHP(v) }
                }
            }
            versionMenu(icon: "hexagon", title: "Node " + (state.defaultNode.map { String($0.major) } ?? "—")) {
                ForEach(state.nodeVersions) { n in
                    Button(n.label) { state.setDefaultNode(n) }
                }
            }
            Spacer()
            Button { openMain(.dashboard) } label: { NerdIcon(name: "macwindow", size: 13) }.help("Nerd'i aç")
            Button { NSApp.terminate(nil) } label: { NerdIcon(name: "power.circle", size: 13) }.help("Çıkış")
        }
        .buttonStyle(QuietButtonStyle())
        .controlSize(.small)
    }

    private func versionMenu<Content: View>(icon: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        Menu { content() } label: {
            HStack(spacing: 5) {
                NerdIcon(name: icon, size: 12)
                Text(verbatim: title)
            }
            .font(.system(size: 11.5, weight: .medium))
            .padding(.horizontal, 9).frame(height: 26)
            .glassSurface(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func label(_ text: LocalizedStringKey) -> some View {
        Text(text).textCase(.uppercase)
            .font(.system(size: 10, weight: .semibold)).tracking(0.5)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 4)
    }

    private func openMain(_ item: SidebarItem, site: String? = nil) {
        state.selection = item
        if let site { state.selectedSiteID = site }
        openWindow(id: "main")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openDebug() {
        openWindow(id: "debug")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Square-ish glass button with an icon and a caption.
private struct QuickAction: View {
    let icon: String
    let title: LocalizedStringKey
    var badge = 0
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                NerdIcon(name: icon, size: 16)
                    .foregroundStyle(hover ? Color.brand : Color.primary.opacity(0.8))
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text(verbatim: "\(badge)").font(.system(size: 8.5, weight: .bold)).foregroundStyle(.white)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Color.brand, in: Capsule())
                                .offset(x: 9, y: -6)
                        }
                    }
                Text(title).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .glassSurface(RoundedRectangle(cornerRadius: 12, style: .continuous), interactive: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct MenuSiteRow: View {
    @Environment(AppState.self) private var state
    let site: Site
    let details: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            SiteIcon(kind: site.kind, size: 20)
            Text(state.host(for: site)).font(.system(size: 12.5)).lineLimit(1)
            if site.config.secure { NerdIcon(name: "lock.fill", size: 10).foregroundStyle(.tertiary) }
            if state.isDevRunning(site) { StatusDot(on: true).help("Dev sunucusu çalışıyor") }
            Spacer()
            if hover {
                HStack(spacing: 2) {
                    IconButton(icon: "chevron.left.forwardslash.chevron.right", help: "Editör") { state.openInEditor(site.path) }
                    IconButton(icon: "terminal", help: "Terminal") { state.openInTerminal(site.path) }
                    MoreMenu {
                        Button("Finder'da göster") { state.reveal(site.path) }
                        if site.hasPackageJSON || site.kind == .dotnet {
                            Button(state.isDevRunning(site) ? "Dev sunucusunu durdur" : "Dev sunucusunu başlat") { state.toggleDev(site) }
                        }
                        Divider()
                        Button("Ayrıntılar…", action: details)
                    }
                }
            } else {
                Text(verbatim: site.kind.isProxied ? site.kind.title : (state.php(for: site).map { "PHP \($0.version)" } ?? ""))
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(hover ? Color.primary.opacity(0.05) : .clear)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { state.openSite(site) }
    }
}
