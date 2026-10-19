import Foundation

extension AppState {
    static let knownPHP = ["8.5", "8.4", "8.3", "8.2", "8.1", "8.0", "7.4"]

    var installedPHP: [PHPVersion] { phpVersions.filter(\.installed) }

    var defaultPHP: PHPVersion? {
        installedPHP.first { $0.version == config.defaultPHP } ?? installedPHP.first
    }

    func phpVersion(_ v: String?) -> PHPVersion? {
        guard let v else { return nil }
        return installedPHP.first { $0.version == v }
    }

    func detectPHP() {
        let brew = Paths.brew
        var latest: String?
        if let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: "\(brew)/opt/php"),
           let full = dest.split(separator: "/").last {
            latest = full.split(separator: ".").prefix(2).joined(separator: ".")
        }
        phpVersions = Self.knownPHP.map { v in
            let versioned = "\(brew)/opt/php@\(v)"
            if Paths.exists("\(versioned)/bin/php") {
                return PHPVersion(version: v, formula: latest == v ? "php" : "php@\(v)", prefix: versioned, installed: true)
            }
            if latest == v, Paths.exists("\(brew)/opt/php/bin/php") {
                return PHPVersion(version: v, formula: "php", prefix: "\(brew)/opt/php", installed: true)
            }
            return PHPVersion(version: v, formula: "php@\(v)", prefix: versioned, installed: false)
        }
    }

    func setDefaultPHP(_ v: PHPVersion) {
        config.defaultPHP = v.version
        linkDefaults()
        Task { await reloadWebServer() }
    }

    func installPHP(_ v: PHPVersion) async {
        busy.insert("php-\(v.version)")
        defer { busy.remove("php-\(v.version)") }
        let job = newJob("PHP \(v.version) kurulumu")
        var ok = await step(job, Paths.brewBin, ["install", "php@\(v.version)"])
        if !ok {
            job.note("\nHomebrew core'da yok, shivammathur/php tap'i deneniyor…\n")
            ok = await step(job, Paths.brewBin, ["tap", "shivammathur/php"])
            if ok { ok = await step(job, Paths.brewBin, ["install", "shivammathur/php/php@\(v.version)"]) }
        }
        job.finish(ok)
        detectPHP()
        if config.defaultPHP == nil { linkDefaults() }
    }

    func uninstallPHP(_ v: PHPVersion) async {
        busy.insert("php-\(v.version)")
        defer { busy.remove("php-\(v.version)") }
        processes[v.key]?.stop()
        await brew("PHP \(v.version) kaldırılıyor", ["uninstall", v.formula])
        detectPHP()
        linkDefaults()
    }

    func phpModules(_ v: PHPVersion) async -> [String] {
        let r = await Shell.run(v.bin, ["-m"])
        return r.stdout.split(separator: "\n").map(String.init).filter { !$0.isEmpty && !$0.hasPrefix("[") }
    }

    func peclInstall(_ ext: String, for v: PHPVersion) async {
        let extDir = await Shell.run(v.bin, ["-r", "echo ini_get('extension_dir');"]).stdout
        if !extDir.isEmpty { try? FileManager.default.createDirectory(atPath: extDir, withIntermediateDirectories: true) }
        await runJob("pecl install \(ext) (PHP \(v.version))", "\(v.binDir)/pecl", ["install", ext],
                     env: Shell.env(prependPath: [v.binDir]))
        await reloadWebServer(restartFPM: true)
    }
}

// MARK: - Xdebug

extension AppState {
    private func xdebugIni(_ v: PHPVersion) -> URL {
        URL(fileURLWithPath: "\(Paths.brew)/etc/php/\(v.version)/conf.d/zz-nerd-xdebug.ini")
    }

    func isXdebugEnabled(_ v: PHPVersion) -> Bool { Paths.exists(xdebugIni(v).path) }

    /// Turns Xdebug on (step debugging on trigger, port 9003) or off for one PHP version.
    func setXdebug(_ v: PHPVersion, enabled: Bool) async {
        busy.insert("php-\(v.version)")
        defer { busy.remove("php-\(v.version)") }
        let ini = xdebugIni(v)
        guard enabled else {
            try? FileManager.default.removeItem(at: ini)
            startFPM(v, restart: true)
            return
        }
        let job = newJob("Xdebug (PHP \(v.version))")
        let extDir = await Shell.run(v.bin, ["-r", "echo ini_get('extension_dir');"]).stdout
        if !Paths.exists("\(extDir)/xdebug.so") {
            // Homebrew's pecl symlink points at a folder that may not exist yet
            try? FileManager.default.createDirectory(atPath: extDir, withIntermediateDirectories: true)
            guard await step(job, "\(v.binDir)/pecl", ["install", "xdebug"], env: Shell.env(prependPath: [v.binDir])) else {
                job.finish(false)
                return
            }
            // pecl enables the extension in php.ini; Nerd's own ini file decides instead
            if let phpIni = try? String(contentsOfFile: v.ini, encoding: .utf8) {
                let cleaned = phpIni.components(separatedBy: "\n").filter {
                    !$0.trimmingCharacters(in: .whitespaces).hasPrefix("zend_extension=\"xdebug.so\"")
                }.joined(separator: "\n")
                try? cleaned.write(toFile: v.ini, atomically: true, encoding: .utf8)
            }
        }
        try? FileManager.default.createDirectory(at: ini.deletingLastPathComponent(), withIntermediateDirectories: true)
        let content = """
        ; Managed by Nerd. Delete this file, or switch Xdebug off in Nerd, to disable.
        zend_extension=xdebug.so
        xdebug.mode=debug,develop
        xdebug.start_with_request=trigger
        xdebug.client_host=127.0.0.1
        xdebug.client_port=9003

        """
        try? content.write(to: ini, atomically: true, encoding: .utf8)
        let check = await Shell.run(v.bin, ["-r", "echo extension_loaded('xdebug') ? 'ok' : 'missing';"])
        let ok = check.stdout == "ok"
        job.note(ok ? "Xdebug açık: tetikleyici XDEBUG_TRIGGER, port 9003.\n" : "Xdebug yüklenemedi.\n")
        job.finish(ok)
        if !ok { try? FileManager.default.removeItem(at: ini) }
        startFPM(v, restart: true)
    }
}
