import SwiftUI

// MARK: - PHP

struct PHPView: View {
    @Environment(AppState.self) private var state
    @State private var modulesFor: PHPVersion?

    var body: some View {
        VStack(spacing: 0) {
            Header(title: "PHP", subtitle: "Homebrew ile kurulur; her site kendi sürümünü kullanabilir") {
                Button { state.detectPHP() } label: { NerdIcon(name: "arrow.clockwise") }
            }
            ScrollView {
                VStack(spacing: 0) {
                    SectionLabel("Kurulu")
                    ListCard {
                        ForEach(state.phpVersions.filter(\.installed)) { row($0) }
                        if state.installedPHP.isEmpty {
                            Row { Text("Kurulu PHP sürümü yok").foregroundStyle(.secondary) }
                        }
                    }
                    SectionLabel("Kullanılabilir")
                    ListCard {
                        ForEach(state.phpVersions.filter { !$0.installed }) { row($0) }
                    }
                    Text("Terminalde varsayılan sürümü kullanmak için ~/.nerd/bin PATH'inizde olmalı.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Metrics.inset)
                }
            }
        }
        .sheet(item: $modulesFor) { v in PHPModulesSheet(version: v) }
    }

    private func row(_ v: PHPVersion) -> some View {
        let isDefault = state.defaultPHP?.version == v.version
        let busy = state.busy.contains("php-\(v.version)")
        let usage = state.sites.filter { state.php(for: $0)?.version == v.version }.count
        return Row {
            Tile(systemName: "chevron.left.forwardslash.chevron.right", brand: "php", size: 18)
            Text(verbatim: "PHP \(v.version)").monospacedDigit()
            if isDefault { Pill(text: "Varsayılan", accent: true) }
            if v.installed && state.isFPMRunning(v) { Chip(text: "FPM", tone: .positive) }
            if v.installed && state.isXdebugEnabled(v) { Chip(text: "Xdebug", systemImage: "ladybug") }
            if v.installed { Detail(text: String(localized: "\(v.formula) · \(usage) site")) }
            Spacer()
            if busy { ProgressView().controlSize(.mini) }
            if v.installed {
                if !isDefault {
                    Button("Varsayılan yap") { state.setDefaultPHP(v) }.controlSize(.small)
                }
                MoreMenu {
                    Button("php.ini") { state.openInEditor(URL(fileURLWithPath: v.ini)) }
                    Button("Modüller") { modulesFor = v }
                    Button(state.isXdebugEnabled(v) ? "Xdebug'ı kapat" : "Xdebug'ı aç") {
                        Task { await state.setXdebug(v, enabled: !state.isXdebugEnabled(v)) }
                    }
                    Button("FPM'i yeniden başlat") { state.startFPM(v, restart: true) }
                    Button("Hata logu") { state.openInEditor(Paths.logs.appendingPathComponent("\(v.key)-php-error.log")) }
                    Divider()
                    Button("Kaldır…", role: .destructive) {
                        state.confirmation = ConfirmRequest(
                            title: String(localized: "PHP \(v.version) kaldırılsın mı?"),
                            message: String(localized: "Homebrew'dan \(v.formula) kaldırılır. Bu sürümü kullanan siteler varsayılan PHP'ye geçer."),
                            button: String(localized: "Kaldır")) { await state.uninstallPHP(v) }
                    }
                }
            } else {
                BusyButton(title: "Kur", busy: busy) { await state.installPHP(v) }.controlSize(.small)
            }
        }
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
            Text("PHP \(version.version) modülleri").font(.system(size: 13, weight: .semibold))
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], alignment: .leading, spacing: 4) {
                    ForEach(modules, id: \.self) { Text($0).font(.system(size: 12, design: .monospaced)) }
                }
            }
            .frame(height: 260)
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
        .controlSize(.small)
        .padding(16)
        .frame(width: 480)
        .task { modules = await state.phpModules(version) }
    }
}

// MARK: - Node

