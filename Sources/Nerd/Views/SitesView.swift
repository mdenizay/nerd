import SwiftUI

struct SitesView: View {
    @Environment(AppState.self) private var state
    @State private var filter = ""

    var filtered: [Site] {
        filter.isEmpty ? state.sites : state.sites.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        @Bindable var state = state
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(filtered, selection: $state.selectedSiteID) { site in
                    HStack(spacing: 8) {
                        SiteIcon(kind: site.kind)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(site.name).lineLimit(1)
                            Text(site.kind.title).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if state.isDevRunning(site) { StatusDot(on: true) }
                        if site.linked { Image(systemName: "link").font(.caption2).foregroundStyle(.tertiary) }
                    }
                    .tag(site.name)
                }
                .searchable(text: $filter, placement: .sidebar, prompt: "Ara")
                Divider()
                HStack {
                    Button { if let url = Panels.chooseFolder("Bağlanacak proje klasörü") { state.linkFolder(url) } } label: {
                        Label("Klasör bağla", systemImage: "plus")
                    }
                    Spacer()
                    Button { state.scanSites(); Task { await state.reloadWebServer() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
            .frame(width: 240)
            Divider()

            Group {
                if let site = state.site(state.selectedSiteID) {
                    SiteDetailView(site: site).id(site.name)
                } else {
                    ContentUnavailableView("Site seçin", systemImage: "globe",
                                           description: Text("Park klasörlerindeki her klasör otomatik olarak bir site olur."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if state.selectedSiteID == nil { state.selectedSiteID = state.sites.first?.name }
        }
    }
}

struct SiteDetailView: View {
    @Environment(AppState.self) private var state
    let site: Site
    @State private var tab = 0
    @State private var artisanCommand = ""
    @State private var log = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(16)
            Divider()
            Form {
                Section("Ayarlar") {
                    if !site.kind.isNodeApp {
                        Picker("PHP", selection: Binding(
                            get: { site.config.php ?? "" },
                            set: { v in state.updateSite(site.name) { $0.php = v.isEmpty ? nil : v } })) {
                            Text("Varsayılan (\(state.defaultPHP?.version ?? "—"))").tag("")
                            ForEach(state.installedPHP) { Text("PHP \($0.version)").tag($0.version) }
                        }
                    }
                    Picker("Node", selection: Binding(
                        get: { site.config.node ?? "" },
                        set: { v in state.updateSite(site.name) { $0.node = v.isEmpty ? nil : v } })) {
                        Text("Varsayılan (\(state.defaultNode?.version ?? "—"))").tag("")
                        ForEach(state.nodeVersions) { Text($0.label).tag($0.version) }
                    }
                    Toggle("HTTPS", isOn: Binding(
                        get: { site.config.secure },
                        set: { v in state.updateSite(site.name) { $0.secure = v } }))
                    if site.kind.isNodeApp, let port = site.config.port {
                        LabeledContent("Dev sunucusu") {
                            HStack {
                                Text("localhost:\(String(port))").foregroundStyle(.secondary)
                                StatusDot(on: state.isDevRunning(site))
                            }
                        }
                    }
                }
                if site.isLaravel {
                    Section("Artisan") {
                        HStack {
                            TextField("", text: $artisanCommand, prompt: Text("migrate, route:list, queue:work…"))
                                .labelsHidden()
                                .onSubmit(runArtisan)
                            Button("Çalıştır", action: runArtisan).disabled(artisanCommand.isEmpty)
                        }
                    }
                }
                Section {
                    LogText(text: logText)
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } header: {
                    HStack {
                        if site.isLaravel {
                            Picker("", selection: $tab) {
                                Text("Laravel log").tag(0)
                                Text("Dev çıktısı").tag(1)
                            }
                            .pickerStyle(.segmented).labelsHidden().fixedSize()
                        } else {
                            Text("Dev çıktısı")
                        }
                        Spacer()
                        Button("Yenile") { log = state.laravelLog(site) }.buttonStyle(.link)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .onAppear {
            tab = site.isLaravel ? 0 : 1
            log = state.laravelLog(site)
        }
    }

    private var logText: String {
        if tab == 0 { return log.ifEmpty("storage/logs/laravel.log boş.") }
        let tail = state.processes[state.devKey(site)]?.tail(300) ?? ""
        return tail.ifEmpty("Dev sunucusu çalışmıyor.")
    }

    private var header: some View {
        HStack(spacing: 12) {
            SiteIcon(kind: site.kind, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(site.name).font(.title3.bold())
                    Pill(text: site.kind.title, color: site.kind.color == .primary ? .secondary : site.kind.color)
                }
                Button(state.url(for: site).absoluteString) { state.openSite(site) }
                    .buttonStyle(.link).font(.callout)
                Text((site.path.path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer()
            HStack(spacing: 6) {
                if site.hasPackageJSON {
                    IconButton(icon: state.isDevRunning(site) ? "stop.fill" : "play.fill",
                               help: state.isDevRunning(site) ? "Dev sunucusunu durdur" : "Dev sunucusunu başlat (npm run dev)",
                               tint: state.isDevRunning(site) ? .red : nil) { state.toggleDev(site) }
                }
                if state.connection(for: site) != nil {
                    IconButton(icon: "tablecells", help: "Veritabanı") {
                        state.databaseFocus = "site:\(site.name)"
                        state.selection = .database
                    }
                }
                IconButton(icon: "terminal", help: "Terminal") { state.openInTerminal(site.path) }
                IconButton(icon: "folder", help: "Finder") { state.reveal(site.path) }
                IconButton(icon: "chevron.left.forwardslash.chevron.right", help: "Editör") { state.openInEditor(site.path) }
                if site.linked {
                    Menu {
                        Button("Bağlantıyı kaldır", role: .destructive) { state.unlink(site) }
                    } label: { Image(systemName: "ellipsis") }
                        .menuIndicator(.hidden).fixedSize()
                }
                Button("Aç") { state.openSite(site) }.buttonStyle(.borderedProminent)
            }
        }
    }

    private func runArtisan() {
        let cmd = artisanCommand.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { return }
        artisanCommand = ""
        Task { await state.artisan(site, cmd); log = state.laravelLog(site) }
    }
}
