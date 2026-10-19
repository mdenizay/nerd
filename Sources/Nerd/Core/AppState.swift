import SwiftUI
import AppKit
import Observation

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard, sites, newProject, php, node, services, database, mail, jobs, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: String(localized: "Genel Bakış")
        case .sites: String(localized: "Siteler")
        case .newProject: String(localized: "Yeni Proje")
        case .php: String(localized: "PHP")
        case .node: String(localized: "Node.js")
        case .services: String(localized: "Servisler")
        case .database: String(localized: "Veritabanı")
        case .mail: String(localized: "Mail")
        case .jobs: String(localized: "Görevler")
        case .settings: String(localized: "Ayarlar")
        }
    }

    var color: Color {
        switch self {
        case .dashboard: .blue
        case .sites: .teal
        case .newProject: .purple
        case .php: .indigo
        case .node: .green
        case .services: .orange
        case .database: .cyan
        case .mail: .pink
        case .jobs: .brown
        case .settings: .gray
        }
    }

    var icon: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .sites: "globe"
        case .newProject: "plus.square"
        case .php: "chevron.left.forwardslash.chevron.right"
        case .node: "hexagon"
        case .services: "server.rack"
        case .database: "cylinder.split.1x2"
        case .mail: "envelope"
        case .jobs: "list.bullet.rectangle"
        case .settings: "gearshape"
        }
    }
}

/// A destructive action waiting for the user's confirmation.
struct ConfirmRequest: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let button: String
    let action: @MainActor () async -> Void
}

@MainActor @Observable
final class AppState {
    static let shared = AppState()

    var config = AppConfig() {
        didSet { saveConfig() }
    }

    var selection: SidebarItem? = .dashboard
    var selectedSiteID: String?
    var selectedJobID: Job.ID?
    var databaseFocus: String?

    var phpVersions: [PHPVersion] = []
    var nodeVersions: [NodeVersion] = []
    var remoteNode: [RemoteNode] = []
    var remoteNodeError: String?
    var sites: [Site] = []
    var services: [String: ServiceStatus] = [:]
    var jobs: [Job] = []
    var processes: [String: ManagedProcess] = [:]

    var caddyInstalled = false
    var webRunning = false
    var webError: String?
    var dnsRunning = false
    var resolverInstalled = false
    var pathConfigured = false
    var busy: Set<String> = []
    var confirmation: ConfirmRequest?
    var mails: [MailMessage] = []
    var readMail: Set<String> = []
    var mailRunning = false

    @ObservationIgnored let dns = DNSServer()
    @ObservationIgnored let smtp = SMTPServer()
    @ObservationIgnored private var booted = false
    @ObservationIgnored private var loadingConfig = false

    // MARK: Lifecycle

