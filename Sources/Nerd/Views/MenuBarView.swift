import SwiftUI
import AppKit

/// The menu bar panel: a small dashboard in the same idiom as the main window.
struct MenuBarView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 12) {
            header
            if let version = Updater.shared.readyVersion { updateBanner(version) }
            if let err = state.webError {
                Text(err).font(.system(size: 11)).foregroundStyle(.red).lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            actions
            ScrollView {
                VStack(spacing: 12) {
                    group("Siteler", trailing: state.sites.isEmpty ? nil : ("Tümü", { openMain(.sites) })) { sites }
                    if !state.installedServices.isEmpty {
                        group("Servisler", trailing: ("Tümü", { openMain(.services) })) { services }
                    }
                }
            }
            .frame(maxHeight: 380)
            .fixedSize(horizontal: false, vertical: true)
            footer
        }
        .padding(14)
        .frame(width: 340)
        .tint(.brand)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Nerd").font(.system(size: 14, weight: .semibold))
                HStack(spacing: 5) {
                    StatusDot(on: state.webRunning)
                    Text(state.webRunning ? "Çalışıyor" : "Durdu")
                    Text(verbatim: "· .\(state.config.tld)").foregroundStyle(.tertiary)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            Spacer()
            if state.caddyInstalled {
                Button { Task { await state.restartWebServer() } } label: { NerdIcon(name: "arrow.clockwise", size: 13) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Yeniden başlat")
                    .disabled(!state.webRunning)
                Toggle("", isOn: Binding(
                    get: { state.webRunning },
                    set: { on in Task { if on { await state.startWebServer() } else { state.stopWebServer() } } }))
                    .toggleStyle(.switch).controlSize(.small).labelsHidden()
                    .help(state.webRunning ? "Web sunucusunu durdur" : "Web sunucusunu başlat")
            } else {
                Button("Caddy kur") { Task { await state.installCaddy() } }.controlSize(.small)
            }
        }
    }

