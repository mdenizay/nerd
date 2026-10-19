import SwiftUI

/// Herd-style sites table with an inspector for the selected site.
struct SitesView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @State private var filter = ""
    @State private var showInspector = true

    private var filtered: [Site] {
        filter.isEmpty ? state.sites : state.sites.filter {
            $0.name.localizedCaseInsensitiveContains(filter) || $0.path.path.localizedCaseInsensitiveContains(filter)
        }
    }

    var body: some View {
        @Bindable var state = state
        Table(filtered, selection: $state.selectedSiteID) {
            TableColumn("Site") { site in
                HStack(spacing: 8) {
                    SiteIcon(kind: site.kind, size: 20)
                    Text(site.name)
                    if state.isDevRunning(site) { StatusDot(on: true).help("Dev sunucusu çalışıyor") }
                }
            }
            .width(min: 140, ideal: 180)
            TableColumn("Adres") { site in
                Text(state.url(for: site).absoluteString).foregroundStyle(Color.brand)
            }
            .width(min: 140, ideal: 200)
            TableColumn("Çalışma ortamı") { site in
                Text(verbatim: runtime(site)).foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 120)
            TableColumn("HTTPS") { site in
                if site.config.secure { NerdIcon(name: "lock.fill", size: 12).foregroundStyle(.green) }
            }
            .width(50)
            TableColumn("Klasör") { site in
                Text((site.path.path as NSString).abbreviatingWithTildeInPath).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let site = state.site(ids.first) {
                Button("Tarayıcıda aç") { state.openSite(site) }
                Button("Editörde aç") { state.openInEditor(site.path) }
                Button("Terminal") { state.openInTerminal(site.path) }
                Button("Finder'da göster") { state.reveal(site.path) }
                if site.hasPackageJSON || site.kind == .dotnet {
                    Divider()
                    Button(state.isDevRunning(site) ? "Dev sunucusunu durdur" : "Dev sunucusunu başlat") { state.toggleDev(site) }
                }
            }
        } primaryAction: { ids in
            if let site = state.site(ids.first) { state.openSite(site) }
        }
        .overlay {
            if state.sites.isEmpty {
                ContentUnavailableView {
                    Label("Henüz site yok.", systemImage: "globe")
                } description: {
                    Text("Park klasörlerindeki her klasör otomatik olarak bir site olur.")
                } actions: {
                    Button("Yeni proje") { state.selection = .newProject }.buttonStyle(.borderedProminent)
                }
            }
        }
        .searchable(text: $filter, placement: .toolbar, prompt: "Ara")
        .inspector(isPresented: $showInspector) {
            Group {
                if let site = state.site(state.selectedSiteID) {
                    SiteInspector(site: site).id(site.name)
                } else {
                    ContentUnavailableView("Site seçin", systemImage: "sidebar.right")
                }
            }
            .inspectorColumnWidth(min: 300, ideal: 340, max: 440)
        }
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("Yeni proje…") { state.selection = .newProject }
                    Button("Klasör bağla…") {
                        if let url = Panels.chooseFolder(String(localized: "Bağlanacak proje klasörü")) { state.linkFolder(url) }
                    }
                } label: { Label("Ekle", systemImage: "plus") }
            }
            ToolbarItem {
                Button { state.scanSites(); Task { await state.reloadWebServer() } } label: { Label("Yenile", systemImage: "arrow.clockwise") }
            }
            ToolbarItem {
                Button { showInspector.toggle() } label: { Label("Ayrıntılar", systemImage: "sidebar.right") }
            }
        }
        .onAppear {
            if state.selectedSiteID == nil { state.selectedSiteID = state.sites.first?.name }
        }
    }

    private func runtime(_ site: Site) -> String {
        switch site.kind {
        case .laravel, .php: state.php(for: site).map { "PHP \($0.version)" } ?? "PHP"
        case .next, .astro: "\(site.kind.title) · Node \(state.node(for: site)?.major ?? 0)"
        case .dotnet: ".NET \(state.dotnet(for: site)?.major ?? "—")"
        case .node: "Node \(state.node(for: site)?.major ?? 0)"
        case .plain: site.kind.title
        }
    }
}

