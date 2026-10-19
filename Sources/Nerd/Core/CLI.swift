import Foundation
import AppKit

/// The `nerd` terminal command (~/.nerd/bin/nerd runs `Nerd --cli …`). Commands
/// change ~/.nerd/config.json and ask a running Nerd to reload it; when Nerd is
/// closed the change applies on its next launch.
@MainActor
enum CLI {
    static let request = Notification.Name("com.mdenizay.nerd.cli.request")
    static let response = Notification.Name("com.mdenizay.nerd.cli.response")

    static let commands: Set<String> = [
        "park", "forget", "parked", "link", "unlink", "links", "sites", "open", "secure", "unsecure",
        "use", "isolate", "unisolate", "php", "composer", "logs", "proxy", "unproxy", "docker", "mcp",
        "startup", "help", "version",
    ]

    static var wrapperURL: URL { Paths.bin.appendingPathComponent("nerd") }

    private static var state: AppState { AppState.shared }
    private static var cwd: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath).resolvingSymlinksInPath()
    }

    // MARK: Entry

    static func run(_ argv: [String]) -> Int32 {
        guard let command = argv.first else { print(help); return 0 }
        var args = Array(argv.dropFirst())
        if command == "mcp" { MCPServer.run() }
        if command == "docker" {
            return state.cliDocker(args.first.flatMap { $0.hasPrefix("--") ? nil : $0 } ?? cwd.path)
        }
        state.prepareHeadless()
        switch command {
        case "help", "-h", "--help":
            print(help)
            return 0
        case "version", "-v", "--version":
            print("Nerd \(Updater.version)")
            return 0
        case "park": return park(args.first)
        case "forget": return forget(args.first)
        case "parked":
            state.config.parkedPaths.forEach { print(tilde($0)) }
            return 0
        case "link": return link(args.first)
        case "unlink": return unlink(args.first)
        case "links": return list(state.sites.filter(\.linked))
        case "sites": return list(state.sites)
        case "open": return open(args.first)
        case "secure", "unsecure": return secure(args.first, on: command == "secure")
        case "use" where args.isEmpty:
            return fail(String(localized: "Kullanım: nerd use php@8.4 [--global]"))
        case "use", "isolate":
            let global = args.contains("--global") || args.contains("-g")
            args.removeAll { $0 == "--global" || $0 == "-g" }
            return use(args.first, global: global && command == "use")
        case "unisolate": return unisolate(args.first)
        case "php": return php(args)
        case "composer": return composer(args)
        case "logs": return logs(args)
        case "proxy": return proxy(args)
        case "unproxy": return unproxy(args.first)
        case "startup": return startup(args.first)
        default:
            fail(String(localized: "Bilinmeyen komut: \(command)"))
            print(help)
            return 1
        }
    }

    // MARK: Folders & sites

    private static func park(_ dir: String?) -> Int32 {
        let path = absolute(dir)
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        if !state.config.parkedPaths.contains(path) { state.config.parkedPaths.append(path) }
        state.scanSites()
        let count = state.sites.filter { $0.path.deletingLastPathComponent().path == path }.count
        ok(String(localized: "\(tilde(path)) park edildi; içindeki her klasör bir site (\(count) site)."))
        return notifyApp()
    }

    private static func forget(_ dir: String?) -> Int32 {
        let path = absolute(dir)
        guard state.config.parkedPaths.contains(path) else {
            return fail(String(localized: "\(tilde(path)) park edilmiş bir klasör değil."))
        }
        state.config.parkedPaths.removeAll { $0 == path }
        ok(String(localized: "\(tilde(path)) artık park klasörü değil."))
        return notifyApp()
    }

    private static func link(_ name: String?) -> Int32 {
        let url = cwd
        state.linkFolder(url, name: name)
        guard let site = state.sites.first(where: { $0.linked && $0.path.path == url.path }) else {
            return fail(String(localized: "Bu klasör bağlanamadı."))
        }
        ok(String(localized: "\(tilde(url.path)) → \(state.url(for: site).absoluteString)"))
        return notifyApp()
    }

    private static func unlink(_ name: String?) -> Int32 {
        guard let site = resolve(name) else { return 1 }
        guard site.linked else {
            return fail(String(localized: "\(site.name) park klasöründen geliyor; bağlı bir site değil."))
        }
        state.unlink(site)
        ok(String(localized: "\(site.name) kaldırıldı (dosyalar yerinde)."))
        return notifyApp()
    }

    private static func list(_ sites: [Site]) -> Int32 {
        let rows = sites.map { site -> [String] in
            [site.name, state.url(for: site).absoluteString, runtime(site),
             site.proxyTarget.map { "→ \($0)" } ?? tilde(site.path.path)]
        }
        table([String(localized: "SİTE"), String(localized: "ADRES"), String(localized: "TÜR"), String(localized: "KLASÖR / HEDEF")], rows)
        return 0
    }

    private static func runtime(_ site: Site) -> String {
        switch site.kind {
        case .laravel, .php: "\(site.kind.title) · PHP \(state.php(for: site)?.version ?? "—")\(site.config.php != nil ? " *" : "")"
        case .dotnet: ".NET \(state.dotnet(for: site)?.major ?? "—")"
        default: site.kind.title
        }
    }

    private static func open(_ name: String?) -> Int32 {
        guard let site = resolve(name) else { return 1 }
        // A running Nerd also boots dev servers (Next.js, Astro, .NET) before opening
        if appRunning, send("open", site: site.name) != nil { return 0 }
        if !appRunning {
            info(String(localized: "Nerd başlatılıyor…"))
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: launchConfiguration) { _, _ in }
            let deadline = Date().addingTimeInterval(20)
            while Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                if appRunning, send("open", site: site.name, timeout: 2) != nil { return 0 }
            }
        }
        NSWorkspace.shared.open(state.url(for: site))
        return 0
    }

    private static var launchConfiguration: NSWorkspace.OpenConfiguration {
        let c = NSWorkspace.OpenConfiguration()
        c.activates = false
        return c
    }

    private static func secure(_ name: String?, on: Bool) -> Int32 {
        guard let site = resolve(name) else { return 1 }
        state.updateSite(site.name) { $0.secure = on }
        if let site = state.site(site.name) {
            ok(on ? String(localized: "\(site.name) HTTPS: \(state.url(for: site).absoluteString)")
                  : String(localized: "\(site.name) HTTP: \(state.url(for: site).absoluteString)"))
        }
        return notifyApp()
    }

    // MARK: PHP

    private static func use(_ spec: String?, global: Bool) -> Int32 {
        var version: String?
        if let spec {
            let v = spec.lowercased().replacingOccurrences(of: "php@", with: "").replacingOccurrences(of: "php", with: "")
            guard AppState.knownPHP.contains(v) else {
                return fail(String(localized: "Bilinmeyen PHP sürümü: \(spec). Seçenekler: \(AppState.knownPHP.joined(separator: ", "))"))
            }
            version = v
        }
        if global {
            guard let v = version, let php = state.phpVersion(v) else {
                return fail(String(localized: "PHP \(version ?? "?") kurulu değil. Nerd'de PHP bölümünden kurun."))
            }
            state.config.defaultPHP = php.version
            state.linkDefaults()
            ok(String(localized: "Varsayılan PHP artık \(php.version)."))
            return notifyApp()
        }
        guard let site = resolve(nil) else { return 1 }
        let v = version ?? state.defaultPHP?.version
        guard let v else { return fail(String(localized: "Kurulu PHP yok.")) }
        if state.phpVersion(v) == nil {
            warn(String(localized: "PHP \(v) kurulu değil; kurulana kadar varsayılan sürüm kullanılır."))
        }
        if site.kind.isProxied || site.isProxy {
            warn(String(localized: "\(site.name) PHP ile çalışmıyor; ayar yine de kaydedildi."))
        }
        state.updateSite(site.name) { $0.php = v }
        ok(String(localized: "\(site.name) artık PHP \(v) kullanıyor."))
        return notifyApp()
    }

    private static func unisolate(_ name: String?) -> Int32 {
        guard let site = resolve(name) else { return 1 }
        state.updateSite(site.name) { $0.php = nil }
        ok(String(localized: "\(site.name) varsayılan PHP'yi (\(state.defaultPHP?.version ?? "—")) kullanıyor."))
        return notifyApp()
    }

    /// The PHP of the site the terminal is in, or the default one.
    private static var currentPHP: (PHPVersion, Site?)? {
        let site = siteAt(cwd)
        guard let php = site.flatMap({ state.php(for: $0) }) ?? state.defaultPHP else {
            fail(String(localized: "Kurulu PHP yok."))
            return nil
        }
        return (php, site)
    }

    private static func php(_ args: [String]) -> Int32 {
        guard let (php, site) = currentPHP else { return 1 }
        exec(php.bin, args, env: terminalEnv(php, site))
    }

    private static func composer(_ args: [String]) -> Int32 {
        guard let (php, site) = currentPHP else { return 1 }
        guard let composer = Shell.which("composer") else {
            return fail(String(localized: "composer bulunamadı. Kurmak için: brew install composer"))
        }
        exec(php.bin, [composer] + args, env: terminalEnv(php, site))
    }

    /// The user's own environment (colours, TERM) with the site's PHP and Node first in PATH.
    private static func terminalEnv(_ php: PHPVersion, _ site: Site?) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        var prepend = [php.binDir]
        if let node = site.flatMap({ state.node(for: $0) }) { prepend.append(node.binDir) }
        env["PATH"] = (prepend + [env["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
        return env
    }

    // MARK: Logs

    private static func logs(_ args: [String]) -> Int32 {
        let follow = args.contains("-f") || args.contains("--follow")
        guard let site = resolve(args.first { !$0.hasPrefix("-") }) else { return 1 }
        let laravel = site.path.appendingPathComponent("storage/logs/laravel.log")
        let dev = Paths.logs.appendingPathComponent("\(state.devKey(site)).log")
        guard let file = [site.isLaravel && !site.isProxy ? laravel : nil, dev].compactMap({ $0 }).first(where: { Paths.exists($0.path) }) else {
            return fail(String(localized: "\(site.name) için henüz log yok."))
        }
        info(tilde(file.path))
        exec("/usr/bin/tail", ["-n", "100"] + (follow ? ["-F"] : []) + [file.path], env: ProcessInfo.processInfo.environment)
    }

    // MARK: Proxy sites

    private static func proxy(_ args: [String]) -> Int32 {
        guard args.count >= 2 else {
            return fail(String(localized: "Kullanım: nerd proxy <ad> <port|adres> [--secure]"))
        }
        if let error = state.addProxy(args[0], target: args[1]) { return fail(error) }
        let name = AppState.slug(args[0])
        if args.contains("--secure") { state.updateSite(name) { $0.secure = true } }
        guard let site = state.site(name) else { return 1 }
        ok("\(state.url(for: site).absoluteString) → \(site.proxyTarget ?? "")")
        return notifyApp()
    }

    private static func unproxy(_ name: String?) -> Int32 {
        guard let name, let site = state.site(AppState.slug(name)), site.isProxy else {
            return fail(String(localized: "Böyle bir proxy yok: \(name ?? "")"))
        }
        state.removeProxy(site.name)
        ok(String(localized: "\(site.name) proxy'si kaldırıldı."))
        return notifyApp()
    }

    // MARK: Launch at login

    private static func startup(_ arg: String?) -> Int32 {
        do {
            switch arg {
            case "on": try LoginItem.set(true)
            case "off": try LoginItem.set(false)
            case nil, "status": break
            default: return fail(String(localized: "Kullanım: nerd startup [on|off|status]"))
            }
        } catch {
            return fail(error.localizedDescription)
        }
        print(LoginItem.statusText)
        return 0
    }

    // MARK: Talking to the running app

    static var appRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.mdenizay.nerd")
            .contains { $0.processIdentifier != getpid() && $0.activationPolicy != .prohibited }
    }

    /// Asks the running app to act; returns its reply, or nil when it did not answer.
    static func send(_ action: String, site: String? = nil, timeout: TimeInterval = 6) -> [AnyHashable: Any]? {
        let center = DistributedNotificationCenter.default()
        let token = UUID().uuidString
        var reply: [AnyHashable: Any]?
        let observer = center.addObserver(forName: response, object: token, queue: nil) { note in
            reply = note.userInfo ?? [:]
        }
        defer { center.removeObserver(observer) }
        var info = ["action": action]
        if let site { info["site"] = site }
        center.postNotificationName(request, object: token, userInfo: info, deliverImmediately: true)
        let deadline = Date().addingTimeInterval(timeout)
        while reply == nil && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
        return reply
    }

    /// Applies the saved config: through the running app, or straight to Caddy if only it answers.
    private static func notifyApp() -> Int32 {
        if appRunning, let reply = send("reload") {
            if let error = reply["error"] as? String, !error.isEmpty { return fail(error) }
            info(String(localized: "Nerd güncellendi."))
            return 0
        }
        if AppState.isPortOpen(2019), let caddy = Shell.which("caddy") {
            try? state.caddyfile().write(to: Paths.caddyfile, atomically: true, encoding: .utf8)
            let (status, output) = runSync(caddy, ["reload", "--config", Paths.caddyfile.path, "--adapter", "caddyfile", "--address", "localhost:2019"])
            if status != 0 { return fail(String(localized: "Caddy yeniden yüklenemedi:") + "\n" + output) }
            info(String(localized: "Nerd yanıt vermedi; Caddy doğrudan yeniden yüklendi."))
            return 0
        }
        info(String(localized: "Nerd çalışmıyor; değişiklik Nerd açılınca geçerli olur."))
        return 0
    }

    // MARK: Helpers

    /// A site by name, or the one the terminal is in.
    private static func resolve(_ name: String?) -> Site? {
        if let name {
            if let site = state.site(name) ?? state.site(AppState.slug(name)) { return site }
            fail(String(localized: "Böyle bir site yok: \(name)"))
            return nil
        }
        if let site = siteAt(cwd) { return site }
        fail(String(localized: "Bu klasör bir Nerd sitesi değil. Önce `nerd link` ya da `nerd park` çalıştırın."))
        return nil
    }

    private static func siteAt(_ url: URL) -> Site? {
        let path = url.path
        return state.sites.filter { !$0.isProxy }
            .map { ($0, $0.path.resolvingSymlinksInPath().path) }
            .filter { path == $0.1 || path.hasPrefix($0.1 + "/") }
            .max { $0.1.count < $1.1.count }?.0
    }

    private static func absolute(_ dir: String?) -> String {
        guard let dir else { return cwd.path }
        let expanded = (dir as NSString).expandingTildeInPath
        let url = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : cwd.appendingPathComponent(expanded)
        return url.standardizedFileURL.path
    }

    private static func tilde(_ path: String) -> String { (path as NSString).abbreviatingWithTildeInPath }

    private static func ok(_ message: String) { print("✓ " + message) }
    private static func info(_ message: String) { print("  " + message) }
    private static func warn(_ message: String) { print("! " + message) }

    @discardableResult
    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(("✗ " + message + "\n").data(using: .utf8)!)
        return 1
    }

    private static func table(_ header: [String], _ rows: [[String]]) {
        let all = [header] + rows
        let widths = header.indices.map { i in all.map { $0[i].count }.max() ?? 0 }
        for row in all {
            print(row.enumerated().map { i, cell in
                i == row.count - 1 ? cell : cell.padding(toLength: widths[i], withPad: " ", startingAt: 0)
            }.joined(separator: "  "))
        }
    }

    /// Replaces this process with `path` so the command keeps the terminal (stdin, colours, Ctrl-C).
    private static func exec(_ path: String, _ args: [String], env: [String: String]) -> Never {
        fflush(stdout)
        let argv = ([(path as NSString).lastPathComponent] + args).map { strdup($0) } + [nil]
        let envp = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        execve(path, argv, envp)
        fail("\(path): \(String(cString: strerror(errno)))")
        exit(127)
    }

    private static func runSync(_ exe: String, _ args: [String]) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        guard (try? p.run()) != nil else { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    static var help: String {
        String(localized: """
        nerd — Nerd'ü terminalden yönetin

        Siteler
          nerd park [klasör]          Klasördeki her alt klasörü site yapar
          nerd forget [klasör]        Park klasörünü bırakır
          nerd link [ad]              Bu klasörü ad.test olarak bağlar
          nerd unlink [ad]            Bağlantıyı (ya da proxy'yi) kaldırır
          nerd links | nerd sites     Bağlı / tüm siteleri listeler
          nerd open [ad]              Siteyi tarayıcıda açar
          nerd secure | unsecure [ad] HTTPS'i açar / kapatır
          nerd proxy <ad> <port|adres> ad.test'i http://localhost:PORT'a yönlendirir
          nerd unproxy <ad>           Proxy siteyi kaldırır

        PHP
          nerd use php@8.4            Bu sitenin PHP sürümünü seçer (--global: varsayılan)
          nerd isolate [php@8.4]      Siteyi bir PHP sürümüne sabitler
          nerd unisolate              Varsayılan PHP'ye döner
          nerd php …, nerd composer … Sitenin PHP sürümüyle çalıştırır

        Diğer
          nerd logs [ad] [-f]         Laravel ya da dev sunucusu logu
          nerd docker [klasör]        Dockerfile ve docker-compose.yml üretir
          nerd startup [on|off]       Oturum açılınca Nerd'ü başlatır
          nerd mcp                    MCP sunucusu (Claude Code, Cursor)

        Ad verilmezse bulunduğunuz klasörün sitesi kullanılır.
        """)
    }
}

