import SwiftUI
import AppKit

/// Menu bar panel: a power button with the state of the stack, sites and
/// services under one switcher, versions and New Project at the bottom.
struct MenuBarView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @State private var tab = Tab.sites

    enum Tab { case sites, services }

    private var runningServices: [ServiceDef] {
        state.installedServices.filter { state.services[$0.formula]?.isRunning == true }
    }

    var body: some View {
        VStack(spacing: 0) {
            hero
            if let version = Updater.shared.readyVersion { updateBanner(version) }
            switcher
            list
            Divider().opacity(0.5)
            bottomBar
        }
        .frame(width: 360)
        .tint(.brand)
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 10) {
            PowerButton(on: state.webRunning, enabled: state.caddyInstalled) {
                Task { if state.webRunning { state.stopWebServer() } else { await state.startWebServer() } }
            }
            VStack(spacing: 3) {
                Text(state.webRunning ? "Nerd çalışıyor" : "Nerd durdu")
                    .font(.system(size: 15, weight: .semibold))
                Text(verbatim: summary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            if !state.caddyInstalled {
                Button("Caddy kur") { Task { await state.installCaddy() } }.controlSize(.small)
            } else if let err = state.webError {
                Text(err).font(.system(size: 10.5)).foregroundStyle(.red).lineLimit(2).multilineTextAlignment(.center)
            }
        }
        .padding(.top, 20).padding(.bottom, 14).padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            // A soft glow of the brand colour while running
            RadialGradient(colors: [Color.brand.opacity(state.webRunning ? 0.22 : 0.06), .clear],
                           center: .top, startRadius: 0, endRadius: 220)
                .animation(.easeInOut(duration: 0.4), value: state.webRunning)
        }
    }

    private var summary: String {
        var parts = ["\(state.sites.count) " + String(localized: "site"), ".\(state.config.tld)"]
        if !runningServices.isEmpty { parts.append("\(runningServices.count) " + String(localized: "servis")) }
        return parts.joined(separator: "  ·  ")
    }

    private func updateBanner(_ version: String) -> some View {
        Button { Updater.shared.installAndRelaunch() } label: {
            HStack(spacing: 6) {
                NerdIcon(name: "arrow.down.circle", size: 13)
                Text("Nerd \(version) hazır: yeniden başlat ve güncelle")
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Color.brand)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.brand.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 10)
    }

    // MARK: Sites / services

    private var switcher: some View {
        Picker("", selection: $tab) {
            Text("Siteler").tag(Tab.sites)
            Text("Servisler").tag(Tab.services)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 2) {
                switch tab {
                case .sites:
                    if state.sites.isEmpty {
                        empty("globe", "Henüz site yok.")
                    }
                    ForEach(state.sites) { site in
                        PanelSiteRow(site: site) { openMain(.sites, site: site.name) }
                    }
                case .services:
                    if state.installedServices.isEmpty {
                        empty("server.rack", "Kurulu servis yok.")
                    }
                    ForEach(state.installedServices) { def in
                        PanelServiceRow(def: def)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .frame(maxHeight: 250)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func empty(_ icon: String, _ text: LocalizedStringKey) -> some View {
        VStack(spacing: 8) {
            NerdIcon(name: icon, size: 22).foregroundStyle(.tertiary)
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        GlassGroup(spacing: 6) {
        HStack(spacing: 6) {
            VersionChip(brand: "php", title: state.defaultPHP.map { "PHP \($0.version)" } ?? "PHP —") {
                ForEach(state.installedPHP) { v in
                    Button { state.setDefaultPHP(v) } label: { check(state.defaultPHP?.version == v.version, "PHP \(v.version)") }
                }
            }
            VersionChip(brand: "nodedotjs", title: "Node " + (state.defaultNode.map { String($0.major) } ?? "—")) {
                ForEach(state.nodeVersions) { n in
                    Button { state.setDefaultNode(n) } label: { check(state.defaultNode?.version == n.version, n.label) }
                }
            }
            Spacer(minLength: 4)
            Button { openMain(.newProject) } label: {
                Label("Yeni proje", systemImage: "plus").labelStyle(.titleAndIcon)
            }
            .primaryButton()
            .controlSize(.small)
            .fixedSize()
            Menu {
                Button("Nerd'i aç…") { openMain(.dashboard) }
                Button("Debug") { openWindow(id: "debug"); activate() }
                Button("Ayarlar…") { openMain(.settings) }
                Divider()
                Button("Nerd'den çık") { NSApp.terminate(nil) }
            } label: {
                NerdIcon(name: "gearshape", size: 14).foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func check(_ on: Bool, _ title: String) -> some View {
        if on { Label(title, systemImage: "checkmark") } else { Text(verbatim: title) }
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

// MARK: - Pieces

/// The big round switch at the top, glowing in the brand colour when on.
private struct PowerButton: View {
    let on: Bool
    let enabled: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            NerdIcon(name: "power", size: 24)
                .foregroundStyle(on ? Color.white : Color.secondary)
                .frame(width: 64, height: 64)
                .modifier(PowerSurface(on: on))
                .shadow(color: on ? Color.brand.opacity(0.4) : .clear, radius: hover ? 14 : 10, y: 2)
            .scaleEffect(hover ? 1.04 : 1)
            .animation(.spring(duration: 0.25), value: hover)
            .animation(.easeInOut(duration: 0.3), value: on)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hover = $0 }
        .help(on ? "Web sunucusunu durdur" : "Web sunucusunu başlat")
    }
}

private struct PanelSiteRow: View {
    @Environment(AppState.self) private var state
    let site: Site
    let details: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            SiteIcon(kind: site.kind, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(state.host(for: site)).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if site.config.secure { NerdIcon(name: "lock.fill", size: 9).foregroundStyle(.green) }
                }
                HStack(spacing: 4) {
                    if state.isDevRunning(site) { StatusDot(on: true) }
                    Text(verbatim: runtime).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if hover {
                HStack(spacing: 0) {
                    action("chevron.left.forwardslash.chevron.right", "Editör") { state.openInEditor(site.path) }
                    action("terminal", "Terminal") { state.openInTerminal(site.path) }
                    action("folder", "Finder") { state.reveal(site.path) }
                    action("ellipsis", "Ayrıntılar…", details)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 46)
        .background(hover ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .onTapGesture { state.openSite(site) }
        .help("Tarayıcıda aç")
    }

    private var runtime: String {
        switch site.kind {
        case .laravel, .php: "\(site.kind.title) · PHP \(state.php(for: site)?.version ?? "—")"
        case .dotnet: ".NET \(state.dotnet(for: site)?.major ?? "—")"
        default: site.kind.title
        }
    }

    private func action(_ icon: String, _ help: LocalizedStringKey, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            NerdIcon(name: icon, size: 13).foregroundStyle(.secondary)
                .frame(width: 26, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct PanelServiceRow: View {
    @Environment(AppState.self) private var state
    let def: ServiceDef
    @State private var hover = false

    var body: some View {
        let running = state.services[def.formula]?.isRunning ?? false
        HStack(spacing: 10) {
            Tile(systemName: def.icon, brand: def.brand, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(def.name).font(.system(size: 13, weight: .medium))
                HStack(spacing: 4) {
                    StatusDot(on: running)
                    Text(running ? "Çalışıyor" : "Durdu")
                    if let port = def.port { Text(verbatim: "· :\(port)") }
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if state.busy.contains(def.formula) { ProgressView().controlSize(.mini) }
            Toggle("", isOn: Binding(get: { running }, set: { _ in Task { await state.toggleService(def) } }))
                .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                .disabled(state.busy.contains(def.formula))
        }
        .padding(.horizontal, 8)
        .frame(height: 46)
        .background(hover ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onHover { hover = $0 }
    }
}

/// "PHP 8.5" with a logo; the versions open in a menu.
private struct VersionChip<Content: View>: View {
    let brand: String
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        Menu { content } label: {
            HStack(spacing: 5) {
                BrandLogo(slug: brand, size: 12)
                Text(verbatim: title).foregroundStyle(.primary)
            }
            .font(.system(size: 11.5, weight: .medium))
            .padding(.horizontal, 9).frame(height: 26)
            .glassSurface(Capsule(), interactive: true)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// The power button's surface: tinted Liquid Glass on macOS 26, a gradient disc before.
private struct PowerSurface: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(on ? Glass.regular.tint(Color.brand).interactive() : Glass.regular.interactive(), in: Circle())
        } else {
            content.background(
                Circle().fill(on ? AnyShapeStyle(Color.brand.gradient) : AnyShapeStyle(Color.primary.opacity(0.08)))
            )
        }
    }
}
