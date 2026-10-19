import SwiftUI
import ServiceManagement

// MARK: - PHP

struct PHPView: View {
    @Environment(AppState.self) private var state
    @State private var modulesFor: PHPVersion?

    var body: some View {
        Form {
            Section {
                Picker("Varsayılan sürüm", selection: Binding(
                    get: { state.defaultPHP?.version ?? "" },
                    set: { v in if let p = state.phpVersion(v) { state.setDefaultPHP(p) } })) {
                    ForEach(state.installedPHP) { Text(verbatim: "PHP \($0.version)").tag($0.version) }
                    if state.installedPHP.isEmpty { Text("Kurulu değil").tag("") }
                }
            } footer: {
                Text("Terminalde varsayılan sürümü kullanmak için ~/.nerd/bin PATH'inizde olmalı.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section("Kurulu") {
                if state.installedPHP.isEmpty { Text("Kurulu PHP sürümü yok").foregroundStyle(.secondary) }
                ForEach(state.installedPHP) { row($0) }
            }
            Section("Kullanılabilir") {
                ForEach(state.phpVersions.filter { !$0.installed }) { row($0) }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem { Button { state.detectPHP() } label: { Label("Yenile", systemImage: "arrow.clockwise") } }
        }
        .sheet(item: $modulesFor) { v in PHPModulesSheet(version: v) }
    }

    private func row(_ v: PHPVersion) -> some View {
        let busy = state.busy.contains("php-\(v.version)")
        let usage = state.sites.filter { state.php(for: $0)?.version == v.version }.count
        return LabeledContent {
            HStack(spacing: 6) {
                if busy { ProgressView().controlSize(.small) }
                if v.installed {
                    if state.isFPMRunning(v) { Chip(text: "FPM", tone: .positive) }
                    if state.isXdebugEnabled(v) { Chip(text: "Xdebug", systemImage: "ladybug") }
                    Menu {
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
                    } label: { Text("Yönet") }
                        .fixedSize()
                } else {
                    BusyButton(title: "Kur", busy: busy) { await state.installPHP(v) }
                }
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(verbatim: "PHP \(v.version)")
                        if state.defaultPHP?.version == v.version { Pill(text: "Varsayılan", accent: true) }
                    }
                    Text(v.installed ? String(localized: "\(v.formula) · \(usage) site") : v.formula)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            } icon: { Tile(systemName: "chevron.left.forwardslash.chevron.right", brand: "php", size: 26) }
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
        Form {
            Section {
                Picker("Varsayılan sürüm", selection: Binding(
                    get: { state.defaultNode?.version ?? "" },
                    set: { v in if let n = state.nodeVersion(v) { state.setDefaultNode(n) } })) {
                    ForEach(state.nodeVersions) { Text(verbatim: $0.label).tag($0.version) }
                    if state.nodeVersions.isEmpty { Text("Kurulu değil").tag("") }
                }
            } footer: {
                Text("nodejs.org'dan indirilir, ~/.nerd/node altında tutulur").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section("Kurulu") {
                if state.nodeVersions.isEmpty { Text("Kurulu Node sürümü yok.").foregroundStyle(.secondary) }
                ForEach(state.nodeVersions) { n in
                    LabeledContent {
                        Button("Kaldır…", role: .destructive) {
                            state.confirmation = ConfirmRequest(
                                title: String(localized: "Node \(n.version) kaldırılsın mı?"),
                                message: String(localized: "Bu Node sürümü diskten silinir."),
                                button: String(localized: "Kaldır")) { await state.uninstallNode(n) }
                        }
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Text(verbatim: n.version)
                                    if state.defaultNode?.version == n.version { Pill(text: "Varsayılan", accent: true) }
                                }
                                Text(verbatim: n.managed ? "nodejs.org" : "Homebrew").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        } icon: { Tile(systemName: "hexagon", brand: "nodedotjs", size: 26) }
                    }
                }
            }
            Section("Kullanılabilir") {
                if let err = state.remoteNodeError { Text(err).foregroundStyle(.red).font(.system(size: 11)) }
                if state.remoteNode.isEmpty && state.remoteNodeError == nil { ProgressView().controlSize(.small) }
                ForEach(state.remoteNode) { r in
                    let installed = state.nodeVersions.contains { $0.version == r.version }
                    LabeledContent {
                        if installed {
                            NerdIcon(name: "checkmark", size: 13).foregroundStyle(.green)
                        } else {
                            BusyButton(title: "Kur", busy: state.busy.contains("node-\(r.version)")) { await state.installNode(r.version) }
                        }
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Text(verbatim: "Node \(r.major)")
                                    if let lts = r.lts { Pill(text: "LTS · \(lts)") }
                                }
                                Text(verbatim: "\(r.version) · \(r.date)").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        } icon: { Tile(systemName: "hexagon", brand: "nodedotjs", size: 26) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem {
                Button { state.detectNode(); Task { await state.fetchRemoteNode() } } label: { Label("Yenile", systemImage: "arrow.clockwise") }
            }
        }
    }
}

// MARK: - .NET

struct DotnetView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Form {
            Section {
                Picker("Varsayılan sürüm", selection: Binding(
                    get: { state.defaultDotnet?.major ?? "" },
                    set: { v in if let d = state.dotnetVersion(v) { state.setDefaultDotnet(d) } })) {
                    ForEach(state.installedDotnet) { Text(verbatim: ".NET \($0.major)").tag($0.major) }
                    if state.installedDotnet.isEmpty { Text("Kurulu değil").tag("") }
                }
            } footer: {
                Text("Homebrew ile kurulan SDK'lar; ASP.NET projeleri dotnet watch ile çalışır").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section("Kurulu") {
                if state.installedDotnet.isEmpty { Text("Kurulu .NET SDK yok.").foregroundStyle(.secondary) }
                ForEach(state.installedDotnet) { row($0) }
            }
            Section("Kullanılabilir") {
                ForEach(state.dotnetVersions.filter { !$0.installed }) { row($0) }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem { Button { state.detectDotnet() } label: { Label("Yenile", systemImage: "arrow.clockwise") } }
        }
    }

    private func row(_ v: DotnetVersion) -> some View {
        let busy = state.busy.contains("dotnet-\(v.major)")
        let usage = state.sites.filter { $0.kind == .dotnet && state.dotnet(for: $0)?.major == v.major }.count
        return LabeledContent {
            HStack(spacing: 6) {
                if busy { ProgressView().controlSize(.small) }
                if v.installed {
                    Button("Kaldır…", role: .destructive) {
                        state.confirmation = ConfirmRequest(
                            title: String(localized: ".NET \(v.major) kaldırılsın mı?"),
                            message: String(localized: "Homebrew'dan \(v.formula) kaldırılır."),
                            button: String(localized: "Kaldır")) { await state.uninstallDotnet(v) }
                    }
                } else {
                    BusyButton(title: "Kur", busy: busy) { await state.installDotnet(v) }
                }
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(verbatim: ".NET \(v.major)")
                        if state.defaultDotnet?.major == v.major { Pill(text: "Varsayılan", accent: true) }
                    }
                    Text(v.installed ? String(localized: "\(v.formula) · \(usage) site") : v.formula)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            } icon: { Tile(systemName: "number", brand: "dotnet", size: 26) }
        }
        .disabled(busy)
    }
}

// MARK: - Services

struct ServicesView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Form {
            let installed = ServiceDef.catalog.filter { state.services[$0.formula]?.installed == true }
            let available = ServiceDef.catalog.filter { state.services[$0.formula]?.installed != true }
            if !installed.isEmpty {
                Section {
                    ForEach(installed) { row($0) }
                } header: {
                    Text("Kurulu")
                } footer: {
                    Text("Homebrew servisleri olarak çalışır (brew services)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            if !available.isEmpty {
                Section("Kullanılabilir") {
                    ForEach(available) { row($0) }
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem { Button { Task { await state.refreshServices() } } label: { Label("Yenile", systemImage: "arrow.clockwise") } }
        }
        .task { await state.refreshServices() }
    }

    private func row(_ def: ServiceDef) -> some View {
        let status = state.services[def.formula] ?? ServiceStatus(installed: false, status: "none")
        let busy = state.busy.contains(def.formula)
        return LabeledContent {
            HStack(spacing: 8) {
                if busy { ProgressView().controlSize(.small) }
                if status.installed {
                    if let ui = def.webUI, status.isRunning {
                        Button("Arayüz") { state.open(URL(string: ui)!) }
                    }
                    Menu {
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
                    } label: { NerdIcon(name: "ellipsis", size: 13) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    Toggle("", isOn: Binding(get: { status.isRunning },
                                             set: { on in Task { await state.serviceAction(def, on ? "start" : "stop") } }))
                        .toggleStyle(.switch).labelsHidden()
                } else {
                    Button("Kur") { Task { await state.serviceAction(def, "install") } }
                }
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(def.name)
                        if status.isRunning { Chip(text: "Çalışıyor", tone: .positive) }
                        if status.installed, !status.isRunning, status.status == "error" { Chip(text: "Hata", tone: .negative) }
                    }
                    Text(verbatim: def.port.map { "\(def.formula) · :\($0)" } ?? def.formula)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    if status.installed, !status.isRunning, let other = state.conflicts(of: def).first {
                        Text("Port \(String(def.port ?? 0)) \(other.name) tarafından kullanılıyor; başlatınca o durdurulur.")
                            .font(.system(size: 11)).foregroundStyle(.orange)
                    }
                }
            } icon: { Tile(systemName: def.icon, brand: def.brand, size: 26) }
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
                LaunchAtLoginToggle()
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

struct LaunchAtLoginToggle: View {
    @State private var enabled = LoginItem.enabled
    @State private var needsApproval = LoginItem.needsApproval
    @State private var error: String?

    var body: some View {
        Toggle("Oturum açılınca Nerd'ü başlat", isOn: Binding(get: { enabled || needsApproval }, set: { on in
            do { try LoginItem.set(on); error = nil } catch { self.error = error.localizedDescription }
            refresh()
        }))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        if needsApproval {
            HStack {
                Text("Sistem Ayarları'nda Nerd'e giriş öğesi izni verin.").font(.caption).foregroundStyle(.orange)
                Spacer()
                Button("Giriş Öğeleri'ni aç") { SMAppService.openSystemSettingsLoginItems() }
            }
        }
        if let error { Text(error).font(.caption).foregroundStyle(.red) }
    }

    private func refresh() {
        enabled = LoginItem.enabled
        needsApproval = LoginItem.needsApproval
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
