import Foundation

private struct NodeIndexEntry: Decodable {
    let version: String
    let date: String
    let lts: String?

    enum CodingKeys: String, CodingKey { case version, date, lts }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(String.self, forKey: .version)
        date = try c.decode(String.self, forKey: .date)
        lts = try? c.decode(String.self, forKey: .lts) // `false` or a codename
    }
}

extension AppState {
    var defaultNode: NodeVersion? {
        nodeVersions.first { $0.version == config.defaultNode } ?? nodeVersions.first
    }

    func nodeVersion(_ v: String?) -> NodeVersion? {
        guard let v else { return nil }
        return nodeVersions.first { $0.version == v }
    }

    func detectNode() {
        var found: [NodeVersion] = []
        let fm = FileManager.default
        if let dirs = try? fm.contentsOfDirectory(atPath: Paths.node.path) {
            for d in dirs where d.hasPrefix("v") {
                let path = Paths.node.appendingPathComponent(d).path
                if Paths.exists("\(path)/bin/node") { found.append(NodeVersion(version: d, path: path, managed: true)) }
            }
        }
        // Homebrew-provided Node installs
        if let opts = try? fm.contentsOfDirectory(atPath: "\(Paths.brew)/opt") {
            for o in opts where o == "node" || o.hasPrefix("node@") {
                let path = "\(Paths.brew)/opt/\(o)"
                guard Paths.exists("\(path)/bin/node"),
                      let real = try? fm.destinationOfSymbolicLink(atPath: path),
                      let ver = real.split(separator: "/").last else { continue }
                let version = "v" + ver.split(separator: "_").first!
                if !found.contains(where: { $0.version == version }) {
                    found.append(NodeVersion(version: version, path: path, managed: false))
                }
            }
        }
        nodeVersions = found.sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
    }

    func fetchRemoteNode() async {
        do {
            let (data, _) = try await URLSession.shared.data(from: URL(string: "https://nodejs.org/dist/index.json")!)
            let entries = try JSONDecoder().decode([NodeIndexEntry].self, from: data)
            var seen = Set<Int>()
            var list: [RemoteNode] = []
            for e in entries {
                let n = RemoteNode(version: e.version, lts: e.lts, date: e.date)
                guard n.major >= 18, !seen.contains(n.major) else { continue }
                seen.insert(n.major)
                list.append(n)
            }
            remoteNode = list
            remoteNodeError = nil
        } catch {
            remoteNodeError = error.localizedDescription
        }
    }

    func installNode(_ version: String) async {
        busy.insert("node-\(version)")
        defer { busy.remove("node-\(version)") }
        let arch = Self.isAppleSilicon ? "arm64" : "x64"
        let name = "node-\(version)-darwin-\(arch)"
        let url = "https://nodejs.org/dist/\(version)/\(name).tar.gz"
        let tmp = Paths.node.appendingPathComponent("\(name).tar.gz").path
        let dest = Paths.node.path
        let script = """
        set -e
        curl -fL --progress-bar -o \(Shell.quote(tmp)) \(Shell.quote(url))
        tar -xzf \(Shell.quote(tmp)) -C \(Shell.quote(dest))
        rm -rf \(Shell.quote("\(dest)/\(version)"))
        mv \(Shell.quote("\(dest)/\(name)")) \(Shell.quote("\(dest)/\(version)"))
        rm -f \(Shell.quote(tmp))
        """
        await runJob("Node \(version) kurulumu", "/bin/zsh", ["-c", script])
        detectNode()
        if config.defaultNode == nil, let n = nodeVersion(version) { setDefaultNode(n) }
    }

    func uninstallNode(_ n: NodeVersion) async {
        if n.managed {
            try? FileManager.default.removeItem(atPath: n.path)
        } else {
            await brew("Node \(n.version) kaldırılıyor", ["uninstall", (n.path as NSString).lastPathComponent])
        }
        if config.defaultNode == n.version { config.defaultNode = nil }
        detectNode()
        linkDefaults()
    }

    func setDefaultNode(_ n: NodeVersion) {
        config.defaultNode = n.version
        linkDefaults()
    }

    static var isAppleSilicon: Bool {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafeBytes(of: &sysinfo.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return machine.hasPrefix("arm64")
    }
}
