import Foundation

/// Caddy (reverse proxy / static) + php-fpm pools per PHP version + DNS for the TLD.
extension AppState {
    var neededPHP: [PHPVersion] {
        var seen = Set<String>()
        return sites.filter { !$0.kind.isProxied }.compactMap { php(for: $0) }.filter { seen.insert($0.version).inserted }
    }

    // MARK: Caddyfile

    func caddyfile() -> String {
        var s = """
        {
        \tadmin localhost:2019
        \thttp_port \(config.httpPort)
        \thttps_port \(config.httpsPort)
        \tskip_install_trust
        \tlocal_certs
        }

        """
        for site in sites {
            let host = host(for: site)
            let addr = site.config.secure
                ? "https://\(host)\(config.httpsPort == 443 ? "" : ":\(config.httpsPort)")"
                : "http://\(host)\(config.httpPort == 80 ? "" : ":\(config.httpPort)")"
            s += "\n\(addr) {\n"
            if site.config.secure { s += "\ttls internal\n" }
            if site.kind.isProxied, let port = site.config.port {
                // Vite-based dev servers (Astro) reject unknown Host headers
                s += site.kind == .astro
                    ? "\treverse_proxy localhost:\(port) {\n\t\theader_up Host localhost:\(port)\n\t}\n}\n"
                    : "\treverse_proxy localhost:\(port)\n}\n"
                continue
            }
            s += "\troot * \"\(site.docroot.path)\"\n"
            s += "\tencode zstd gzip\n"
            if let php = php(for: site) {
                s += "\tphp_fastcgi unix/\(php.socket)\n"
            }
            s += "\tfile_server\n}\n"
        }
        return s
    }

    func fpmConfig(_ v: PHPVersion) -> String {
        let run = Paths.run.path, logs = Paths.logs.path
        return """
        [global]
        pid = \(run)/\(v.key)-fpm.pid
        error_log = \(logs)/\(v.key)-fpm-error.log
        daemonize = no

        [nerd]
        listen = \(v.socket)
        listen.mode = 0666
        pm = dynamic
        pm.max_children = 10
        pm.start_servers = 2
        pm.min_spare_servers = 1
        pm.max_spare_servers = 4
        catch_workers_output = yes
        clear_env = no
        php_admin_flag[log_errors] = on
        php_admin_value[error_log] = \(logs)/\(v.key)-php-error.log
        ; Deprecations raised before a framework installs its error handler (e.g. while
        ; Laravel loads config) would otherwise be printed into the page. Frameworks
        ; still raise the level themselves and log deprecations their own way.
        php_value[error_reporting] = E_ALL & ~E_DEPRECATED
        ; Sends dump() / dd() to Nerd's Dumps view (php_value, so a site's .user.ini can still override it)
        php_value[auto_prepend_file] = "\(DumpHook.prepend.path)"
        php_value[memory_limit] = 512M
        php_value[upload_max_filesize] = 128M
        php_value[post_max_size] = 128M

        """
    }

    // MARK: PHP-FPM

    func startFPM(_ v: PHPVersion, restart: Bool = false) {
        let p = process(v.key)
        if p.running && !restart { return }
        p.stop()
        guard Paths.exists(v.fpm) else { return }
        let conf = Paths.fpm.appendingPathComponent("\(v.key).conf")
        try? fpmConfig(v).write(to: conf, atomically: true, encoding: .utf8)
        // Clean stale pid/socket from a previous crash
        let pidFile = Paths.run.appendingPathComponent("\(v.key)-fpm.pid")
        if let pidStr = try? String(contentsOf: pidFile, encoding: .utf8), let pid = Int32(pidStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
            kill(pid, SIGTERM)
        }
        try? FileManager.default.removeItem(atPath: v.socket)
        try? p.start(v.fpm, ["--nodaemonize", "--fpm-config", conf.path], env: Shell.env(prependPath: [v.binDir]))
    }