    func boot() async {
        guard !booted else { return }
        booted = true
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--page=") }) {
            selection = SidebarItem(rawValue: String(arg.dropFirst(7)))
        }
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--db=") }) {
            databaseFocus = String(arg.dropFirst(5))
        }
        Paths.ensure()
        loadConfig()
        for p in config.parkedPaths {
            try? FileManager.default.createDirectory(atPath: p, withIntermediateDirectories: true)
        }
        refreshEnvironment()
        linkDefaults()
        applyAppearance()
        startDNSIfNeeded()
        startMailServer()
        if config.autostart && caddyInstalled {
            await startWebServer()
        }
        Updater.shared.start()
        await refreshServices()
        await fetchRemoteNode()
    }

    func refreshEnvironment() {
        detectPHP()
        detectNode()
        scanSites()
        caddyInstalled = Shell.which("caddy") != nil
        resolverInstalled = Paths.exists("/etc/resolver/\(config.tld)")
        pathConfigured = Self.shellRCMentionsNerd()
    }

    func shutdown() {
        for p in processes.values { p.stop() }
        dns.stop()
        smtp.stop()
    }

    func applyAppearance() {
        switch config.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    // MARK: Config

    func loadConfigForCLI() { loadConfig() }

    private func loadConfig() {
        guard let data = try? Data(contentsOf: Paths.config),
              let c = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            saveConfig()
            return
        }
        loadingConfig = true
        config = c
        loadingConfig = false
    }

    private func saveConfig() {
        guard !loadingConfig else { return }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(config) {
            try? data.write(to: Paths.config, options: .atomic)
        }
    }

    // MARK: Jobs

    func newJob(_ title: String.LocalizationValue) -> Job {
        newJob(verbatim: String(localized: title))
    }

    func newJob(verbatim title: String) -> Job {
        let job = Job(title: title)
        jobs.insert(job, at: 0)
        if jobs.count > 50 { jobs.removeLast(jobs.count - 50) }
        return job
    }

    /// Runs one step of a job, streaming its output. Returns success.
    @discardableResult
    func step(_ job: Job, _ exe: String, _ args: [String], cwd: URL? = nil, env: [String: String]? = nil) async -> Bool {
        let display = ([(exe as NSString).lastPathComponent] + args.map { $0.contains(" ") ? Shell.quote($0) : $0 }).joined(separator: " ")
        job.note("\n$ \(display)\n")
        let status = await Shell.stream(exe, args, cwd: cwd, env: env) { chunk in
            DispatchQueue.main.async { MainActor.assumeIsolated { job.append(chunk) } }
        }
        if status != 0 { job.note("\n(çıkış kodu \(status))\n") }
        return status == 0
    }

    @discardableResult
    func runJob(_ title: String.LocalizationValue, _ exe: String, _ args: [String], cwd: URL? = nil, env: [String: String]? = nil) async -> Bool {
        let job = newJob(title)
        let ok = await step(job, exe, args, cwd: cwd, env: env)
        job.finish(ok)
        return ok
    }

    @discardableResult
    func brew(_ title: String.LocalizationValue, _ args: [String]) async -> Bool {
        await runJob(title, Paths.brewBin, args)
    }

    func process(_ name: String) -> ManagedProcess {
        if let p = processes[name] { return p }
        let p = ManagedProcess(name: name)
        processes[name] = p
        return p
    }

    // MARK: Helpers

    func open(_ url: URL) { NSWorkspace.shared.open(url) }

    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    func openInEditor(_ url: URL) {
        Task {
            let r = await Shell.run("/usr/bin/open", ["-a", config.editor, url.path])
            if !r.ok { _ = await Shell.run("/usr/bin/open", [url.path]) }
        }
    }

    func openInTerminal(_ url: URL) {
        Task { _ = await Shell.run("/usr/bin/open", ["-a", "Terminal", url.path]) }
    }

    func link(_ target: String, as name: String) {
        let dest = Paths.bin.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.createSymbolicLink(atPath: dest.path, withDestinationPath: target)
    }

    func linkDefaults() {
        if let php = defaultPHP {
            for tool in ["php", "phpize", "php-config", "pecl", "pear"] where Paths.exists("\(php.binDir)/\(tool)") {
                link("\(php.binDir)/\(tool)", as: tool)
            }
        }
        if let node = defaultNode {
            for tool in ["node", "npm", "npx", "corepack"] where Paths.exists("\(node.binDir)/\(tool)") {
                link("\(node.binDir)/\(tool)", as: tool)
            }
        }
    }

    static let pathLine = "export PATH=\"$HOME/.nerd/bin:$PATH\" # Nerd"

    static func shellRCMentionsNerd() -> Bool {
        for rc in [".zshrc", ".zprofile", ".bash_profile", ".bashrc"] {
            let url = Paths.home.appendingPathComponent(rc)
            if let s = try? String(contentsOf: url, encoding: .utf8), s.contains(".nerd/bin") { return true }
        }
        return false
    }

    func addNerdToPath() {
        let url = Paths.home.appendingPathComponent(".zshrc")
        var s = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        if !s.contains(".nerd/bin") {
            if !s.isEmpty && !s.hasSuffix("\n") { s += "\n" }
            s += "\n\(Self.pathLine)\n"
            try? s.write(to: url, atomically: true, encoding: .utf8)
        }
        pathConfigured = Self.shellRCMentionsNerd()
    }
}