// MARK: - App side

extension AppState {
    /// Writes ~/.nerd/bin/nerd, pointing at this copy of the app.
    func installCLI() {
        guard let exe = Bundle.main.executablePath else { return }
        let script = """
        #!/bin/sh
        # Managed by Nerd: the `nerd` terminal command.
        exec \(Shell.quote(exe)) --cli "$@"

        """
        let url = CLI.wrapperURL
        if (try? String(contentsOf: url, encoding: .utf8)) == script { return }
        try? FileManager.default.removeItem(at: url)
        try? script.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// Answers `nerd` commands run while the app is open.
    func listenForCLI() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: CLI.request, object: nil, queue: .main) { note in
            let token = note.object as? String
            let action = note.userInfo?["action"] as? String ?? "reload"
            let site = note.userInfo?["site"] as? String
            Task { @MainActor in
                let state = AppState.shared
                switch action {
                case "open":
                    if let s = state.site(site) { state.openSite(s) }
                default:
                    await state.reloadFromDisk()
                }
                center.postNotificationName(CLI.response, object: token,
                                            userInfo: ["error": state.webError ?? ""], deliverImmediately: true)
            }
        }
    }

    /// Picks up config changes made outside the app and applies them to Caddy and PHP-FPM.
    func reloadFromDisk() async {
        loadConfigForCLI()
        for p in config.parkedPaths {
            try? FileManager.default.createDirectory(atPath: p, withIntermediateDirectories: true)
        }
        linkDefaults()
        scanSites()
        await reloadWebServer()
    }
}
