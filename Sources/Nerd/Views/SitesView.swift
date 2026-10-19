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
                    HStack(spacing: 6) {
                        SiteIcon(kind: site.kind, size: 18)
                        Text(site.name).lineLimit(1)
                        Spacer()
                        if state.isDevRunning(site) { StatusDot(on: true) }
                        if site.linked { Glyph(systemName: "link", size: 9) }
                    }
                    .tag(site.name)
                }
                .listStyle(.sidebar)
                .searchable(text: $filter, placement: .sidebar, prompt: "Ara")
                Divider()
                HStack {
                    Button { if let url = Panels.chooseFolder(String(localized: "Bağlanacak proje klasörü")) { state.linkFolder(url) } } label: {
                        NerdIcon(name: "plus")
                    }
                    .help("Klasör bağla")
                    Spacer()
                    Button { state.scanSites(); Task { await state.reloadWebServer() } } label: {
                        NerdIcon(name: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10).frame(height: 28)
            }
            .frame(width: 220)
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
    @State private var confirmDocker = false
    @State private var showDelete = false
    @State private var dockerMessage: String?
    @State private var dockerOptions: DockerOptions?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 0) {
                    SectionLabel("Ayarlar")
                    ListCard {
                    if !site.kind.isProxied {
                        Row {
                            Tile(systemName: "chevron.left.forwardslash.chevron.right", brand: "php", size: 18)
                            Text("PHP")
                            Spacer()
                            Picker("", selection: Binding(
                                get: { site.config.php ?? "" },
                                set: { v in state.updateSite(site.name) { $0.php = v.isEmpty ? nil : v } })) {
                                Text("Varsayılan (\(state.defaultPHP?.version ?? "—"))").tag("")
                                ForEach(state.installedPHP) { Text(verbatim: "PHP \($0.version)").tag($0.version) }
                            }
                            .labelsHidden().fixedSize().controlSize(.small)
                        }
                    }
                    if site.kind == .dotnet {
                        Row {
                            Tile(systemName: "number", brand: "dotnet", size: 18)
                            Text(verbatim: ".NET")
                            Spacer()
                            Picker("", selection: Binding(
                                get: { site.config.dotnet ?? "" },
                                set: { v in state.updateSite(site.name) { $0.dotnet = v.isEmpty ? nil : v } })) {
                                Text("Varsayılan (\(state.defaultDotnet?.major ?? "—"))").tag("")
                                ForEach(state.installedDotnet) { Text(verbatim: ".NET \($0.major)").tag($0.major) }
                            }
                            .labelsHidden().fixedSize().controlSize(.small)
                        }
                    }
                    if site.kind != .dotnet {
                    Row {
                        Tile(systemName: "hexagon.fill", brand: "nodedotjs", size: 18)
                        Text("Node")
                        Spacer()
                        Picker("", selection: Binding(
                            get: { site.config.node ?? "" },
                            set: { v in state.updateSite(site.name) { $0.node = v.isEmpty ? nil : v } })) {
                            Text("Varsayılan (\(state.defaultNode?.version ?? "—"))").tag("")
                            ForEach(state.nodeVersions) { Text(verbatim: $0.label).tag($0.version) }
                        }
                        .labelsHidden().fixedSize().controlSize(.small)
                    }
                    }
                    Row {
                        Tile(systemName: "lock.fill", size: 18)
                        Text("HTTPS")
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { site.config.secure },
                            set: { v in state.updateSite(site.name) { $0.secure = v } }))
                            .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                    }
                    if site.kind.isProxied, let port = site.config.port {
                        Row {
                            Tile(systemName: "play.fill", size: 18)
                            Text("Dev sunucusu")
                            Spacer()
                            StatusDot(on: state.isDevRunning(site))
                            Detail(text: "localhost:\(port)")
                        }
                    }
                    }

                    if site.isLaravel {
                        SectionLabel("Mail")
                        ListCard {
                        Row {
                            Tile(systemName: "envelope.fill", size: 18)
                            Text(state.mailRouted(site) ? "E-postalar Nerd'e gidiyor" : "E-postaları Nerd'de yakala")
                            Spacer()
                            if state.mailRouted(site) {
                                Button("Gelen kutusu") { state.selection = .mail }.controlSize(.small)
                            } else {
                                Button("Yönlendir") { state.routeMail(to: site); state.scanSites() }.controlSize(.small)
                            }
                        }
                        }
                        SectionLabel("Artisan")
                        ListCard {
                        Row {
                            Tile(systemName: "terminal.fill", size: 18)
                            Text(verbatim: "php artisan").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                            TextField("", text: $artisanCommand, prompt: Text("migrate, route:list, queue:work…"))
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                                .onSubmit(runArtisan)
                            Button("Çalıştır", action: runArtisan).controlSize(.small).disabled(artisanCommand.isEmpty)
                        }
                        }
                    }

                    if site.kind != .plain {
                        SectionLabel("Dağıtım")
                        ListCard {
                        Row {
                            Tile(systemName: "shippingbox.fill", brand: "docker", size: 18)
                            Text(verbatim: "Docker · Dokploy")
                            Detail(text: dockerFilesHere ? String(localized: "Dockerfile ve docker-compose.yml hazır") : String(localized: "Production için Dockerfile + compose oluştur"))
                            Spacer()
                            if dockerFilesHere, state.dockerBinary != nil {
                                Button("Yerelde çalıştır") { Task { await state.dockerUp(site) }; state.selection = .jobs }.controlSize(.small)
                            }
                            Button(dockerFilesHere ? "Yeniden oluştur" : "Oluştur") {
                                dockerOptions = state.defaultDockerOptions(for: site)
                            }
                            .controlSize(.small)
                        }
                        if let dockerMessage {
                            Text(dockerMessage)
                                .font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Metrics.inset).padding(.vertical, 6)
                        }
                        Row {
                            Tile(systemName: "paperplane.fill", brand: "laravel", size: 18)
                            Text(verbatim: "Laravel Forge")
                            Detail(text: String(localized: "Ek dosya gerekmez — repoyu Forge'a bağlayıp deploy edin."))
                            Spacer()
                        }
                        }
                    }

                    SectionLabel(text: site.isLaravel ? (tab == 0 ? "Laravel log" : "Dev çıktısı") : "Dev çıktısı") {
                        if site.isLaravel {
                            Picker("", selection: $tab) {
                                Text("Laravel log").tag(0)
                                Text("Dev çıktısı").tag(1)
                            }
                            .pickerStyle(.segmented).labelsHidden().fixedSize()
                        }
                        Button("Yenile") { log = state.laravelLog(site) }
                    }
                    LogText(text: logText)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                        .padding(.horizontal, Metrics.inset)
                        .padding(.bottom, Metrics.inset)
                }
            }
        }
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

    private var logText: String {
        if tab == 0 { return log.ifEmpty(String(localized: "storage/logs/laravel.log boş.")) }
        let tail = state.processes[state.devKey(site)]?.tail(300) ?? ""
        return tail.ifEmpty(String(localized: "Dev sunucusu çalışmıyor."))
    }

    /// Title bar: name, address and path; quiet icon actions; one primary button.
    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                SiteIcon(kind: site.kind, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(site.name).font(.system(size: 20, weight: .semibold)).tracking(-0.3)
                        Pill(text: "\(site.kind.title)")
                    }
                    HStack(spacing: 6) {
                        Button(state.url(for: site).absoluteString) { state.openSite(site) }
                            .buttonStyle(.link).font(.system(size: 12))
                        Detail(text: (site.path.path as NSString).abbreviatingWithTildeInPath)
                            .textSelection(.enabled)
                    }
                }
                Spacer()
                if site.hasPackageJSON || site.kind == .dotnet {
                    IconButton(icon: state.isDevRunning(site) ? "stop.circle" : "play.circle",
                               help: state.isDevRunning(site) ? "Dev sunucusunu durdur" : "Dev sunucusunu başlat (npm run dev)",
                               tint: state.isDevRunning(site) ? .red : nil) { state.toggleDev(site) }
                }
                if state.connection(for: site) != nil {
                    IconButton(icon: "cylinder.split.1x2", help: "Veritabanı") {
                        state.databaseFocus = "site:\(site.name)"
                        state.selection = .database
                    }
                }
                IconButton(icon: "terminal", help: "Terminal") { state.openInTerminal(site.path) }
                IconButton(icon: "folder", help: "Finder") { state.reveal(site.path) }
                IconButton(icon: "chevron.left.forwardslash.chevron.right", help: "Editör") { state.openInEditor(site.path) }
                MoreMenu {
                    if site.linked {
                        Button("Bağlantıyı kaldır (dosyalar kalır)") { state.unlink(site) }
                    }
                    Button("Projeyi sil…", role: .destructive) { showDelete = true }
                }
                Button("Aç") { state.openSite(site) }
                    .primaryButton().controlSize(.small)
            }
            .padding(.horizontal, Metrics.inset)
            .padding(.top, 12).padding(.bottom, 6)
        }
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
