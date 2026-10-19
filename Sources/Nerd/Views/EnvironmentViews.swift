import SwiftUI

// MARK: - PHP

struct PHPView: View {
    @Environment(AppState.self) private var state
    @State private var modulesFor: PHPVersion?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(title: "PHP Sürümleri", subtitle: "Homebrew ile kurulur; her site kendi sürümünü kullanabilir") {
                    Button { state.detectPHP() } label: { Image(systemName: "arrow.clockwise") }
                }
                ForEach(state.phpVersions) { v in row(v) }
                Text("Terminalde varsayılan sürümü kullanmak için ~/.nerd/bin PATH'inizde olmalı.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .sheet(item: $modulesFor) { v in PHPModulesSheet(version: v) }
    }

    private func row(_ v: PHPVersion) -> some View {
        let isDefault = state.defaultPHP?.version == v.version
        let busy = state.busy.contains("php-\(v.version)")
        let usage = state.sites.filter { state.php(for: $0)?.version == v.version }.count
        return HStack(spacing: 12) {
            TextBadge(text: v.version, color: v.installed ? .indigo : .gray)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("PHP \(v.version)")
                    if isDefault { Pill(text: "Varsayılan", color: .green) }
                    if v.installed && state.isFPMRunning(v) { Pill(text: "FPM", color: .blue) }
                }
                Text(v.installed ? "\(v.formula) · \(usage) site" : "Kurulu değil")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if v.installed {
                if !isDefault { Button("Varsayılan yap") { state.setDefaultPHP(v) } }
                Button("php.ini") { state.openInEditor(URL(fileURLWithPath: v.ini)) }
                Button("Modüller") { modulesFor = v }
                Menu {
                    Button("FPM'i yeniden başlat") { state.startFPM(v, restart: true) }
                    Button("Hata logu") { state.openInEditor(Paths.logs.appendingPathComponent("\(v.key)-php-error.log")) }
                    Divider()
                    Button("Kaldır", role: .destructive) { Task { await state.uninstallPHP(v) } }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            } else {
                BusyButton(title: "Kur", icon: "arrow.down.circle", busy: busy) { await state.installPHP(v) }
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        .disabled(busy)
    }
}

struct PHPModulesSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let version: PHPVersion
    @State private var modules: [String] = []
    @State private var ext = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PHP \(version.version) modülleri").font(.headline)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], alignment: .leading) {
                    ForEach(modules, id: \.self) { Text($0).font(.callout.monospaced()) }
                }
            }
            .frame(height: 300)
            HStack {
                TextField("pecl eklentisi (ör. redis, xdebug, imagick)", text: $ext).textFieldStyle(.roundedBorder)
                Button("pecl install") {
                    let e = ext
                    Task { await state.peclInstall(e, for: version); modules = await state.phpModules(version) }
                }
                .disabled(ext.isEmpty)
            }
            HStack { Spacer(); Button("Kapat") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(20)
        .frame(width: 520)
        .task { modules = await state.phpModules(version) }
    }
}

// MARK: - Node