/// The selected site's details, settings and actions.
struct SiteInspector: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    let site: Site
    @State private var tab = 0
    @State private var artisanCommand = ""
    @State private var log = ""
    @State private var showDelete = false
    @State private var dockerMessage: String?
    @State private var dockerOptions: DockerOptions?

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    SiteIcon(kind: site.kind, size: 48)
                    Text(site.name).font(.system(size: 17, weight: .semibold))
                    Button(state.url(for: site).absoluteString) { state.openSite(site) }
                        .buttonStyle(.link).font(.system(size: 12))
                    Text((site.path.path as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                    HStack(spacing: 6) {
                        Button("Aç") { state.openSite(site) }.buttonStyle(.borderedProminent)
                        iconButton("chevron.left.forwardslash.chevron.right", "Editör") { state.openInEditor(site.path) }
                        iconButton("terminal", "Terminal") { state.openInTerminal(site.path) }
                        iconButton("folder", "Finder") { state.reveal(site.path) }
                        if state.connection(for: site) != nil {
                            iconButton("cylinder.split.1x2", "Veritabanı") {
                                state.databaseFocus = "site:\(site.name)"
                                state.selection = .database
                            }
                        }
                    }
                    .controlSize(.small)
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }

            Section("Ayarlar") {
                if !site.kind.isProxied {
                    Picker("PHP", selection: Binding(
                        get: { site.config.php ?? "" },
                        set: { v in state.updateSite(site.name) { $0.php = v.isEmpty ? nil : v } })) {
                        Text("Varsayılan (\(state.defaultPHP?.version ?? "—"))").tag("")
                        ForEach(state.installedPHP) { Text(verbatim: "PHP \($0.version)").tag($0.version) }
                    }
                }
                if site.kind == .dotnet {
                    Picker(selection: Binding(
                        get: { site.config.dotnet ?? "" },
                        set: { v in state.updateSite(site.name) { $0.dotnet = v.isEmpty ? nil : v } })) {
                        Text("Varsayılan (\(state.defaultDotnet?.major ?? "—"))").tag("")
                        ForEach(state.installedDotnet) { Text(verbatim: ".NET \($0.major)").tag($0.major) }
                    } label: { Text(verbatim: ".NET") }
                } else {
                    Picker("Node", selection: Binding(
                        get: { site.config.node ?? "" },
                        set: { v in state.updateSite(site.name) { $0.node = v.isEmpty ? nil : v } })) {
                        Text("Varsayılan (\(state.defaultNode?.version ?? "—"))").tag("")
                        ForEach(state.nodeVersions) { Text(verbatim: $0.label).tag($0.version) }
                    }
                }
                Toggle("HTTPS", isOn: Binding(
                    get: { site.config.secure },
                    set: { v in state.updateSite(site.name) { $0.secure = v } }))
                if site.kind.isProxied || site.hasPackageJSON {
                    LabeledContent("Dev sunucusu") {
                        HStack(spacing: 6) {
                            if let port = site.config.port, site.kind.isProxied { Text(verbatim: "localhost:\(port)").foregroundStyle(.secondary) }
                            Button(state.isDevRunning(site) ? "Durdur" : "Başlat") { state.toggleDev(site) }
                        }
                    }
                }
            }

            if site.isLaravel {
                Section("Laravel") {
                    LabeledContent(state.mailRouted(site) ? "E-postalar Nerd'e gidiyor" : "E-postaları Nerd'de yakala") {
                        if state.mailRouted(site) {
                            Button("Gelen kutusu") { state.selection = .mail }
                        } else {
                            Button("Yönlendir") { state.routeMail(to: site); state.scanSites() }
                        }
                    }
                    HStack {
                        TextField("php artisan", text: $artisanCommand, prompt: Text("migrate, route:list, queue:work…"))
                            .font(.system(size: 12, design: .monospaced))
                            .onSubmit(runArtisan)
                        Button("Çalıştır", action: runArtisan).disabled(artisanCommand.isEmpty)
                    }
                }
            }

            if site.kind != .plain {
                Section("Dağıtım") {
                    LabeledContent {
                        Button(dockerFilesHere ? "Yeniden oluştur" : "Oluştur") {
                            dockerOptions = state.defaultDockerOptions(for: site)
                        }
                    } label: {
                        Label { Text(verbatim: "Docker · Dokploy") } icon: { Tile(systemName: "shippingbox.fill", brand: "docker", size: 20) }
                    }
                    if let dockerMessage {
                        Text(dockerMessage).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    if dockerFilesHere, state.dockerBinary != nil {
                        LabeledContent("Yerelde çalıştır") {
                            Button("Başlat") { Task { await state.dockerUp(site) }; state.selection = .jobs }
                        }
                    }
                    Label {
                        Text("Ek dosya gerekmez — repoyu Forge'a bağlayıp deploy edin.").font(.system(size: 11)).foregroundStyle(.secondary)
                    } icon: { Tile(systemName: "paperplane.fill", brand: "laravel", size: 20) }
                }
            }

            Section {
                LogText(text: logText)
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } header: {
                HStack {
                    if site.isLaravel {
                        Picker("", selection: $tab) {
                            Text("Laravel log").tag(0)
                            Text("Dev çıktısı").tag(1)
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize().controlSize(.small)
                    } else {
                        Text("Dev çıktısı")
                    }
                    Spacer()
                    Button("Debug penceresi") { openWindow(id: "debug") }.buttonStyle(.link).font(.system(size: 11))
                }
            }

            Section {
                if site.linked {
                    Button("Bağlantıyı kaldır (dosyalar kalır)") { state.unlink(site) }
                }
                Button("Projeyi sil…", role: .destructive) { showDelete = true }
            }
        }
        .formStyle(.grouped)
        .sheet(item: Binding(get: { dockerOptions.map(IdentifiedOptions.init) }, set: { dockerOptions = $0?.options })) { item in
            DockerOptionsSheet(site: site, options: item.options, overwrite: dockerFilesHere) { chosen in
                generateDocker(chosen)
            }
        }
        .sheet(isPresented: $showDelete) { DeleteSiteSheet(site: site) }
        .onAppear {
            tab = site.isLaravel ? 0 : 1
            log = state.laravelLog(site)
        }
    }

    private func iconButton(_ icon: String, _ help: LocalizedStringKey, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { NerdIcon(name: icon, size: 13) }.help(help)
    }

    private var logText: String {
        if tab == 0 { return log.ifEmpty(String(localized: "storage/logs/laravel.log boş.")) }
        let tail = state.processes[state.devKey(site)]?.tail(200) ?? ""
        return tail.ifEmpty(String(localized: "Dev sunucusu çalışmıyor."))
    }

    private var dockerFilesHere: Bool { state.dockerFilesExist(site) }

    private func generateDocker(_ options: DockerOptions) {
        let plan = state.dockerPlan(for: site, options: options)
        let files = state.writeDockerFiles(site, options: options)
        let fileList = files.joined(separator: ", "), serviceList = plan.services.joined(separator: ", ")
        dockerMessage = String(localized: "Oluşturuldu: \(fileList) · servisler: \(serviceList) · port \(String(plan.port))")
            + (site.isLaravel ? "\n" + String(localized: "Dokploy'da APP_KEY ve (MySQL/Postgres için) DB_PASSWORD değişkenlerini tanımlayın.") : "")
    }

    private func runArtisan() {
        let cmd = artisanCommand.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { return }
        artisanCommand = ""
        Task { await state.artisan(site, cmd); log = state.laravelLog(site) }
    }
}