    func isFPMRunning(_ v: PHPVersion) -> Bool { processes[v.key]?.running ?? false }

    // MARK: Web server

    func startWebServer() async {
        guard let caddy = Shell.which("caddy") else {
            webError = String(localized: "Caddy kurulu değil.")
            return
        }
        webError = nil
        for v in neededPHP { startFPM(v) }
        try? caddyfile().write(to: Paths.caddyfile, atomically: true, encoding: .utf8)

        // Stop a caddy left behind by a previous run
        _ = await Shell.run(caddy, ["stop", "--address", "localhost:2019"])

        let p = process("caddy")
        p.onExit = { [weak self] status in
            guard let self else { return }
            self.webRunning = false
            if status != 0 {
                self.webError = String(localized: "Caddy durdu (kod \(Int(status))).") + "\n" + p.tail(8)
            }
        }
        do {
            try p.start(caddy, ["run", "--config", Paths.caddyfile.path, "--adapter", "caddyfile"])
            webRunning = true
        } catch {
            webError = error.localizedDescription
            webRunning = false
        }
    }

    func stopWebServer() {
        processes["caddy"]?.stop()
        for v in phpVersions { processes[v.key]?.stop() }
        webRunning = false
    }

    func restartWebServer() async {
        stopWebServer()
        await startWebServer()
    }

    func reloadWebServer(restartFPM: Bool = false) async {
        guard webRunning, let caddy = Shell.which("caddy") else { return }
        let needed = Set(neededPHP.map(\.version))
        for v in installedPHP {
            if needed.contains(v.version) { startFPM(v, restart: restartFPM) } else { processes[v.key]?.stop() }
        }
        try? caddyfile().write(to: Paths.caddyfile, atomically: true, encoding: .utf8)
        let r = await Shell.run(caddy, ["reload", "--config", Paths.caddyfile.path, "--adapter", "caddyfile", "--address", "localhost:2019"])
        webError = r.ok ? nil : String(localized: "Caddy yeniden yüklenemedi:") + "\n" + r.stderr.suffix(600)
    }

    func installCaddy() async {
        busy.insert("caddy")
        defer { busy.remove("caddy") }
        await brew("Caddy kurulumu", ["install", "caddy"])
        caddyInstalled = Shell.which("caddy") != nil
        if caddyInstalled { await startWebServer() }
    }

    // MARK: DNS

    func startDNSIfNeeded() {
        dns.tld = config.tld
        if config.tld == "localhost" {
            dns.stop()
        } else if !dns.isRunning {
            dns.start(port: UInt16(config.dnsPort))
        }
        dnsRunning = dns.isRunning
        resolverInstalled = Paths.exists("/etc/resolver/\(config.tld)")
    }

    func installResolver() async {
        let tld = config.tld
        let script = "mkdir -p /etc/resolver && printf 'nameserver 127.0.0.1\\nport \(config.dnsPort)\\n' > /etc/resolver/\(tld) && killall -HUP mDNSResponder || true"
        let r = await Shell.runAsAdmin(script)
        let job = newJob("DNS çözümleyici (.\(tld))")
        if r.ok { job.note("/etc/resolver/\(tld) yazıldı.\n") } else { job.append(r.stderr) }
        job.finish(r.ok)
        resolverInstalled = Paths.exists("/etc/resolver/\(tld)")
    }

    func trustCaddyCA() async {
        let cert = Paths.caddyRootCert.path
        let job = newJob("HTTPS sertifikasına güven")
        guard Paths.exists(cert) else {
            job.note("Caddy kök sertifikası henüz oluşmadı. Önce bir siteyi HTTPS yapıp web sunucusunu çalıştırın.\n")
            job.finish(false)
            return
        }
        let r = await Shell.runAsAdmin("security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain \(Shell.quote(cert))")
        if r.ok { job.note("Kök sertifika sistem anahtar zincirine eklendi.\n") } else { job.append(r.stderr) }
        job.finish(r.ok)
    }
}