struct NodeView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            Header(title: "Node.js", subtitle: "nodejs.org'dan indirilir, ~/.nerd/node altında tutulur") {
                Button { state.detectNode(); Task { await state.fetchRemoteNode() } } label: { NerdIcon(name: "arrow.clockwise") }
            }
            ScrollView {
                VStack(spacing: 0) {
                    SectionLabel("Kurulu")
                    ListCard {
                    if state.nodeVersions.isEmpty {
                        Row { Text("Kurulu Node sürümü yok.").foregroundStyle(.secondary) }
                    }
                    ForEach(state.nodeVersions) { n in
                        let isDefault = state.defaultNode?.version == n.version
                        Row {
                            Tile(systemName: "hexagon.fill", brand: "nodedotjs", size: 18)
                            Text(verbatim: n.version).monospacedDigit()
                            if isDefault { Pill(text: "Varsayılan", accent: true) }
                            if !n.managed { Detail(text: "Homebrew") }
                            Spacer()
                            if !isDefault {
                                Button("Varsayılan yap") { state.setDefaultNode(n) }.controlSize(.small)
                            }
                            MoreMenu {
                                Button("Kaldır…", role: .destructive) {
                                    state.confirmation = ConfirmRequest(
                                        title: String(localized: "Node \(n.version) kaldırılsın mı?"),
                                        message: String(localized: "Bu Node sürümü diskten silinir."),
                                        button: String(localized: "Kaldır")) { await state.uninstallNode(n) }
                                }
                            }
                        }
                    }

                    }
                    SectionLabel("Kullanılabilir")
                    ListCard {
                    if let err = state.remoteNodeError {
                        Row { Text(err).foregroundStyle(.red).font(.system(size: 12)) }
                    }
                    if state.remoteNode.isEmpty && state.remoteNodeError == nil {
                        Row { ProgressView().controlSize(.small) }
                    }
                    ForEach(state.remoteNode) { r in
                        let installed = state.nodeVersions.contains { $0.version == r.version }
                        Row {
                            Tile(systemName: "hexagon", brand: "nodedotjs", size: 18)
                            Text(verbatim: "Node \(r.major)").frame(width: 64, alignment: .leading)
                            Detail(text: r.version)
                            if let lts = r.lts { Pill(text: "LTS · \(lts)") }
                            Spacer()
                            Detail(text: r.date)
                            if installed {
                                Glyph(systemName: "checkmark", color: .green)
                            } else {
                                BusyButton(title: "Kur", busy: state.busy.contains("node-\(r.version)")) {
                                    await state.installNode(r.version)
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                    }
                }
                .padding(.bottom, 16)
            }
        }
    }
}

// MARK: - .NET

struct DotnetView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            Header(title: ".NET", subtitle: "Homebrew ile kurulan SDK'lar; ASP.NET projeleri dotnet watch ile çalışır") {
                Button { state.detectDotnet() } label: { NerdIcon(name: "arrow.clockwise") }
            }
            ScrollView {
                VStack(spacing: 0) {
                    SectionLabel("Kurulu")
                    ListCard {
                        ForEach(state.installedDotnet) { row($0) }
                        if state.installedDotnet.isEmpty {
                            Row { Text("Kurulu .NET SDK yok.").foregroundStyle(.secondary) }
                        }
                    }
                    SectionLabel("Kullanılabilir")
                    ListCard {
                        ForEach(state.dotnetVersions.filter { !$0.installed }) { row($0) }
                    }
                }
                .padding(.bottom, 16)
            }
        }
    }

    private func row(_ v: DotnetVersion) -> some View {
        let isDefault = state.defaultDotnet?.major == v.major
        let busy = state.busy.contains("dotnet-\(v.major)")
        let usage = state.sites.filter { $0.kind == .dotnet && state.dotnet(for: $0)?.major == v.major }.count
        return Row {
            Tile(systemName: "number", brand: "dotnet", size: 18)
            Text(verbatim: ".NET \(v.major)").monospacedDigit()
            if isDefault { Pill(text: "Varsayılan", accent: true) }
            if v.installed { Detail(text: String(localized: "\(v.formula) · \(usage) site")) } else { Detail(text: v.formula) }
            Spacer()
            if busy { ProgressView().controlSize(.mini) }
            if v.installed {
                if !isDefault {
                    Button("Varsayılan yap") { state.setDefaultDotnet(v) }.controlSize(.small)
                }
                MoreMenu {
                    Button("Kaldır…", role: .destructive) {
                        state.confirmation = ConfirmRequest(
                            title: String(localized: ".NET \(v.major) kaldırılsın mı?"),
                            message: String(localized: "Homebrew'dan \(v.formula) kaldırılır."),
                            button: String(localized: "Kaldır")) { await state.uninstallDotnet(v) }
                    }
                }
            } else {
                BusyButton(title: "Kur", busy: busy) { await state.installDotnet(v) }.controlSize(.small)
            }
        }
        .disabled(busy)
    }
}

