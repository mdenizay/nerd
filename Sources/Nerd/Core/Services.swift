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
        default:
            await brew(title, ["services", action, def.formula])
        }
        await refreshServices()
    }

    func toggleService(_ def: ServiceDef) async {
        let running = services[def.formula]?.isRunning ?? false
        await serviceAction(def, running ? "stop" : "start")
    }

    var installedServices: [ServiceDef] {
        ServiceDef.catalog.filter { services[$0.formula]?.installed == true }
    }
}