struct DeleteSiteSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let site: Site
    @State private var confirmation = ""
    @State private var dropDatabase = false
    @State private var working = false
    @State private var error: String?

    private var database: DBConnection? {
        state.connection(for: site).flatMap { $0.driver == .sqlite ? nil : $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                IconBadge(systemName: "trash.fill", color: .red, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(site.name) silinsin mi?").font(.headline)
                    Text((site.path.path as NSString).abbreviatingWithTildeInPath)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Proje klasörü Çöp Sepeti'ne taşınır; oradan geri alabilirsiniz. Site, ayarları ve çalışan dev sunucusu Nerd'den kaldırılır.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let db = database {
                Toggle("\(db.driver.title) veritabanını da sil (\(db.database))", isOn: $dropDatabase)
                if dropDatabase {
                    Text("Veritabanı kalıcı olarak silinir, geri alınamaz.").font(.caption).foregroundStyle(.red)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Onaylamak için proje adını yazın: **\(site.name)**").font(.callout)
                TextField(site.name, text: $confirmation).textFieldStyle(.roundedBorder)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Vazgeç") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(role: .destructive) {
                    working = true
                    Task {
                        error = await state.deleteSite(site, dropDatabase: dropDatabase)
                        working = false
                        if error == nil { dismiss() }
                    }
                } label: {
                    if working { ProgressView().controlSize(.small) } else { Text("Projeyi sil") }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(confirmation != site.name || working)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

private struct IdentifiedOptions: Identifiable {
    let id = UUID()
    let options: DockerOptions
}

/// Choose what goes into docker-compose.yml next to the app.
struct DockerOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let site: Site
    @State var options: DockerOptions
    let overwrite: Bool
    let onCreate: (DockerOptions) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Tile(systemName: "shippingbox.fill", brand: "docker", size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Docker dosyaları").font(.system(size: 15, weight: .semibold))
                    Text(verbatim: "Dockerfile · docker-compose.yml · .dockerignore").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Form {
                Picker("Veritabanı", selection: $options.database) {
                    Text("Yok").tag(DockerOptions.Database.none)
                    if site.kind == .laravel { Text(verbatim: "SQLite").tag(DockerOptions.Database.sqlite) }
                    Text(verbatim: "PostgreSQL").tag(DockerOptions.Database.pgsql)
                    Text(verbatim: "MySQL").tag(DockerOptions.Database.mysql)
                }
                Toggle(isOn: $options.redis) { Text(verbatim: "Redis") }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 110)
            Text(note).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if overwrite {
                Label("Mevcut Docker dosyalarının üzerine yazılır.", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Vazgeç") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(overwrite ? "Yeniden oluştur" : "Oluştur") { onCreate(options); dismiss() }
                    .keyboardShortcut(.defaultAction).primaryButton()
            }
        }
        .controlSize(.small)
        .padding(18)
        .frame(width: 420)
    }

    private var note: String {
        switch site.kind {
        case .laravel: String(localized: "Laravel için DB_* ve REDIS_* değişkenleri ayarlanır; queue ve scheduler servisleri eklenir.")
        case .dotnet: String(localized: "Uygulamaya ConnectionStrings__DefaultConnection ve ConnectionStrings__Redis verilir.")
        default: String(localized: "Uygulamaya DATABASE_URL ve REDIS_URL verilir.")
        }
    }
}
