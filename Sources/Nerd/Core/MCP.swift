import Foundation

/// `Nerd mcp`: a Model Context Protocol server over stdio (JSON-RPC 2.0, one
/// message per line). AI coding agents use it to see and manage the local
/// environment: sites, services, logs, databases, mail, artisan, Docker files.
@MainActor
enum MCPServer {
    static let protocolVersion = "2025-06-18"
    private static var state: AppState { AppState.shared }

    /// Reads requests from stdin until EOF; never returns.
    static func run() -> Never {
        state.prepareHeadless()
        Thread.detachNewThread {
            while let line = readLine(strippingNewline: true) {
                guard !line.isEmpty, let data = line.data(using: .utf8),
                      let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                let done = DispatchSemaphore(value: 0)
                Task { @MainActor in
                    if let reply = await handle(message) { write(reply) }
                    done.signal()
                }
                done.wait()
            }
            exit(0)
        }
        dispatchMain()
    }

    private nonisolated static func write(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else { return }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    }

    // MARK: JSON-RPC

    static func handle(_ message: [String: Any]) async -> [String: Any]? {
        let id = message["id"]
        let method = message["method"] as? String ?? ""
        let params = message["params"] as? [String: Any] ?? [:]
        guard id != nil else { return nil } // notifications (e.g. notifications/initialized)

        func result(_ value: Any) -> [String: Any] { ["jsonrpc": "2.0", "id": id!, "result": value] }
        func failure(_ code: Int, _ text: String) -> [String: Any] {
            ["jsonrpc": "2.0", "id": id!, "error": ["code": code, "message": text]]
        }

        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String
            return result([
                "protocolVersion": requested ?? protocolVersion,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "nerd", "title": "Nerd", "version": Updater.version],
                "instructions": "Nerd manages a local PHP / Laravel / Node / .NET development environment on macOS. Sites live at https?://<name>.test. Use list_sites first; most tools take a site name.",
            ])
        case "ping":
            return result([String: Any]())
        case "tools/list":
            return result(["tools": tools])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            do {
                let text = try await call(name, args)
                return result(["content": [["type": "text", "text": text]], "isError": false])
            } catch {
                return result(["content": [["type": "text", "text": error.localizedDescription]], "isError": true])
            }
        default:
            return failure(-32601, "Method not found: \(method)")
        }
    }

    // MARK: Tools

    private static func tool(_ name: String, _ description: String, _ properties: [String: Any] = [:], required: [String] = [],
                             readOnly: Bool = true) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": ["type": "object", "properties": properties, "required": required],
            "annotations": ["readOnlyHint": readOnly],
        ]
    }

    private static func string(_ description: String) -> [String: Any] { ["type": "string", "description": description] }

    static var tools: [[String: Any]] {
        [
            tool("list_sites", "All local sites with URL, kind (laravel, php, next, astro, dotnet, proxy), path and runtime versions."),
            tool("get_site", "Details of one site: settings, database connection, dev server, Docker files.",
                 ["site": string("Site name, e.g. my-app")], required: ["site"]),
            tool("list_services", "Homebrew services Nerd knows (MySQL, PostgreSQL, Redis, Mailpit, …) with installed / running state."),
            tool("service_action", "Start, stop or restart a Homebrew service. Starting one stops another on the same port.",
                 ["service": string("Formula, e.g. postgresql@18, mysql, redis"),
                  "action": ["type": "string", "enum": ["start", "stop", "restart"]]],
                 required: ["service", "action"], readOnly: false),
            tool("environment", "Installed PHP, Node.js and .NET versions, defaults, web server state, TLD."),
            tool("list_logs", "Log sources: Caddy, PHP-FPM and PHP errors per version, Laravel logs and dev server output per site."),
            tool("read_log", "The last lines of a log from list_logs.",
                 ["id": string("Log id (path) from list_logs"), "lines": ["type": "integer", "description": "Default 100, max 1000"],
                  "filter": string("Only lines containing this text")], required: ["id"]),
            tool("query_database", "Run SQL against a site's database (SQLite, MySQL or PostgreSQL, from its .env). Returns up to 200 rows as JSON. Statements that change data run as given.",
                 ["site": string("Site name"), "sql": string("SQL to run")], required: ["site", "sql"], readOnly: false),
            tool("list_tables", "Tables in a site's database.", ["site": string("Site name")], required: ["site"]),
            tool("list_mail", "Emails caught by Nerd's SMTP server (127.0.0.1:2525), newest first.",
                 ["limit": ["type": "integer", "description": "Default 20"]]),
            tool("read_mail", "One caught email: headers, text and HTML.", ["id": string("Mail id from list_mail")], required: ["id"]),
            tool("artisan", "Run `php artisan <command>` in a Laravel site with its PHP version and return the output.",
                 ["site": string("Site name"), "command": string("e.g. route:list, migrate --force, about")],
                 required: ["site", "command"], readOnly: false),
            tool("generate_docker", "Write a production Dockerfile, docker-compose.yml and .dockerignore for a site (Dokploy-ready).",
                 ["site": string("Site name"),
                  "database": ["type": "string", "enum": ["none", "sqlite", "mysql", "pgsql"]],
                  "redis": ["type": "boolean"]], required: ["site"], readOnly: false),
        ]
    }

    struct ToolError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static func site(_ args: [String: Any]) throws -> Site {
        let name = args["site"] as? String ?? ""
        state.scanSites()
        guard let site = state.site(name) ?? state.site(AppState.slug(name)) else {
            throw ToolError(message: "No site named '\(name)'. Sites: \(state.sites.map(\.name).joined(separator: ", "))")
        }
        return site
    }

    private static func json(_ value: Any) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private static func describe(_ site: Site) -> [String: Any] {
        var d: [String: Any] = ["name": site.name, "url": state.url(for: site).absoluteString, "kind": site.kind.rawValue,
                                "path": site.proxyTarget == nil ? site.path.path : NSNull(), "https": site.config.secure]
        if let target = site.proxyTarget { d["proxyTarget"] = target }
        if site.kind.isProxied {
            d["devServerPort"] = site.config.port ?? NSNull()
            d["devServerRunning"] = state.isDevRunning(site)
        } else {
            d["php"] = state.php(for: site)?.version ?? NSNull()
        }
        if site.kind == .dotnet { d["dotnet"] = state.dotnet(for: site)?.major ?? NSNull() }
        if site.hasPackageJSON { d["node"] = state.node(for: site)?.version ?? NSNull() }
        return d
    }

    static func call(_ name: String, _ args: [String: Any]) async throws -> String {
        switch name {
        case "list_sites":
            state.scanSites()
            return json(state.sites.map(describe))

        case "get_site":
            let s = try site(args)
            var d = describe(s)
            if let c = state.connection(for: s) {
                d["database"] = ["driver": c.driver.rawValue, "host": c.host, "port": c.port, "database": c.database,
                                 "username": c.username, "file": c.file]
            }
            d["dockerFiles"] = state.dockerFilesExist(s)
            d["mailRoutedToNerd"] = s.isLaravel ? state.mailRouted(s) : false
            return json(d)

        case "list_services":
            await state.refreshServices()
            return json(ServiceDef.catalog.map { def -> [String: Any] in
                let st = state.services[def.formula]
                return ["service": def.formula, "name": def.name, "port": def.port ?? NSNull(),
                        "installed": st?.installed ?? false, "status": st?.status ?? "none"]
            })

        case "service_action":
            let formula = args["service"] as? String ?? ""
            let action = args["action"] as? String ?? ""
            guard let def = ServiceDef.catalog.first(where: { $0.formula == formula }) else {
                throw ToolError(message: "Unknown service '\(formula)'. Known: \(ServiceDef.catalog.map(\.formula).joined(separator: ", "))")
            }
            guard ["start", "stop", "restart"].contains(action) else { throw ToolError(message: "action must be start, stop or restart") }
            await state.refreshServices()
            await state.serviceAction(def, action)
            let job = state.jobs.first
            return "\(def.name): \(state.services[def.formula]?.status ?? "unknown")\n\n" + (job?.output.suffix(2000).description ?? "")

        case "environment":
            state.refreshEnvironment()
            return json([
                "php": state.installedPHP.map(\.version), "defaultPHP": state.defaultPHP?.version ?? NSNull(),
                "node": state.nodeVersions.map(\.version), "defaultNode": state.defaultNode?.version ?? NSNull(),
                "dotnet": state.installedDotnet.map(\.major), "defaultDotnet": state.defaultDotnet?.major ?? NSNull(),
                "tld": state.config.tld, "parkedFolders": state.config.parkedPaths,
                "webServerRunning": Services.isPortListening(state.config.httpPort),
                "mailSMTP": "127.0.0.1:\(state.config.mailPort)",
            ])

        case "list_logs":
            state.scanSites()
            return json(state.debugSources.map { ["id": $0.url.path, "title": $0.title, "group": $0.group,
                                                  "exists": FileManager.default.fileExists(atPath: $0.url.path)] })

        case "read_log":
            let path = args["id"] as? String ?? ""
            guard state.debugSources.contains(where: { $0.url.path == path }) || path.hasPrefix(Paths.logs.path) else {
                throw ToolError(message: "Unknown log. Use an id from list_logs.")
            }
            let count = min(max(args["lines"] as? Int ?? 100, 1), 1000)
            let filter = args["filter"] as? String ?? ""
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return "(empty)" }
            let lines = Shell.stripANSI(String(decoding: data.suffix(2_000_000), as: UTF8.self)).split(separator: "\n")
                .filter { filter.isEmpty || $0.localizedCaseInsensitiveContains(filter) }
            return lines.suffix(count).joined(separator: "\n").ifEmpty("(empty)")

        case "query_database", "list_tables":
            let s = try site(args)
            guard let conn = state.connection(for: s) else { throw ToolError(message: "\(s.name) has no database in its .env") }
            let client = DBClient(conn: conn)
            if name == "list_tables" { return json(try await client.tables()) }
            let sql = args["sql"] as? String ?? ""
            guard !sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ToolError(message: "sql is empty") }
            let r = try await client.run(sql)
            let rows = r.rows.prefix(200).map { row in
                Dictionary(uniqueKeysWithValues: zip(r.columns, row.map { $0 as Any? ?? NSNull() }).map { ($0.0, $0.1 ?? NSNull()) })
            }
            return json(["columns": r.columns, "rows": rows, "rowCount": r.rows.count, "message": r.message ?? NSNull()])

        case "list_mail":
            state.loadMail()
            let limit = args["limit"] as? Int ?? 20
            return json(state.mails.prefix(limit).map {
                ["id": $0.id, "subject": $0.subject, "from": $0.from, "to": $0.to,
                 "date": ISO8601DateFormatter().string(from: $0.date), "attachments": $0.attachments]
            })

        case "read_mail":
            state.loadMail()
            let id = args["id"] as? String ?? ""
            guard let m = state.mails.first(where: { $0.id == id }) else { throw ToolError(message: "No mail with id '\(id)'") }
            return json(["subject": m.subject, "from": m.from, "to": m.to, "date": ISO8601DateFormatter().string(from: m.date),
                         "text": m.text ?? NSNull(), "html": m.html ?? NSNull(), "attachments": m.attachments])

        case "artisan":
            let s = try site(args)
            guard s.isLaravel, let php = state.php(for: s) else { throw ToolError(message: "\(s.name) is not a Laravel site") }
            let command = (args["command"] as? String ?? "").split(separator: " ").map(String.init)
            let r = await Shell.run(php.bin, ["artisan"] + command + ["--no-interaction"], cwd: s.path, env: state.env(for: s))
            return Shell.stripANSI(r.stdout + r.stderr).ifEmpty("(exit \(r.status))")

        case "generate_docker":
            let s = try site(args)
            var options = state.defaultDockerOptions(for: s)
            if let db = (args["database"] as? String).flatMap(DockerOptions.Database.init(rawValue:)) { options.database = db }
            if let redis = args["redis"] as? Bool { options.redis = redis }
            let files = state.writeDockerFiles(s, options: options)
            let plan = state.dockerPlan(for: s, options: options)
            return "Wrote \(files.joined(separator: ", ")) in \(s.path.path). Services: \(plan.services.joined(separator: ", ")); app port \(plan.port)."

        default:
            throw ToolError(message: "Unknown tool '\(name)'")
        }
    }
}

@MainActor
enum Services {
    static func isPortListening(_ port: Int) -> Bool { AppState.isPortOpen(port) }
}

extension AppState {
    /// Load config and detect the environment without starting servers or UI.
    func prepareHeadless() {
        Paths.ensure()
        loadConfigForCLI()
        refreshEnvironment()
        readMail = Set(UserDefaults.standard.stringArray(forKey: "nerd.mail.read") ?? [])
    }

    var mcpCommand: String { Bundle.main.executablePath ?? "/Applications/Nerd.app/Contents/MacOS/Nerd" }

    func addToClaudeCode() async {
        guard let claude = Shell.which("claude") ?? [Paths.home.appendingPathComponent(".claude/local/claude").path,
                                                     Paths.home.appendingPathComponent(".local/bin/claude").path].first(where: Paths.exists) else {
            let job = newJob("Claude Code'a ekle")
            job.note("claude komutu bulunamadı. Claude Code'u kurun ya da komutu kendiniz çalıştırın.\n")
            job.finish(false)
            return
        }
        await runJob("Claude Code'a ekle", claude, ["mcp", "add", "--scope", "user", "nerd", "--", mcpCommand, "mcp"])
    }
}
