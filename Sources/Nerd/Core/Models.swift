import Foundation

// MARK: - Config

struct SiteConfig: Codable, Hashable {
    var php: String?
    var node: String?
    var secure: Bool = false

    init(php: String? = nil, node: String? = nil, secure: Bool = false) {
        self.php = php
        self.node = node
        self.secure = secure
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        php = try c.decodeIfPresent(String.self, forKey: .php)
        node = try c.decodeIfPresent(String.self, forKey: .node)
        secure = try c.decodeIfPresent(Bool.self, forKey: .secure) ?? false
    }
}

struct AppConfig: Codable {
    var parkedPaths: [String] = [Paths.home.appendingPathComponent("Sites").path]
    var linkedPaths: [String] = []
    var sites: [String: SiteConfig] = [:]
    var defaultPHP: String?
    var defaultNode: String?
    var tld: String = "test"
    var httpPort: Int = 80
    var httpsPort: Int = 443
    var dnsPort: Int = 53535
    var autostart: Bool = true
    var editor: String = "Visual Studio Code"
    var connections: [DBConnection] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppConfig()
        parkedPaths = try c.decodeIfPresent([String].self, forKey: .parkedPaths) ?? d.parkedPaths
        linkedPaths = try c.decodeIfPresent([String].self, forKey: .linkedPaths) ?? d.linkedPaths
        sites = try c.decodeIfPresent([String: SiteConfig].self, forKey: .sites) ?? d.sites
        defaultPHP = try c.decodeIfPresent(String.self, forKey: .defaultPHP)
        defaultNode = try c.decodeIfPresent(String.self, forKey: .defaultNode)
        tld = try c.decodeIfPresent(String.self, forKey: .tld) ?? d.tld
        httpPort = try c.decodeIfPresent(Int.self, forKey: .httpPort) ?? d.httpPort
        httpsPort = try c.decodeIfPresent(Int.self, forKey: .httpsPort) ?? d.httpsPort
        dnsPort = try c.decodeIfPresent(Int.self, forKey: .dnsPort) ?? d.dnsPort
        autostart = try c.decodeIfPresent(Bool.self, forKey: .autostart) ?? d.autostart
        editor = try c.decodeIfPresent(String.self, forKey: .editor) ?? d.editor
        connections = try c.decodeIfPresent([DBConnection].self, forKey: .connections) ?? d.connections
    }
}

// MARK: - Sites

struct Site: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let path: URL
    let docroot: URL
    let isLaravel: Bool
    let linked: Bool
    var config: SiteConfig

    var hasPackageJSON: Bool {
        FileManager.default.fileExists(atPath: path.appendingPathComponent("package.json").path)
    }
}

// MARK: - PHP

struct PHPVersion: Identifiable, Hashable {
    var id: String { version }
    let version: String          // "8.4"
    let formula: String          // "php@8.4" / "php"
    let prefix: String           // /opt/homebrew/opt/php@8.4
    let installed: Bool

    var bin: String { prefix + "/bin/php" }
    var binDir: String { prefix + "/bin" }
    var fpm: String { prefix + "/sbin/php-fpm" }
    var ini: String { "\(Paths.brew)/etc/php/\(version)/php.ini" }
    var key: String { "php" + version.replacingOccurrences(of: ".", with: "") }
    var socket: String { Paths.run.appendingPathComponent("\(key).sock").path }
}

// MARK: - Node

struct NodeVersion: Identifiable, Hashable {
    var id: String { path }
    let version: String          // "v22.11.0"
    let path: String             // install root
    let managed: Bool            // installed by Nerd

    var binDir: String { path + "/bin" }
    var major: Int { Int(version.dropFirst().split(separator: ".").first ?? "0") ?? 0 }
    var label: String { managed ? version : "\(version) (Homebrew)" }
}

struct RemoteNode: Identifiable, Hashable {
    var id: String { version }
    let version: String
    let lts: String?
    let date: String
    var major: Int { Int(version.dropFirst().split(separator: ".").first ?? "0") ?? 0 }
}

// MARK: - Services

