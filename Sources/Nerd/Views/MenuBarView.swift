import SwiftUI
import AppKit

/// Menu bar panel: a plain, compact list. Status with a switch on top,
/// sites and services below, versions and actions in the footer.
struct MenuBarView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let version = Updater.shared.readyVersion { updateRow(version) }
            Divider().padding(.horizontal, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionTitle("Siteler")
                    if state.sites.isEmpty {
                        placeholder("Henüz site yok.")
                    }
                    ForEach(state.sites) { site in
                        PanelSiteRow(site: site) { openMain(.sites, site: site.name) }
                    }
                    if !state.installedServices.isEmpty {
                        sectionTitle("Servisler")
                        ForEach(state.installedServices) { PanelServiceRow(def: $0) }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
            .frame(maxHeight: 340)
            .fixedSize(horizontal: false, vertical: true)
            Divider().padding(.horizontal, 12)
            footer
        }
        .frame(width: 300)
        .tint(.brand)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            StatusDot(on: state.webRunning)
            VStack(alignment: .leading, spacing: 1) {
                Text(state.webRunning ? "Nerd çalışıyor" : "Nerd durdu")
                    .font(.system(size: 13, weight: .semibold))
                if let err = state.webError {
                    Text(err).font(.system(size: 10.5)).foregroundStyle(.red).lineLimit(1)
                } else {
                    Text(verbatim: summary).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if state.caddyInstalled {
                Toggle("", isOn: Binding(
                    get: { state.webRunning },
                    set: { on in Task { if on { await state.startWebServer() } else { state.stopWebServer() } } }))
                    .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                    .help(state.webRunning ? "Web sunucusunu durdur" : "Web sunucusunu başlat")
            } else {
                Button("Caddy kur") { Task { await state.installCaddy() } }.controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var summary: String {
        var parts = ["\(state.sites.count) " + String(localized: "site"), ".\(state.config.tld)"]
        let running = state.installedServices.filter { state.services[$0.formula]?.isRunning == true }.count
        if running > 0 { parts.append("\(running) " + String(localized: "servis")) }
        return parts.joined(separator: " · ")
    }

    private func updateRow(_ version: String) -> some View {
        Button { Updater.shared.installAndRelaunch() } label: {
            Text("Nerd \(version) hazır: yeniden başlat ve güncelle")
                .font(.system(size: 11))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.link)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    // MARK: List

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func placeholder(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(.tertiary)
            .padding(.horizontal, 8).padding(.vertical, 6)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 2) {
            VersionMenu(title: state.defaultPHP.map { "PHP \($0.version)" } ?? "PHP —") {
                ForEach(state.installedPHP) { v in
                    Button { state.setDefaultPHP(v) } label: { check(state.defaultPHP?.version == v.version, "PHP \(v.version)") }
                }
            }
            VersionMenu(title: "Node " + (state.defaultNode.map { String($0.major) } ?? "—")) {
                ForEach(state.nodeVersions) { n in
                    Button { state.setDefaultNode(n) } label: { check(state.defaultNode?.version == n.version, n.label) }
                }
            }
            Spacer(minLength: 4)
            Button { openMain(.newProject) } label: {
                NerdIcon(name: "plus", size: 13).frame(width: 24, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Yeni proje")
            Menu {
                Button("Nerd'i aç…") { openMain(.dashboard) }
                Button("Yeni proje…") { openMain(.newProject) }
                Button("Debug") { openWindow(id: "debug"); activate() }
                Button("Ayarlar…") { openMain(.settings) }
                Divider()
                Button("Nerd'den çık") { NSApp.terminate(nil) }
            } label: {
                NerdIcon(name: "gearshape", size: 13).foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
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

private struct PanelSiteRow: View {
    @Environment(AppState.self) private var state
    let site: Site
    let details: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            SiteIcon(kind: site.kind, size: 20)
            Text(state.host(for: site)).font(.system(size: 12.5)).lineLimit(1)
            if site.config.secure { NerdIcon(name: "lock.fill", size: 8.5).foregroundStyle(.secondary) }
            if state.isDevRunning(site) { StatusDot(on: true) }
            Spacer(minLength: 4)
            if !hover {
                Text(verbatim: runtime).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
            } else {
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
        .frame(height: 30)
        .background(hover ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
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
            NerdIcon(name: icon, size: 12).foregroundStyle(.secondary)
                .frame(width: 22, height: 22).contentShape(Rectangle())
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
        HStack(spacing: 8) {
            Tile(systemName: def.icon, brand: def.brand, size: 20)
            Text(def.name).font(.system(size: 12.5)).lineLimit(1)
            if let port = def.port { Text(verbatim: ":\(port)").font(.system(size: 11)).foregroundStyle(.tertiary) }
            Spacer()
            if state.busy.contains(def.formula) { ProgressView().controlSize(.mini) }
            Toggle("", isOn: Binding(get: { running }, set: { _ in Task { await state.toggleService(def) } }))
                .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                .disabled(state.busy.contains(def.formula))
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(hover ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover { hover = $0 }
    }
}

/// "PHP 8.5": the versions open in a menu.
private struct VersionMenu<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        Menu { content } label: {
            Text(verbatim: title).font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 4)
    }
}
