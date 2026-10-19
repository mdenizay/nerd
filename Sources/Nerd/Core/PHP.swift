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
        await runJob("pecl install \(ext) (PHP \(v.version))", "\(v.binDir)/pecl", ["install", ext],
                     env: Shell.env(prependPath: [v.binDir]))
        await reloadWebServer(restartFPM: true)
    }
}
