import SwiftUI
import AppKit

/// Menu bar panel in the style of macOS's own menu bar extras (Wi-Fi, Sound):
/// a title with a switch, grey section headings, hover-highlighted rows.
struct MenuBarView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    private var runningServices: [ServiceDef] {
        state.installedServices.filter { state.services[$0.formula]?.isRunning == true }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Nerd").font(.system(size: 13, weight: .semibold))
                Spacer()
                if state.caddyInstalled {
                    Toggle("", isOn: Binding(
                        get: { state.webRunning },
                        set: { on in Task { if on { await state.startWebServer() } else { state.stopWebServer() } } }))
                        .toggleStyle(.switch).controlSize(.small).labelsHidden()
                }
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)

            if let version = Updater.shared.readyVersion {
                MenuRow(action: { Updater.shared.installAndRelaunch() }) {
                    RoundIcon(name: "arrow.down.circle", active: true)
                    Text("Nerd \(version) hazır")
                    Spacer()
                    Text("Yeniden başlat").foregroundStyle(.secondary)
                }
            }
            if !state.caddyInstalled {
                MenuRow(action: { Task { await state.installCaddy() } }) {
                    RoundIcon(name: "exclamationmark", active: false)
                    Text("Caddy kur")
                }
            }

            separator
            heading("Siteler")
            if state.sites.isEmpty {
                placeholder("Henüz site yok.")
            }
            ForEach(state.sites.prefix(8)) { site in
                MenuRow(action: { state.openSite(site) }) {
                    RoundIcon(brand: site.kind.brand, name: site.kind.icon, active: state.webRunning)
                    Text(state.host(for: site)).lineLimit(1)
                    if site.config.secure { NerdIcon(name: "lock.fill", size: 9).foregroundStyle(.secondary) }
                    Spacer()
                    if state.isDevRunning(site) { StatusDot(on: true) }
                }
            }
            if state.sites.count > 8 {
                MenuRow(action: { openMain(.sites) }) {
                    Text("Tümü (\(state.sites.count))").foregroundStyle(.secondary)
                }
            }

            separator
            heading("Servisler")
            if runningServices.isEmpty {
                placeholder("Çalışan servis yok.")
            }
            ForEach(runningServices) { def in
                MenuRow(action: { openMain(.services) }) {
                    RoundIcon(brand: def.brand, name: def.icon, active: true)
                    Text(def.name)
                    Spacer()
                    if let port = def.port { Text(verbatim: ":\(port)").foregroundStyle(.secondary) }
                }
            }

            separator
            versionRow(title: "PHP", value: state.defaultPHP?.version ?? "—") {
                ForEach(state.installedPHP) { v in
                    Button { state.setDefaultPHP(v) } label: {
                        if state.defaultPHP?.version == v.version { Label("PHP \(v.version)", systemImage: "checkmark") } else { Text(verbatim: "PHP \(v.version)") }
                    }
                }
            }
            versionRow(title: "Node", value: state.defaultNode?.version ?? "—") {
                ForEach(state.nodeVersions) { n in
                    Button { state.setDefaultNode(n) } label: {
                        if state.defaultNode?.version == n.version { Label(n.label, systemImage: "checkmark") } else { Text(verbatim: n.label) }
                    }
                }
            }

            separator
            MenuRow(action: { openMain(.newProject) }) { Text("Yeni proje…") }
            MenuRow(action: { openMain(.dashboard) }) { Text("Nerd'i aç…") }
            MenuRow(action: { NSApp.terminate(nil) }) { Text("Nerd'den çık") }
                .padding(.bottom, 6)
        }
        .font(.system(size: 13))
        .frame(width: 300)
        .tint(.brand)
    }

    // MARK: Pieces

    private var separator: some View {
        Divider().padding(.horizontal, 14).padding(.vertical, 5)
    }

    private func heading(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.vertical, 3)
    }

    private func placeholder(_ text: LocalizedStringKey) -> some View {
        Text(text).foregroundStyle(.tertiary)
            .padding(.horizontal, 14).frame(height: 26, alignment: .leading)
    }

    /// "PHP            8.5 ⌃⌄" with the versions in a menu.
    private func versionRow<Content: View>(title: String, value: String, @ViewBuilder items: () -> Content) -> some View {
        Menu { items() } label: {
            HStack {
                Text(verbatim: title)
                Spacer()
                Text(verbatim: value).foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9).frame(height: 26)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(MenuRowButtonStyle())
        .menuIndicator(.hidden)
        .padding(.horizontal, 5)
    }

    private func openMain(_ item: SidebarItem) {
        state.selection = item
        openWindow(id: "main")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// A full-width row that highlights on hover, like items in macOS menu bar extras.
private struct MenuRow<Content: View>: View {
    let action: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) { content }
                .padding(.horizontal, 9)
                .frame(minHeight: 26)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowButtonStyle())
        .padding(.horizontal, 5)
    }
}

private struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Highlight(configuration: configuration)
    }

    private struct Highlight: View {
        let configuration: ButtonStyleConfiguration
        @State private var hover = false

        var body: some View {
            configuration.label
                .foregroundStyle(.primary)
                .background(Color.primary.opacity(configuration.isPressed ? 0.16 : hover ? 0.09 : 0),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .onHover { hover = $0 }
        }
    }
}

/// The round icon macOS uses in menu bar extras: filled with the accent when active.
private struct RoundIcon: View {
    var brand: String? = nil
    var name: String
    var active: Bool

    var body: some View {
        ZStack {
            Circle().fill(Color.primary.opacity(0.1))
            if let brand, Brands.exists(brand) {
                BrandLogo(slug: brand, size: 13)
            } else {
                NerdIcon(name: name, size: 12).foregroundStyle(active ? Color.brand : .secondary)
            }
        }
        .frame(width: 24, height: 24)
        .opacity(active ? 1 : 0.6)
    }
}
