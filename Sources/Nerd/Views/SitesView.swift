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
                    HStack {
                        Image(systemName: site.isLaravel ? "leaf.fill" : "folder.fill")
                            .foregroundStyle(site.isLaravel ? .red : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(site.name)
                            Text(state.host(for: site)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if site.linked { Image(systemName: "link").font(.caption).foregroundStyle(.secondary) }
                        if let php = state.php(for: site) { Pill(text: php.version, color: .indigo) }
                    }
                    .tag(site.name)
                }
                .searchable(text: $filter, placement: .sidebar, prompt: "Ara")
                Divider()
                HStack {
                    Button { if let url = Panels.chooseFolder("Bağlanacak proje klasörü") { state.linkFolder(url) } } label: {
                        Label("Klasör bağla", systemImage: "link.badge.plus")
                    }
                    Spacer()
                    Button { state.scanSites(); Task { await state.reloadWebServer() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
            .frame(width: 270)
            Divider()

            Group {
                if let site = state.site(state.selectedSiteID) {
                    SiteDetailView(site: site).id(site.name)
                } else {
                    ContentUnavailableView("Site seçin", systemImage: "globe",
                                           description: Text("Park klasörlerindeki her klasör otomatik olarak bir site olur."))
                }
            }
            .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
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
        VStack(alignment: .leading, spacing: 14) {
            header
            settings
            actions
            Picker("", selection: $tab) {
                Text("Laravel Log").tag(0)
                Text("Vite Çıktısı").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
            Group {
                if tab == 0 {
                    LogText(text: log.ifEmpty(site.isLaravel ? "storage/logs/laravel.log boş." : "Laravel projesi değil."))
                } else {
                    LogText(text: state.processes[state.viteKey(site)]?.tail(300) ?? "Vite çalışmıyor.")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            HStack {
                Spacer()
                Button("Yenile") { log = state.laravelLog(site) }.buttonStyle(.link)
            }
        }
        .padding(20)
        .onAppear { log = state.laravelLog(site) }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(site.name).font(.title2.bold())
                    if site.isLaravel { Pill(text: "Laravel", color: .red) }
                    if site.linked { Pill(text: "Bağlı", color: .blue) }
                }
                Link(state.url(for: site).absoluteString, destination: state.url(for: site))
                Text(site.path.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer()
            Button { state.open(state.url(for: site)) } label: { Label("Aç", systemImage: "safari") }
                .buttonStyle(.borderedProminent)
        }
    }

    private var settings: some View {
        Form {
            Picker("PHP", selection: Binding(
                get: { site.config.php ?? "" },
                set: { v in state.updateSite(site.name) { $0.php = v.isEmpty ? nil : v } })) {
                Text("Varsayılan (\(state.defaultPHP?.version ?? "—"))").tag("")
                ForEach(state.installedPHP) { Text("PHP \($0.version)").tag($0.version) }
            }
            Picker("Node", selection: Binding(
                get: { site.config.node ?? "" },
                set: { v in state.updateSite(site.name) { $0.node = v.isEmpty ? nil : v } })) {
                Text("Varsayılan (\(state.defaultNode?.version ?? "—"))").tag("")
                ForEach(state.nodeVersions) { Text($0.label).tag($0.version) }
            }
            Toggle("HTTPS (yerel sertifika)", isOn: Binding(
                get: { site.config.secure },
                set: { v in state.updateSite(site.name) { $0.secure = v } }))
        }
        .formStyle(.grouped)
        .frame(maxHeight: 170)
        .scrollDisabled(true)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { state.openInEditor(site.path) } label: { Label("Editör", systemImage: "chevron.left.forwardslash.chevron.right") }
                Button { state.reveal(site.path) } label: { Label("Finder", systemImage: "folder") }
                Button { state.openInTerminal(site.path) } label: { Label("Terminal", systemImage: "terminal") }
                if site.hasPackageJSON {
                    Button { state.toggleVite(site) } label: {
                        Label(state.isViteRunning(site) ? "Vite'i durdur" : "npm run dev",
                              systemImage: state.isViteRunning(site) ? "stop.fill" : "play.fill")
                    }
                    .tint(state.isViteRunning(site) ? .red : nil)
                }
                if state.connection(for: site) != nil {
                    Button {
                        state.databaseFocus = "site:\(site.name)"
                        state.selection = .database
                    } label: { Label("Veritabanı", systemImage: "tablecells") }
                }
                Spacer()
                if site.linked {
                    Button("Bağlantıyı kaldır", role: .destructive) { state.unlink(site) }
                }
            }
            if site.isLaravel {
                HStack {
                    Text("php artisan").font(.callout.monospaced()).foregroundStyle(.secondary)
                    TextField("migrate, queue:work, route:list…", text: $artisanCommand)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(runArtisan)
                    Button("Çalıştır", action: runArtisan).disabled(artisanCommand.isEmpty)
                }
            }
        }
    }

    private func runArtisan() {
        let cmd = artisanCommand.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { return }
        Task { await state.artisan(site, cmd); log = state.laravelLog(site) }
        state.selectedJobID = state.jobs.first?.id
    }
}
