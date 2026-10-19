import Foundation

extension AppState {
    func refreshServices() async {
        let list = await Shell.run(Paths.brewBin, ["list", "--formula", "-1"])
        let installed = Set(list.stdout.split(separator: "\n").map(String.init))
        let svc = await Shell.run(Paths.brewBin, ["services", "list", "--json"])
        var statuses: [String: String] = [:]
        if let data = svc.stdout.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for item in arr {
                if let name = item["name"] as? String { statuses[name] = item["status"] as? String ?? "none" }
            }
        }
        var result: [String: ServiceStatus] = [:]
        for def in ServiceDef.catalog {
            result[def.formula] = ServiceStatus(installed: installed.contains(def.formula), status: statuses[def.formula] ?? "none")
        }
        services = result
    }

    func serviceAction(_ def: ServiceDef, _ action: String) async {
        busy.insert(def.formula)
        defer { busy.remove(def.formula) }
        let titles = ["install": "kuruluyor", "start": "başlatılıyor", "stop": "durduruluyor", "restart": "yeniden başlatılıyor", "uninstall": "kaldırılıyor"]
        let title = "\(def.name) \(titles[action] ?? action)"
        switch action {
        case "install", "uninstall":
            await brew(title, [action, def.formula])
        case "start", "restart":
            let job = newJob(title)
            // Services sharing a port (PostgreSQL 17/18, MySQL/MariaDB, Redis/Valkey) can't run together
            for other in conflicts(of: def) {
                job.append("\(other.name) aynı portu (\(String(def.port ?? 0))) kullanıyor, durduruluyor…\n")
                await step(job, Paths.brewBin, ["services", "stop", other.formula])
            }
            if let port = def.port, Self.isPortOpen(port) {
                try? await Task.sleep(for: .seconds(1))
                if Self.isPortOpen(port) {
                    job.append("Uyarı: \(port) portu başka bir uygulama tarafından kullanılıyor.\n")
                }
            }
            // An errored launch agent is still loaded; `start` would be a no-op
            let verb = action == "start" && services[def.formula]?.status == "error" ? "restart" : action
            var ok = await step(job, Paths.brewBin, ["services", verb, def.formula])
            try? await Task.sleep(for: .seconds(2))
            await refreshServices()
            if services[def.formula]?.status == "error" {
                ok = false
                job.append("\n\(def.name) başlatılamadı.\n")
                if let log = serviceLog(def) { job.append("Son log satırları:\n\(log)\n") }
            }
            job.finish(ok)
        default:
            await brew(title, ["services", action, def.formula])
        }
        await refreshServices()
    }

    /// Running catalog services bound to the same port.
    func conflicts(of def: ServiceDef) -> [ServiceDef] {
        guard let port = def.port else { return [] }
        return ServiceDef.catalog.filter {
            $0.formula != def.formula && $0.port == port && (services[$0.formula]?.isRunning ?? false)
        }
    }

    func serviceLog(_ def: ServiceDef, lines: Int = 8) -> String? {
        let url = URL(fileURLWithPath: "\(Paths.brew)/var/log/\(def.formula).log")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(decoding: data.suffix(8_000), as: UTF8.self)
            .split(separator: "\n").suffix(lines).joined(separator: "\n")
    }

    static func isPortOpen(_ port: Int) -> Bool {
        let s = socket(AF_INET, SOCK_STREAM, 0)
        guard s >= 0 else { return false }
        defer { close(s) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        } == 0
    }

    func toggleService(_ def: ServiceDef) async {
        let running = services[def.formula]?.isRunning ?? false
        await serviceAction(def, running ? "stop" : "start")
    }

    var installedServices: [ServiceDef] {
        ServiceDef.catalog.filter { services[$0.formula]?.installed == true }
    }
}