    private func updateBanner(_ version: String) -> some View {
        Button { Updater.shared.installAndRelaunch() } label: {
            HStack(spacing: 8) {
                SettingsIcon(name: "arrow.down.circle", color: .brand, size: 20)
                Text("Nerd \(version) hazır")
                Spacer()
                Text("Yeniden başlat").foregroundStyle(Color.brand)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10).frame(height: 34)
            .background(Color.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Quick actions

    private var actions: some View {
        HStack(spacing: 6) {
            QuickAction(icon: "plus", title: "Yeni proje", color: .purple) { openMain(.newProject) }
            QuickAction(icon: "cylinder.split.1x2", title: "Veritabanı", color: .teal) { openMain(.database) }
            QuickAction(icon: "envelope", title: "Mail", color: .pink, badge: state.unreadMailCount) { openMain(.mail) }
            QuickAction(icon: "ladybug", title: "Debug", color: .orange) { openWindow(id: "debug"); activate() }
        }
    }

    // MARK: Sites and services

    @ViewBuilder
    private var sites: some View {
        if state.sites.isEmpty {
            HStack {
                Text("Henüz site yok.").foregroundStyle(.secondary)
                Spacer()
                Button("Yeni proje") { openMain(.newProject) }.controlSize(.small)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 10).frame(height: 36)
        }
        ForEach(Array(state.sites.prefix(8).enumerated()), id: \.element.id) { index, site in
            if index > 0 { Divider().padding(.leading, 42) }
            MenuSiteRow(site: site) { openMain(.sites, site: site.name) }
        }
    }

    @ViewBuilder
    private var services: some View {
        ForEach(Array(state.installedServices.enumerated()), id: \.element.id) { index, def in
            let running = state.services[def.formula]?.isRunning ?? false
            if index > 0 { Divider().padding(.leading, 42) }
            HStack(spacing: 10) {
                Tile(systemName: def.icon, brand: def.brand, size: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(def.name).font(.system(size: 12.5))
                    if let port = def.port {
                        Text(verbatim: "127.0.0.1:\(port)").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if state.busy.contains(def.formula) { ProgressView().controlSize(.mini) }
                Toggle("", isOn: Binding(get: { running }, set: { _ in Task { await state.toggleService(def) } }))
                    .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                    .disabled(state.busy.contains(def.formula))
            }
            .padding(.horizontal, 10).frame(height: 40)
        }
    }

    private func group<Content: View>(_ title: LocalizedStringKey, trailing: (LocalizedStringKey, () -> Void)?,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                if let trailing {
                    Button(trailing.0, action: trailing.1).buttonStyle(.link).font(.system(size: 11))
                }
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) { content() }
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            versionMenu(brand: "php", title: state.defaultPHP.map { "PHP \($0.version)" } ?? "PHP —") {
                ForEach(state.installedPHP) { v in Button("PHP \(v.version)") { state.setDefaultPHP(v) } }
            }
            versionMenu(brand: "nodedotjs", title: "Node " + (state.defaultNode.map { String($0.major) } ?? "—")) {
                ForEach(state.nodeVersions) { n in Button(n.label) { state.setDefaultNode(n) } }
            }
            Spacer()
            Button { openMain(.dashboard) } label: { NerdIcon(name: "macwindow", size: 14) }.help("Nerd'i aç")
            Button { openMain(.settings) } label: { NerdIcon(name: "gearshape", size: 14) }.help("Ayarlar")
            Button { NSApp.terminate(nil) } label: { NerdIcon(name: "power", size: 14) }.help("Nerd'den çık")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
    }

    private func versionMenu<Content: View>(brand: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        Menu { content() } label: {
            HStack(spacing: 5) {
                BrandLogo(slug: brand, size: 12)
                Text(verbatim: title).foregroundStyle(.primary)
            }
            .font(.system(size: 11.5, weight: .medium))
            .padding(.horizontal, 9).frame(height: 24)
            .background(.quaternary.opacity(0.45), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: Navigation

    private func openMain(_ item: SidebarItem, site: String? = nil) {
        state.selection = item
        if let site { state.selectedSiteID = site }
        openWindow(id: "main")
        activate()
    }

    private func activate() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// A coloured square with a caption, like the overview's quick actions.
private struct QuickAction: View {
    let icon: String
    let title: LocalizedStringKey
    let color: Color
    var badge = 0
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                SettingsIcon(name: icon, color: color, size: 30)
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text(verbatim: "\(badge)").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Color.red, in: Capsule())
                                .offset(x: 7, y: -5)
                        }
                    }
                Text(title).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(hover ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
        HStack(spacing: 10) {
            SiteIcon(kind: site.kind, size: 22)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(state.host(for: site)).font(.system(size: 12.5)).lineLimit(1)
                    if site.config.secure { NerdIcon(name: "lock.fill", size: 9).foregroundStyle(.green) }
                    if state.isDevRunning(site) { StatusDot(on: true).help("Dev sunucusu çalışıyor") }
                }
                Text(verbatim: runtime).font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
            Spacer()
            if hover {
                HStack(spacing: 2) {
                    rowButton("chevron.left.forwardslash.chevron.right", "Editör") { state.openInEditor(site.path) }
                    rowButton("terminal", "Terminal") { state.openInTerminal(site.path) }
                    Menu {
                        Button("Finder'da göster") { state.reveal(site.path) }
                        if site.hasPackageJSON || site.kind == .dotnet {
                            Button(state.isDevRunning(site) ? "Dev sunucusunu durdur" : "Dev sunucusunu başlat") { state.toggleDev(site) }
                        }
                        Divider()
                        Button("Ayrıntılar…", action: details)
                    } label: { NerdIcon(name: "ellipsis", size: 13) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .foregroundStyle(.secondary)
                }
            } else {
                NerdIcon(name: "arrow.up.right", size: 11).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(hover ? Color.primary.opacity(0.05) : .clear)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { state.openSite(site) }
    }

    private var runtime: String {
        switch site.kind {
        case .laravel, .php: "\(site.kind.title) · PHP \(state.php(for: site)?.version ?? "—")"
        case .dotnet: ".NET \(state.dotnet(for: site)?.major ?? "—")"
        default: site.kind.title
        }
    }

    private func rowButton(_ icon: String, _ help: LocalizedStringKey, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { NerdIcon(name: icon, size: 13).frame(width: 22, height: 22).contentShape(Rectangle()) }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(help)
    }
}