// MARK: - Services

struct ServicesView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            Header(title: "Servisler", subtitle: "Homebrew servisleri olarak çalışır (brew services)") {
                Button { Task { await state.refreshServices() } } label: { NerdIcon(name: "arrow.clockwise") }
            }
            ScrollView {
                VStack(spacing: 0) {
                    let installed = ServiceDef.catalog.filter { state.services[$0.formula]?.installed == true }
                    let available = ServiceDef.catalog.filter { state.services[$0.formula]?.installed != true }
                    if !installed.isEmpty {
                        SectionLabel("Kurulu")
                        ListCard { ForEach(installed) { row($0) } }
                    }
                    if !available.isEmpty {
                        SectionLabel("Kullanılabilir")
                        ListCard { ForEach(available) { row($0) } }
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .task { await state.refreshServices() }
    }

    private func row(_ def: ServiceDef) -> some View {
        let status = state.services[def.formula] ?? ServiceStatus(installed: false, status: "none")
        let busy = state.busy.contains(def.formula)
        let failed = status.status == "error"
        return Row {
            Tile(systemName: def.icon, brand: def.brand, size: 18)
            Text(def.name)
            if status.isRunning { Chip(text: "Çalışıyor", tone: .positive) }
            Detail(text: def.port.map { "\(def.formula) · :\($0)" } ?? def.formula)
            if status.installed, !status.isRunning {
                if let other = state.conflicts(of: def).first {
                    Glyph(systemName: "arrow.left.arrow.right", size: 10)
                        .help("Port \(String(def.port ?? 0)) \(other.name) tarafından kullanılıyor; başlatınca o durdurulur.")
                } else if failed {
                    Glyph(systemName: "exclamationmark.triangle", color: .red, size: 10)
                        .help("Son başlatma başarısız. Ayrıntılar Görevler'de.")
                }
            }
            Spacer()
            if busy { ProgressView().controlSize(.mini) }
            if status.installed {
                if let ui = def.webUI, status.isRunning {
                    Button("Arayüz") { state.open(URL(string: ui)!) }.buttonStyle(.link).font(.system(size: 12))
                }
                Toggle("", isOn: Binding(get: { status.isRunning },
                                         set: { on in Task { await state.serviceAction(def, on ? "start" : "stop") } }))
                    .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                MoreMenu {
                    if status.isRunning {
                        Button("Yeniden başlat") { Task { await state.serviceAction(def, "restart") } }
                        Divider()
                    }
                    Button("Kaldır…", role: .destructive) {
                        state.confirmation = ConfirmRequest(
                            title: String(localized: "\(def.name) kaldırılsın mı?"),
                            message: String(localized: "Homebrew'dan \(def.formula) kaldırılır. Veri klasörü (\(Paths.brew)/var) silinmez; yeniden kurunca veriler geri gelir."),
                            button: String(localized: "Kaldır")) { await state.serviceAction(def, "uninstall") }
                    }
                }
            } else {
                Button("Kur") { Task { await state.serviceAction(def, "install") } }.controlSize(.small)
            }
        }
        .disabled(busy)
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
                    case .success: NerdIcon(name: "checkmark.circle.fill").foregroundStyle(.green)
                    case .failed: NerdIcon(name: "xmark.octagon.fill").foregroundStyle(.red)
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
                        Text(job.title).font(.system(size: 13, weight: .semibold))
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
                        NerdIcon(name: "folder")
                        Text((p as NSString).abbreviatingWithTildeInPath)
                        Spacer()
                        Button { state.config.parkedPaths.removeAll { $0 == p }; state.scanSites() } label: {
                            NerdIcon(name: "minus.circle")
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
            Section {
                MCPSettings()
            } header: {
                Text(verbatim: "MCP")
            } footer: {
                Text("Claude Code, Cursor gibi yapay zekâ araçları Nerd üzerinden siteleri, servisleri, logları, veritabanını ve mailleri görebilir.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section("Güncellemeler") {
                UpdateSettings()
            }
            Section("Genel") {
                LanguagePicker()
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

// MARK: - Updates & language

struct UpdateSettings: View {
    @State private var updater = Updater.shared

    var body: some View {
        LabeledContent("Sürüm", value: Updater.version)
        if updater.available {
            Toggle("Güncellemeleri otomatik indir", isOn: $updater.automatic)
            HStack {
                switch updater.state {
                case .idle: Text("Henüz kontrol edilmedi").foregroundStyle(.secondary)
                case .checking: ProgressView().controlSize(.small); Text("Kontrol ediliyor…").foregroundStyle(.secondary)
                case .upToDate: Text("Nerd güncel").foregroundStyle(.secondary)
                case .downloading(let v): ProgressView().controlSize(.small); Text("\(v) indiriliyor…").foregroundStyle(.secondary)
                case .ready(let v): Text("Nerd \(v) yüklemeye hazır").foregroundStyle(.green)
                case .failed(let message): Text(message).foregroundStyle(.red).lineLimit(2)
                }
                Spacer()
                if updater.readyVersion != nil {
                    Button("Yeniden başlat ve güncelle") { updater.installAndRelaunch() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Şimdi kontrol et") { updater.check() }
                        .disabled(updater.state == .checking)
                }
            }
        } else {
            Text("Yerel derlemeler kendini güncellemez; Homebrew ya da GitHub sürümlerini kullanın.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct LanguagePicker: View {
    @State private var language = LanguagePicker.current
    @State private var changed = false

    static var current: String {
        (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String]).flatMap { list in
            UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] != nil ? list.first : nil
        }.map { $0.hasPrefix("tr") ? "tr" : "en" } ?? "system"
    }

    var body: some View {
        Picker("Dil", selection: $language) {
            Text("Sistem").tag("system")
            Text(verbatim: "English").tag("en")
            Text(verbatim: "Türkçe").tag("tr")
        }
        .onChange(of: language) {
            if language == "system" {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.set([language], forKey: "AppleLanguages")
            }
            changed = true
        }
        if changed {
            HStack {
                Text("Dil, uygulama yeniden başlayınca değişir.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Şimdi yeniden başlat") { Updater.restart() }
            }
        }
    }
}

// MARK: - MCP

struct MCPSettings: View {
    @Environment(AppState.self) private var state
    @State private var copied: String?

    private var command: String { "claude mcp add --scope user nerd -- \"\(state.mcpCommand)\" mcp" }
    private var json: String {
        """
        {
          "mcpServers": {
            "nerd": { "command": "\(state.mcpCommand)", "args": ["mcp"] }
          }
        }
        """
    }

    var body: some View {
        LabeledContent("Claude Code") {
            BusyButton(title: "Claude Code'a ekle", busy: state.jobs.first?.state == .running && state.jobs.first?.title.contains("Claude") == true) {
                await state.addToClaudeCode()
                state.selection = .jobs
            }
        }
        snippet(command, id: "cmd")
        snippet(json, id: "json")
    }

    private func snippet(_ text: String, id: String) -> some View {
        HStack(alignment: .top) {
            Text(verbatim: text)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = id
            } label: {
                NerdIcon(name: copied == id ? "checkmark" : "doc.on.doc", size: 12)
            }
            .buttonStyle(.borderless)
            .help("Kopyala")
        }
    }
}
