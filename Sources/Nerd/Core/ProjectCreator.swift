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
}

extension AppState {
    func createProject(_ o: NewProjectOptions) async -> Job {
        let name = Self.slug(o.name)
        let job = newJob("Yeni proje: \(name)")
        selectedJobID = job.id
        let parent = URL(fileURLWithPath: o.location)
        let dir = parent.appendingPathComponent(name)

        func fail(_ msg: String) -> Job {
            job.append("\n\(msg)\n")
            job.finish(false)
            return job
        }

        guard !name.isEmpty else { return fail("Proje adı boş olamaz.") }
        guard !FileManager.default.fileExists(atPath: dir.path) else { return fail("\(dir.path) zaten mevcut.") }
        guard let php = phpVersion(o.php) ?? defaultPHP else { return fail("Kurulu PHP bulunamadı. Önce PHP sekmesinden bir sürüm kurun.") }
        let node = nodeVersion(o.node) ?? defaultNode
        var prepend = [php.binDir]
        if let node { prepend.insert(node.binDir, at: 0) }
        let env = Shell.env(prependPath: prepend, ["COMPOSER_NO_INTERACTION": "1"])

        job.append("PHP \(php.version)\(node.map { ", Node \($0.version)" } ?? "") ile oluşturuluyor → \(dir.path)\n")

        // 1. Scaffold
        if o.template == .plain {
            do {
                try FileManager.default.createDirectory(at: dir.appendingPathComponent("public"), withIntermediateDirectories: true)
                try "<?php\n\necho 'Merhaba, \(name)!';\n".write(to: dir.appendingPathComponent("public/index.php"), atomically: true, encoding: .utf8)
            } catch { return fail(error.localizedDescription) }
        } else {
            let package = o.template == .custom ? o.customPackage.trimmingCharacters(in: .whitespaces) : (o.template.package ?? "")
            guard !package.isEmpty else { return fail("Composer paketi belirtilmedi.") }
            guard let composer = Shell.which("composer") else { return fail("Composer bulunamadı. `brew install composer` ile kurun.") }
            let ok = await step(job, php.bin, [composer, "create-project", package, name, "--prefer-dist", "--no-interaction"], cwd: parent, env: env)
            guard ok else { return fail("composer create-project başarısız oldu.") }
        }

        let isLaravel = FileManager.default.fileExists(atPath: dir.appendingPathComponent("artisan").path)

        // 2. Environment + database
        if isLaravel {
            let scheme = o.secure ? "https" : "http"
            var values = ["APP_URL": "\(scheme)://\(name).\(config.tld)"]
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
            job.append("\n.env güncellendi (APP_URL, DB ayarları)\n")

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
                job.append("\nnpm bulunamadı, frontend adımı atlandı.\n")
            }
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
            job.append("\nHazır: \(url(for: site).absoluteString)\n")
        }
        job.finish(true)
        if o.openEditor { openInEditor(dir) }
        return job
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