struct ServiceDef: Identifiable, Hashable {
    var id: String { formula }
    let formula: String
    let name: String
    let port: Int?
    let icon: String
    var webUI: String? = nil

    static let catalog: [ServiceDef] = [
        ServiceDef(formula: "mysql", name: "MySQL", port: 3306, icon: "cylinder.split.1x2"),
        ServiceDef(formula: "mariadb", name: "MariaDB", port: 3306, icon: "cylinder.split.1x2"),
        ServiceDef(formula: "postgresql@17", name: "PostgreSQL 17", port: 5432, icon: "cylinder"),
        ServiceDef(formula: "postgresql@18", name: "PostgreSQL 18", port: 5432, icon: "cylinder"),
        ServiceDef(formula: "redis", name: "Redis", port: 6379, icon: "bolt.horizontal"),
        ServiceDef(formula: "valkey", name: "Valkey", port: 6379, icon: "bolt.horizontal"),
        ServiceDef(formula: "memcached", name: "Memcached", port: 11211, icon: "memorychip"),
        ServiceDef(formula: "mailpit", name: "Mailpit", port: 1025, icon: "envelope", webUI: "http://localhost:8025"),
        ServiceDef(formula: "meilisearch", name: "Meilisearch", port: 7700, icon: "magnifyingglass", webUI: "http://localhost:7700"),
        ServiceDef(formula: "minio", name: "MinIO", port: 9000, icon: "externaldrive", webUI: "http://localhost:9000"),
    ]
}

struct ServiceStatus: Hashable {
    var installed: Bool
    var status: String   // started, stopped, none, error

    var isRunning: Bool { status == "started" }
}

// MARK: - Database

enum DBDriver: String, Codable, CaseIterable, Identifiable {
    case sqlite, mysql, pgsql
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sqlite: "SQLite"
        case .mysql: "MySQL / MariaDB"
        case .pgsql: "PostgreSQL"
        }
    }
    var defaultPort: Int {
        switch self {
        case .sqlite: 0
        case .mysql: 3306
        case .pgsql: 5432
        }
    }
}

struct DBConnection: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String = ""
    var driver: DBDriver = .mysql
    var host: String = "127.0.0.1"
    var port: Int = 3306
    var username: String = "root"
    var password: String = ""
    var database: String = ""
    var file: String = ""
    var site: String? = nil

    var summary: String {
        switch driver {
        case .sqlite: (file as NSString).abbreviatingWithTildeInPath
        default: "\(username)@\(host):\(port)/\(database)"
        }
    }
}

// MARK: - Project templates

enum ProjectTemplate: String, CaseIterable, Identifiable {
    case blade, livewire, react, vue, svelte, plain, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .blade: "Blade"
        case .livewire: "Livewire"
        case .react: "Inertia + React"
        case .vue: "Inertia + Vue"
        case .svelte: "Inertia + Svelte"
        case .plain: "Boş PHP"
        case .custom: "Özel paket"
        }
    }

    var subtitle: String {
        switch self {
        case .blade: "laravel/laravel — sade Laravel iskeleti"
        case .livewire: "Resmi Livewire starter kit (Flux UI)"
        case .react: "Resmi React starter kit (TypeScript, shadcn)"
        case .vue: "Resmi Vue starter kit (TypeScript, shadcn-vue)"
        case .svelte: "Resmi Svelte starter kit"
        case .plain: "public/index.php ile boş klasör"
        case .custom: "Herhangi bir composer create-project paketi"
        }
    }

    var icon: String {
        switch self {
        case .blade: "leaf"
        case .livewire: "bolt"
        case .react: "atom"
        case .vue: "v.circle"
        case .svelte: "s.circle"
        case .plain: "doc"
        case .custom: "shippingbox"
        }
    }

    var package: String? {
        switch self {
        case .blade: "laravel/laravel"
        case .livewire: "laravel/livewire-starter-kit"
        case .react: "laravel/react-starter-kit"
        case .vue: "laravel/vue-starter-kit"
        case .svelte: "laravel/svelte-starter-kit"
        case .plain, .custom: nil
        }
    }
}