struct NodeView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(title: "Node.js Sürümleri", subtitle: "nodejs.org'dan indirilir, ~/.nerd/node altında tutulur") {
                    Button { state.detectNode(); Task { await state.fetchRemoteNode() } } label: { Image(systemName: "arrow.clockwise") }
                }
                Text("Kurulu").font(.headline)
                if state.nodeVersions.isEmpty { Text("Kurulu Node sürümü yok.").foregroundStyle(.secondary) }
                ForEach(state.nodeVersions) { n in
                    let isDefault = state.defaultNode?.version == n.version
                    HStack(spacing: 10) {
                        TextBadge(text: String(n.major), color: .green, size: 30)
                        Text(n.version).font(.body.monospacedDigit())
                        if !n.managed { Pill(text: "Homebrew") }
                        if isDefault { Pill(text: "Varsayılan", color: .green) }
                        Spacer()
                        if !isDefault { Button("Varsayılan yap") { state.setDefaultNode(n) } }
                        Button("Kaldır", role: .destructive) { Task { await state.uninstallNode(n) } }
                    }
                    .padding(10)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                }

                Text("Kullanılabilir").font(.headline).padding(.top, 8)
                if let err = state.remoteNodeError { Text(err).foregroundStyle(.red).font(.caption) }
                if state.remoteNode.isEmpty && state.remoteNodeError == nil { ProgressView() }
                ForEach(state.remoteNode) { r in
                    let installed = state.nodeVersions.contains { $0.version == r.version }
                    HStack(spacing: 10) {
                        TextBadge(text: String(r.major), color: installed ? .green : .gray, size: 26)
                        Text("Node \(r.major)").bold().frame(width: 70, alignment: .leading)
                        Text(r.version).font(.body.monospacedDigit()).foregroundStyle(.secondary)
                        if let lts = r.lts { Pill(text: "LTS · \(lts)", color: .green) }
                        Text(r.date).font(.caption).foregroundStyle(.tertiary)
                        Spacer()
                        if installed {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            BusyButton(title: "Kur", icon: "arrow.down.circle", busy: state.busy.contains("node-\(r.version)")) {
                                await state.installNode(r.version)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
            .padding(20)
        }
    }
}

// MARK: - Services

struct ServicesView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(title: "Servisler", subtitle: "Homebrew servisleri olarak çalışır (brew services)") {
                    Button { Task { await state.refreshServices() } } label: { Image(systemName: "arrow.clockwise") }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                    ForEach(ServiceDef.catalog) { def in card(def) }
                }
            }
            .padding(20)
        }
        .task { await state.refreshServices() }
    }

    private func card(_ def: ServiceDef) -> some View {
        let status = state.services[def.formula] ?? ServiceStatus(installed: false, status: "none")
        let busy = state.busy.contains(def.formula)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                IconBadge(systemName: def.icon, color: status.installed ? def.color : .gray, size: 34)
                VStack(alignment: .leading) {
                    Text(def.name).font(.headline)
                    Text(def.port.map { "\(def.formula) · port \(String($0))" } ?? def.formula)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                if status.installed {
                    Pill(text: status.isRunning ? "Çalışıyor" : (status.status == "error" ? "Hata" : "Durdu"),
                         color: status.isRunning ? .green : (status.status == "error" ? .red : .secondary))
                }
            }
            if status.installed, !status.isRunning {
                if let other = state.conflicts(of: def).first {
                    Label("Port \(String(def.port ?? 0)) \(other.name) tarafından kullanılıyor; başlatınca o durdurulur.", systemImage: "arrow.left.arrow.right")
                        .font(.caption).foregroundStyle(.secondary)
                } else if status.status == "error" {
                    Label("Son başlatma başarısız. Ayrıntılar Görevler'de.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.red)
                }
            }
            HStack {
                if status.installed {
                    if status.isRunning {
                        Button("Durdur") { Task { await state.serviceAction(def, "stop") } }
                        Button("Yeniden başlat") { Task { await state.serviceAction(def, "restart") } }
                    } else {
                        Button("Başlat") { Task { await state.serviceAction(def, "start") } }.buttonStyle(.borderedProminent)
                            .help(state.conflicts(of: def).isEmpty ? "" : "\(state.conflicts(of: def).map(\.name).joined(separator: ", ")) durdurulacak")
                    }
                    if let ui = def.webUI, status.isRunning {
                        Button("Arayüz") { state.open(URL(string: ui)!) }
                    }
                    Spacer()
                    Menu {
                        Button("Kaldır", role: .destructive) { Task { await state.serviceAction(def, "uninstall") } }
                    } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                } else {
                    Button("Kur") { Task { await state.serviceAction(def, "install") } }
                }
            }
            .disabled(busy)
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Jobs

struct JobsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        HStack(spacing: 0) {
            List(state.jobs, selection: $state.selectedJobID) { job in
                HStack {
                    switch job.state {
                    case .running: ProgressView().controlSize(.small)
                    case .success: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                    }
                    VStack(alignment: .leading) {
                        Text(job.title).lineLimit(1)
                        Text(job.started, style: .time).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tag(job.id)
            }
            .frame(width: 270)
            .overlay { if state.jobs.isEmpty { ContentUnavailableView("Görev yok", systemImage: "list.bullet.rectangle") } }
            Divider()

            Group {
                if let job = state.jobs.first(where: { $0.id == state.selectedJobID }) ?? state.jobs.first {
                    VStack(alignment: .leading) {
                        Text(job.title).font(.headline)
                        LogText(text: job.output).clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(12)
                } else {
                    Color.clear
                }
            }
            .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        Form {
            Section("Park klasörleri") {
                ForEach(state.config.parkedPaths, id: \.self) { p in
                    HStack {
                        Image(systemName: "folder")
                        Text((p as NSString).abbreviatingWithTildeInPath)
                        Spacer()
                        Button { state.config.parkedPaths.removeAll { $0 == p }; state.scanSites() } label: {
                            Image(systemName: "minus.circle")
                        }.buttonStyle(.borderless)
                    }
                }
                Button("Klasör ekle…") {
                    if let url = Panels.chooseFolder(), !state.config.parkedPaths.contains(url.path) {
                        state.config.parkedPaths.append(url.path)
                        state.scanSites()
                        Task { await state.reloadWebServer() }
                    }
                }
            }
            Section("Alan adları ve portlar") {
                Picker("Uzantı (TLD)", selection: $state.config.tld) {
                    Text(".test").tag("test")
                    Text(".localhost (DNS kurulumu gerekmez)").tag("localhost")
                }
                .onChange(of: state.config.tld) {
                    state.startDNSIfNeeded()
                    Task { await state.restartWebServer() }
                }
                TextField("HTTP portu", value: $state.config.httpPort, format: .number.grouping(.never))
                TextField("HTTPS portu", value: $state.config.httpsPort, format: .number.grouping(.never))
                TextField("DNS portu", value: $state.config.dnsPort, format: .number.grouping(.never))
                TextField("SMTP (mail) portu", value: $state.config.mailPort, format: .number.grouping(.never))
                HStack {
                    Button("Uygula ve yeniden başlat") {
                        state.startMailServer()
                        state.dns.stop()
                        state.startDNSIfNeeded()
                        Task { await state.restartWebServer() }
                    }
                    Spacer()
                }
            }
            Section("Sistem entegrasyonu") {
                LabeledContent("DNS çözümleyici (/etc/resolver/\(state.config.tld))") {
                    if state.config.tld == "localhost" {
                        Text("Gerekmiyor").foregroundStyle(.secondary)
                    } else {
                        HStack {
                            Text(state.resolverInstalled ? "Kurulu" : "Kurulu değil").foregroundStyle(state.resolverInstalled ? .green : .orange)
                            Button(state.resolverInstalled ? "Yeniden yaz" : "Kur") { Task { await state.installResolver() } }
                        }
                    }
                }
                LabeledContent("HTTPS kök sertifikası") {
                    Button("Sisteme güven ekle") { Task { await state.trustCaddyCA() } }
                }
                LabeledContent("Terminal PATH (~/.nerd/bin)") {
                    HStack {
                        Text(state.pathConfigured ? "Ekli" : "Ekli değil").foregroundStyle(state.pathConfigured ? .green : .orange)
                        if !state.pathConfigured { Button("~/.zshrc'ye ekle") { state.addNerdToPath() } }
                    }
                }
                LabeledContent("Caddy") {
                    if state.caddyInstalled {
                        Text("Kurulu").foregroundStyle(.green)
                    } else {
                        BusyButton(title: "Kur", busy: state.busy.contains("caddy")) { await state.installCaddy() }
                    }
                }
            }
            Section("Genel") {
                Picker("Görünüm", selection: $state.config.appearance) {
                    ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: state.config.appearance) { state.applyAppearance() }
                Toggle("Açılışta web sunucusunu başlat", isOn: $state.config.autostart)
                TextField("Editör uygulaması", text: $state.config.editor, prompt: Text("Visual Studio Code, Cursor, PhpStorm, Zed…"))
                LabeledContent("Yapılandırma") {
                    Button("~/.nerd klasörünü aç") { state.reveal(Paths.config) }
                }
            }
        }
        .formStyle(.grouped)
    }
}
