import Foundation

extension AppState {
    static func slug(_ s: String) -> String {
        let lowered = s.lowercased().replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "_", with: "-")
        return String(lowered.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." })
    }

    func scanSites() {
        let fm = FileManager.default
        var result: [String: Site] = [:]

        func add(_ url: URL, linked: Bool) {
            let name = Self.slug(url.lastPathComponent)
            guard !name.isEmpty, result[name] == nil else { return }
            let isLaravel = fm.fileExists(atPath: url.appendingPathComponent("artisan").path)
            let pub = url.appendingPathComponent("public")
            var isDir: ObjCBool = false
            let docroot = fm.fileExists(atPath: pub.path, isDirectory: &isDir) && isDir.boolValue ? pub : url
            result[name] = Site(name: name, path: url, docroot: docroot, isLaravel: isLaravel, linked: linked,
                                config: config.sites[name] ?? SiteConfig())
        }

        for linked in config.linkedPaths { add(URL(fileURLWithPath: linked), linked: true) }
        for parked in config.parkedPaths {
            let base = URL(fileURLWithPath: parked)
            guard let items = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey],
                                                         options: [.skipsHiddenFiles]) else { continue }
            for item in items where (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                add(item, linked: false)
            }
        }
        sites = result.values.sorted { $0.name < $1.name }
    }

    func site(_ name: String?) -> Site? { sites.first { $0.name == name } }

    func host(for site: Site) -> String { "\(site.name).\(config.tld)" }

    func url(for site: Site) -> URL {
        let secure = site.config.secure
        let port = secure ? config.httpsPort : config.httpPort
        let suffix = (secure && port == 443) || (!secure && port == 80) ? "" : ":\(port)"
        return URL(string: "\(secure ? "https" : "http")://\(host(for: site))\(suffix)")!
    }

    func php(for site: Site) -> PHPVersion? {
        phpVersion(site.config.php) ?? defaultPHP
    }

    func node(for site: Site) -> NodeVersion? {
        nodeVersion(site.config.node) ?? defaultNode
    }

    func updateSite(_ name: String, _ change: (inout SiteConfig) -> Void) {
        var c = config.sites[name] ?? SiteConfig()
        change(&c)
        config.sites[name] = c
        scanSites()
        Task { await reloadWebServer() }
    }

    func linkFolder(_ url: URL) {
        guard !config.linkedPaths.contains(url.path) else { return }
        config.linkedPaths.append(url.path)
        scanSites()
        Task { await reloadWebServer() }
    }

    func unlink(_ site: Site) {
        config.linkedPaths.removeAll { $0 == site.path.path }
        scanSites()
        Task { await reloadWebServer() }
    }

    /// Environment for running commands inside a site with its PHP/Node versions first in PATH.
    func env(for site: Site) -> [String: String] {
        var prepend: [String] = []
        if let n = node(for: site) { prepend.append(n.binDir) }
        if let p = php(for: site) { prepend.append(p.binDir) }
        return Shell.env(prependPath: prepend)
    }

    // MARK: Vite dev server

    func viteKey(_ site: Site) -> String { "vite-\(site.name)" }

    func isViteRunning(_ site: Site) -> Bool { processes[viteKey(site)]?.running ?? false }

    func toggleVite(_ site: Site) {
        let p = process(viteKey(site))
        if p.running { p.stop(); return }
        guard let npm = node(for: site).map({ "\($0.binDir)/npm" }) ?? Shell.which("npm") else { return }
        try? p.start(npm, ["run", "dev"], cwd: site.path, env: env(for: site))
    }

    func artisan(_ site: Site, _ command: String) async {
        guard let php = php(for: site) else { return }
        let args = ["artisan"] + command.split(separator: " ").map(String.init)
        await runJob("\(site.name): php artisan \(command)", php.bin, args, cwd: site.path, env: env(for: site))
    }

    func laravelLog(_ site: Site, lines: Int = 300) -> String {
        let url = site.path.appendingPathComponent("storage/logs/laravel.log")
        guard let h = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: size > 200_000 ? size - 200_000 : 0)
        let data = (try? h.readToEnd()) ?? Data()
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false).suffix(lines).joined(separator: "\n")
    }

    // MARK: .env

    static func parseEnv(_ url: URL) -> [String: String] {
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for raw in s.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let f = value.first, f == "\"" || f == "'", value.last == f {
                value = String(value.dropFirst().dropLast())
            }
            out[key] = value
        }
        return out
    }

    func connection(for site: Site) -> DBConnection? {
        let env = Self.parseEnv(site.path.appendingPathComponent(".env"))
        guard let driver = env["DB_CONNECTION"] else { return nil }
        var c = DBConnection(id: "site:\(site.name)", name: site.name, site: site.name)
        switch driver {
        case "sqlite":
            c.driver = .sqlite
            let db = env["DB_DATABASE"] ?? ""
            c.file = db.hasPrefix("/") ? db : site.path.appendingPathComponent(db.isEmpty ? "database/database.sqlite" : db).path
        case "mysql", "mariadb":
            c.driver = .mysql
            c.host = env["DB_HOST"] ?? "127.0.0.1"
            c.port = Int(env["DB_PORT"] ?? "") ?? 3306
            c.username = env["DB_USERNAME"] ?? "root"
            c.password = env["DB_PASSWORD"] ?? ""
            c.database = env["DB_DATABASE"] ?? site.name
        case "pgsql":
            c.driver = .pgsql
            c.host = env["DB_HOST"] ?? "127.0.0.1"
            c.port = Int(env["DB_PORT"] ?? "") ?? 5432
            c.username = env["DB_USERNAME"] ?? NSUserName()
            c.password = env["DB_PASSWORD"] ?? ""
            c.database = env["DB_DATABASE"] ?? site.name
        default:
            return nil
        }
        return c
    }

    var siteConnections: [DBConnection] { sites.compactMap { connection(for: $0) } }
}
