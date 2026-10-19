import Foundation

struct NewProjectOptions {
    var name = ""
    var location = ""
    var template: ProjectTemplate = .blade
    var customPackage = ""
    var php: String?
    var node: String?
    var database: DBDriver = .sqlite
    var npmBuild = true
    var gitInit = true
    var secure = false
    var openEditor = true
    var docker = false
    var dotnet: String?
}

extension AppState {
    func createProject(_ o: NewProjectOptions) async -> Job {
        let name = Self.slug(o.name)
        let job = newJob("Yeni proje: \(name)")
        selectedJobID = job.id
        let parent = URL(fileURLWithPath: o.location)
        let dir = parent.appendingPathComponent(name)

        func fail(_ msg: String.LocalizationValue) -> Job {
            job.append("\n" + String(localized: msg) + "\n")
            job.finish(false)
            return job
        }

        guard !name.isEmpty else { return fail("Proje adı boş olamaz.") }
        guard !FileManager.default.fileExists(atPath: dir.path) else { return fail("\(dir.path) zaten mevcut.") }
        if o.template.isDotnet {
            return await createDotnetProject(o, name: name, dir: dir, job: job)
        }
        let node = nodeVersion(o.node) ?? defaultNode
        if o.template.isNode {
            guard let node else { return fail("Kurulu Node bulunamadı. Önce Node.js sekmesinden bir sürüm kurun.") }
            return await createNodeProject(o, name: name, dir: dir, node: node, job: job)
        }
        guard let php = phpVersion(o.php) ?? defaultPHP else { return fail("Kurulu PHP bulunamadı. Önce PHP sekmesinden bir sürüm kurun.") }
        var prepend = [php.binDir]
        if let node { prepend.insert(node.binDir, at: 0) }
        let env = Shell.env(prependPath: prepend, ["COMPOSER_NO_INTERACTION": "1"])

        job.note("PHP \(php.version)\(node.map { ", Node \($0.version)" } ?? "") ile oluşturuluyor → \(dir.path)\n")

        // 1. Scaffold
        if o.template == .plain {
            do {
                try FileManager.default.createDirectory(at: dir.appendingPathComponent("public"), withIntermediateDirectories: true)
                try "<?php\n\necho 'Hello, \(name)!';\n".write(to: dir.appendingPathComponent("public/index.php"), atomically: true, encoding: .utf8)
            } catch { return fail("\(error.localizedDescription)") }
        } else {
            let package = o.template == .custom ? o.customPackage.trimmingCharacters(in: .whitespaces) : (o.template.package ?? "")
            guard !package.isEmpty else { return fail("Composer paketi belirtilmedi.") }
            guard let composer = Shell.which("composer") else { return fail("Composer bulunamadı. `brew install composer` ile kurun.") }
            let ok = await step(job, php.bin, [composer, "create-project", package, name, "--prefer-dist", "--no-interaction"], cwd: parent, env: env)
            guard ok else { return fail("composer create-project başarısız oldu.") }
        }

        let isLaravel = FileManager.default.fileExists(atPath: dir.appendingPathComponent("artisan").path)
        if isLaravel, Self.fixPDOConstants(dir) {
            job.note("\nconfig/database.php PHP 8.5 için güncellendi (Pdo\\Mysql::ATTR_SSL_CA).\n")
        }

        // 2. Environment + database
        if isLaravel {
            let scheme = o.secure ? "https" : "http"
            var values = ["APP_URL": "\(scheme)://\(name).\(config.tld)"]
            values.merge(mailEnv) { $1 }
            switch o.database {
            case .sqlite:
                break
            case .mysql:
                values.merge(["DB_CONNECTION": "mysql", "DB_HOST": "127.0.0.1", "DB_PORT": "3306",
                              "DB_DATABASE": name.replacingOccurrences(of: "-", with: "_"), "DB_USERNAME": "root", "DB_PASSWORD": ""]) { $1 }
            case .pgsql:
                values.merge(["DB_CONNECTION": "pgsql", "DB_HOST": "127.0.0.1", "DB_PORT": "5432",
                              "DB_DATABASE": name.replacingOccurrences(of: "-", with: "_"), "DB_USERNAME": NSUserName(), "DB_PASSWORD": ""]) { $1 }
            }
            Self.writeEnv(dir.appendingPathComponent(".env"), values)
            job.note("\n.env güncellendi (APP_URL, DB ayarları)\n")

            if o.database != .sqlite {
                let db = name.replacingOccurrences(of: "-", with: "_")
                if o.database == .mysql, let mysql = DBClient.mysqlBinary {
                    await step(job, mysql, ["-h127.0.0.1", "-uroot", "-e", "CREATE DATABASE IF NOT EXISTS `\(db)` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"])
                } else if o.database == .pgsql, let psql = DBClient.psqlBinary {
                    let createdb = (psql as NSString).deletingLastPathComponent + "/createdb"
                    await step(job, createdb, ["-h", "127.0.0.1", db])
                }
                await step(job, php.bin, ["artisan", "migrate", "--force"], cwd: dir, env: env)
            }
        }

        // 3. Frontend
        if o.npmBuild, FileManager.default.fileExists(atPath: dir.appendingPathComponent("package.json").path) {
            let npm = node.map { "\($0.binDir)/npm" } ?? Shell.which("npm")
            if let npm {
                if await step(job, npm, ["install"], cwd: dir, env: env) {
                    await step(job, npm, ["run", "build"], cwd: dir, env: env)
                }
            } else {
                job.note("\nnpm bulunamadı, frontend adımı atlandı.\n")
            }
        }

        if o.docker {
            let files = writeDockerFiles(adhocSite(dir))
            job.note("\nDocker dosyaları oluşturuldu: \(files.joined(separator: ", "))\n")
        }

        // 4. Git
        if o.gitInit, !FileManager.default.fileExists(atPath: dir.appendingPathComponent(".git").path) {
            await step(job, "/usr/bin/git", ["init", "-q"], cwd: dir)
            await step(job, "/usr/bin/git", ["add", "-A"], cwd: dir)
            await step(job, "/usr/bin/git", ["commit", "-q", "-m", "Initial commit"], cwd: dir)
        }

        // 5. Register site
        if !config.parkedPaths.contains(parent.path) { config.linkedPaths.append(dir.path) }
        config.sites[name] = SiteConfig(php: o.php, node: o.node, secure: o.secure)
        scanSites()
        await reloadWebServer()
        if !webRunning && caddyInstalled { await startWebServer() }
        selectedSiteID = name

        if let site = site(name) {
            job.note("\nHazır: \(url(for: site).absoluteString)\n")
        }
        job.finish(true)
        if o.openEditor { openInEditor(dir) }
        return job
    }

