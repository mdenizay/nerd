import SwiftUI
import AppKit

/// Herd-style menu bar menu: a native macOS menu.
struct MenuBarView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(state.webRunning ? "Nerd çalışıyor" : "Nerd durdu")
        if let version = Updater.shared.readyVersion {
            Button("Nerd \(version) hazır: yeniden başlat ve güncelle") { Updater.shared.installAndRelaunch() }
        }
        if state.caddyInstalled {
            if state.webRunning {
                Button("Yeniden başlat") { Task { await state.restartWebServer() } }
                Button("Durdur") { state.stopWebServer() }
            } else {
                Button("Başlat") { Task { await state.startWebServer() } }
            }
        } else {
            Button("Caddy kur") { Task { await state.installCaddy() } }
        }

        Divider()

        Button("Nerd'i aç") { openMain(.dashboard) }.keyboardShortcut("o")
        Menu("Siteler") {
            if state.sites.isEmpty { Text("Henüz site yok.") }
            ForEach(state.sites) { site in
                Menu(state.host(for: site)) {
                    Button("Tarayıcıda aç") { state.openSite(site) }
                    Button("Editörde aç") { state.openInEditor(site.path) }
                    Button("Terminal") { state.openInTerminal(site.path) }
                    Button("Finder'da göster") { state.reveal(site.path) }
                    if site.hasPackageJSON || site.kind == .dotnet {
                        Divider()
                        Button(state.isDevRunning(site) ? "Dev sunucusunu durdur" : "Dev sunucusunu başlat") { state.toggleDev(site) }
                    }
                    Divider()
                    Button("Ayrıntılar…") { openMain(.sites, site: site.name) }
                }
            }
            Divider()
            Button("Yeni proje…") { openMain(.newProject) }
        }

        Divider()

        if !state.installedPHP.isEmpty {
            Picker(selection: Binding(
                get: { state.defaultPHP?.version ?? "" },
                set: { v in if let p = state.phpVersion(v) { state.setDefaultPHP(p) } })) {
                ForEach(state.installedPHP) { Text(verbatim: "PHP \($0.version)").tag($0.version) }
            } label: { Text(verbatim: "PHP \(state.defaultPHP?.version ?? "—")") }
        }
        if !state.nodeVersions.isEmpty {
            Picker(selection: Binding(
                get: { state.defaultNode?.version ?? "" },
                set: { v in if let n = state.nodeVersion(v) { state.setDefaultNode(n) } })) {
                ForEach(state.nodeVersions) { Text(verbatim: $0.label).tag($0.version) }
            } label: { Text(verbatim: "Node \(state.defaultNode?.version ?? "—")") }
        }
        if !state.installedDotnet.isEmpty {
            Picker(selection: Binding(
                get: { state.defaultDotnet?.major ?? "" },
                set: { v in if let d = state.dotnetVersion(v) { state.setDefaultDotnet(d) } })) {
                ForEach(state.installedDotnet) { Text(verbatim: ".NET \($0.major)").tag($0.major) }
            } label: { Text(verbatim: ".NET \(state.defaultDotnet?.major ?? "—")") }
        }
        if !state.installedServices.isEmpty {
            Menu("Servisler") {
                ForEach(state.installedServices) { def in
                    Toggle(def.name, isOn: Binding(
                        get: { state.services[def.formula]?.isRunning ?? false },
                        set: { _ in Task { await state.toggleService(def) } }))
                }
            }
        }

        Divider()

        Button("Veritabanı") { openMain(.database) }
        Button(state.unreadMailCount > 0 ? "Mail (\(state.unreadMailCount))" : "Mail") { openMain(.mail) }
        Button("Debug") { openWindow(id: "debug"); activate() }.keyboardShortcut("d", modifiers: [.command, .shift])

        Divider()

        Button("Ayarlar…") { openMain(.settings) }.keyboardShortcut(",")
        Button("Nerd'den çık") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }

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
