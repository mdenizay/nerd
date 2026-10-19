import Foundation
import AppKit

extension AppState {
    static func slug(_ s: String) -> String {
        let lowered = s.lowercased().replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "_", with: "-")
        return String(lowered.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." })
    }

    static func detectKind(_ url: URL) -> SiteKind {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.appendingPathComponent("artisan").path) { return .laravel }
        if dotnetProject(in: url) != nil { return .dotnet }
        if let data = try? Data(contentsOf: url.appendingPathComponent("package.json")),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let deps = (json["dependencies"] as? [String: Any] ?? [:]).merging(json["devDependencies"] as? [String: Any] ?? [:]) { a, _ in a }
            if deps["next"] != nil { return .next }
            if deps["astro"] != nil { return .astro }
        }
        for candidate in ["public/index.php", "index.php"] where fm.fileExists(atPath: url.appendingPathComponent(candidate).path) {
            return .php
        }
        return .plain
    }

    func scanSites() {
        let fm = FileManager.default
        var result: [String: Site] = [:]

        func add(_ url: URL, linked: Bool) {
            let name = Self.slug(url.lastPathComponent)
            guard !name.isEmpty, result[name] == nil else { return }
            let pub = url.appendingPathComponent("public")
            var isDir: ObjCBool = false
            let docroot = fm.fileExists(atPath: pub.path, isDirectory: &isDir) && isDir.boolValue ? pub : url
            result[name] = Site(name: name, path: url, docroot: docroot, kind: Self.detectKind(url), linked: linked,
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

        // Give every Node app a stable dev server port
        var used = Set(config.sites.values.compactMap(\.port))
        for (name, site) in result where site.kind.isProxied && site.config.port == nil {
            var port = 3100
            while used.contains(port) { port += 1 }
            used.insert(port)
            var c = config.sites[name] ?? SiteConfig()
            c.port = port
            config.sites[name] = c
            result[name]?.config = c
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

    /// Moves a project to the Trash and forgets it; optionally drops its MySQL/PostgreSQL database.
    func deleteSite(_ site: Site, dropDatabase: Bool) async -> String? {
        processes[devKey(site)]?.stop()
        processes.removeValue(forKey: devKey(site))
        if dropDatabase, var c = connection(for: site), c.driver != .sqlite, !c.database.isEmpty {
            let db = c.database
            c.database = c.driver == .pgsql ? "postgres" : ""
            let client = DBClient(conn: c)
            let sql = c.driver == .pgsql
                ? "DROP DATABASE IF EXISTS \(client.ident(db)) WITH (FORCE)"
                : "DROP DATABASE IF EXISTS \(client.ident(db))"
            do { _ = try await client.run(sql) } catch {
                return String(localized: "Veritabanı silinemedi: \(error.localizedDescription)")
            }
        }
        do {
            _ = try await NSWorkspace.shared.recycle([site.path])
        } catch {
            return String(localized: "Klasör Çöp Sepeti'ne taşınamadı: \(error.localizedDescription)")
        }
        config.sites.removeValue(forKey: site.name)
        config.linkedPaths.removeAll { $0 == site.path.path }
        if selectedSiteID == site.name { selectedSiteID = nil }
        scanSites()
        await reloadWebServer()
        return nil
    }

    /// Environment for running commands inside a site with its PHP/Node versions first in PATH.
    func env(for site: Site) -> [String: String] {
        var prepend: [String] = []
        if let n = node(for: site) { prepend.append(n.binDir) }
        if let p = php(for: site) { prepend.append(p.binDir) }
        return Shell.env(prependPath: prepend)
    }

    // MARK: Dev servers (Vite for Laravel, Next.js / Astro)

    func devKey(_ site: Site) -> String { "dev-\(site.name)" }

    func isDevRunning(_ site: Site) -> Bool { processes[devKey(site)]?.running ?? false }

    func startDev(_ site: Site) {
        let p = process(devKey(site))
        if site.kind == .dotnet {
            if !p.running { startDotnet(site, process: p) }
            return
        }
        guard !p.running,
              let npm = node(for: site).map({ "\($0.binDir)/npm" }) ?? Shell.which("npm") else { return }
        var args = ["run", "dev"]
        if site.kind.isNodeApp, let port = site.config.port { args += ["--", "--port", String(port)] }
        try? p.start(npm, args, cwd: site.path, env: env(for: site))
    }

    func toggleDev(_ site: Site) {
        if isDevRunning(site) { processes[devKey(site)]?.stop() } else { startDev(site) }
    }

    /// Opens the site in the browser, booting its dev server first for Node apps.
    func openSite(_ site: Site) {
        guard site.kind.isProxied, !isDevRunning(site) else { open(url(for: site)); return }
        startDev(site)
        Task {
            // .NET builds before it serves
            try? await Task.sleep(for: .seconds(site.kind == .dotnet ? 10 : 4))
            open(url(for: site))
        }
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