    private func createNodeProject(_ o: NewProjectOptions, name: String, dir: URL, node: NodeVersion, job: Job) async -> Job {
        let parent = dir.deletingLastPathComponent()
        let env = Shell.env(prependPath: [node.binDir], ["CI": "1", "NEXT_TELEMETRY_DISABLED": "1", "ASTRO_TELEMETRY_DISABLED": "1"])
        let npx = "\(node.binDir)/npx"
        job.note("Node \(node.version) ile oluşturuluyor → \(dir.path)\n")

        let ok: Bool
        switch o.template {
        case .next:
            var args = ["--yes", "create-next-app@latest", name, "--yes", "--use-npm"]
            if !o.gitInit { args.append("--disable-git") }
            ok = await step(job, npx, args, cwd: parent, env: env)
            if ok { Self.allowNextDevOrigins(dir, tld: config.tld) }
        default:
            ok = await step(job, npx, ["--yes", "create-astro@latest", name, "--template", "basics", "--install",
                                       o.gitInit ? "--git" : "--no-git", "--skip-houston", "--yes"], cwd: parent, env: env)
        }
        guard ok else {
            job.note("\nProje oluşturulamadı.\n")
            job.finish(false)
            return job
        }

        if o.docker {
            let files = writeDockerFiles(adhocSite(dir))
            job.note("\nDocker dosyaları oluşturuldu: \(files.joined(separator: ", "))\n")
        }

        if !config.parkedPaths.contains(parent.path) { config.linkedPaths.append(dir.path) }
        var c = SiteConfig(node: o.node, secure: o.secure)
        c.port = config.sites[name]?.port
        config.sites[name] = c
        scanSites()
        await reloadWebServer()
        if !webRunning && caddyInstalled { await startWebServer() }
        selectedSiteID = name
        if let site = site(name) {
            startDev(site)
            job.note("\nDev sunucusu başlatıldı → \(url(for: site).absoluteString)\n")
        }
        job.finish(true)
        if o.openEditor { openInEditor(dir) }
        return job
    }

    /// Next.js blocks dev assets for unknown origins; allow the local TLD.
    static func allowNextDevOrigins(_ dir: URL, tld: String) {
        for file in ["next.config.ts", "next.config.mjs", "next.config.js"] {
            let url = dir.appendingPathComponent(file)
            guard var s = try? String(contentsOf: url, encoding: .utf8), !s.contains("allowedDevOrigins") else { continue }
            if let r = s.range(of: #"nextConfig(\s*:\s*NextConfig)?\s*=\s*\{"#, options: .regularExpression) {
                s.replaceSubrange(r, with: s[r] + "\n  allowedDevOrigins: [\"*.\(tld)\"],")
                try? s.write(to: url, atomically: true, encoding: .utf8)
            }
            return
        }
    }

    /// PHP 8.5 deprecates PDO::MYSQL_ATTR_SSL_CA, which older Laravel skeletons use in
    /// config/database.php; switch to the form that works on every PHP version.
    @discardableResult
    static func fixPDOConstants(_ dir: URL) -> Bool {
        let url = dir.appendingPathComponent("config/database.php")
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { return false }
        let pattern = #"(?<![\w>])\\?PDO::MYSQL_ATTR_SSL_CA(?=\s*=>)"#
        guard s.range(of: pattern, options: .regularExpression) != nil else { return false }
        let fixed = s.replacingOccurrences(of: pattern,
                                           with: #"(PHP_VERSION_ID >= 80500 ? \\Pdo\\Mysql::ATTR_SSL_CA : \\PDO::MYSQL_ATTR_SSL_CA)"#,
                                           options: .regularExpression)
        return (try? fixed.write(to: url, atomically: true, encoding: .utf8)) != nil
    }

    /// Sets keys in a .env file, uncommenting/replacing existing (also commented) entries.
    static func writeEnv(_ url: URL, _ values: [String: String]) {
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { return }
        var remaining = values
        var lines: [String] = []
        for line in s.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let bare = trimmed.hasPrefix("#") ? trimmed.dropFirst().trimmingCharacters(in: .whitespaces) : trimmed
            if let eq = bare.firstIndex(of: "=") {
                let key = String(bare[..<eq])
                if values[key] != nil {
                    if let v = remaining.removeValue(forKey: key) { lines.append("\(key)=\(v)") }
                    continue
                }
            }
            lines.append(line)
        }
        for (k, v) in remaining.sorted(by: { $0.key < $1.key }) { lines.append("\(k)=\(v)") }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
