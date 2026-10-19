import Foundation
import SwiftUI

// MARK: - Config

struct SiteConfig: Codable, Hashable {
    var php: String?
    var node: String?
    var secure: Bool = false
    var port: Int?   // dev server port for proxied apps (Next.js, Astro, .NET)
    var dotnet: String?

    init(php: String? = nil, node: String? = nil, secure: Bool = false, port: Int? = nil, dotnet: String? = nil) {
        self.php = php
        self.node = node
        self.secure = secure
        self.port = port
        self.dotnet = dotnet
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        php = try c.decodeIfPresent(String.self, forKey: .php)
        node = try c.decodeIfPresent(String.self, forKey: .node)
        secure = try c.decodeIfPresent(Bool.self, forKey: .secure) ?? false
        port = try c.decodeIfPresent(Int.self, forKey: .port)
        dotnet = try c.decodeIfPresent(String.self, forKey: .dotnet)
    }
}

struct AppConfig: Codable {
    var parkedPaths: [String] = [Paths.home.appendingPathComponent("Sites").path]
    var linkedPaths: [String] = []
    /// Site name chosen for a linked folder (`nerd link name`), keyed by path.
    var linkNames: [String: String] = [:]
    /// Proxy-only sites: name → upstream ("localhost:5173" or "http://host:port").
    var proxies: [String: String] = [:]
    var sites: [String: SiteConfig] = [:]
    var defaultPHP: String?
    var defaultNode: String?
    var defaultDotnet: String?
    var tld: String = "test"
    var httpPort: Int = 80
    var httpsPort: Int = 443
    var dnsPort: Int = 53535
    var autostart: Bool = true
    var editor: String = "Visual Studio Code"
    var connections: [DBConnection] = []
    var mailPort: Int = 2525
    var dumpPort: Int = 9913
    var dumpsInBrowser: Bool = true
    var dumpsCLI: Bool = false
    var appearance: Appearance = .system

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppConfig()
        parkedPaths = try c.decodeIfPresent([String].self, forKey: .parkedPaths) ?? d.parkedPaths
        linkedPaths = try c.decodeIfPresent([String].self, forKey: .linkedPaths) ?? d.linkedPaths
        linkNames = try c.decodeIfPresent([String: String].self, forKey: .linkNames) ?? d.linkNames
        proxies = try c.decodeIfPresent([String: String].self, forKey: .proxies) ?? d.proxies
        sites = try c.decodeIfPresent([String: SiteConfig].self, forKey: .sites) ?? d.sites
        defaultPHP = try c.decodeIfPresent(String.self, forKey: .defaultPHP)
        defaultNode = try c.decodeIfPresent(String.self, forKey: .defaultNode)
        defaultDotnet = try c.decodeIfPresent(String.self, forKey: .defaultDotnet)
        tld = try c.decodeIfPresent(String.self, forKey: .tld) ?? d.tld
        httpPort = try c.decodeIfPresent(Int.self, forKey: .httpPort) ?? d.httpPort
        httpsPort = try c.decodeIfPresent(Int.self, forKey: .httpsPort) ?? d.httpsPort
        dnsPort = try c.decodeIfPresent(Int.self, forKey: .dnsPort) ?? d.dnsPort
        autostart = try c.decodeIfPresent(Bool.self, forKey: .autostart) ?? d.autostart
        editor = try c.decodeIfPresent(String.self, forKey: .editor) ?? d.editor
        connections = try c.decodeIfPresent([DBConnection].self, forKey: .connections) ?? d.connections
        mailPort = try c.decodeIfPresent(Int.self, forKey: .mailPort) ?? d.mailPort
        dumpPort = try c.decodeIfPresent(Int.self, forKey: .dumpPort) ?? d.dumpPort
        dumpsInBrowser = try c.decodeIfPresent(Bool.self, forKey: .dumpsInBrowser) ?? d.dumpsInBrowser
        dumpsCLI = try c.decodeIfPresent(Bool.self, forKey: .dumpsCLI) ?? d.dumpsCLI
        appearance = (try? c.decodeIfPresent(Appearance.self, forKey: .appearance)) ?? d.appearance
    }
}

enum Appearance: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: String(localized: "Sistem")
        case .light: String(localized: "Açık")
        case .dark: String(localized: "Koyu")
        }
    }
}

// MARK: - Sites

enum SiteKind: String, Hashable {
    case laravel, php, next, astro, dotnet, node, plain, proxy

    var title: String {
        switch self {
        case .laravel: String(localized: "Laravel")
        case .php: String(localized: "PHP")
        case .next: String(localized: "Next.js")
        case .astro: String(localized: "Astro")
        case .dotnet: ".NET"
        case .node: String(localized: "Node")
        case .plain: String(localized: "Statik")
        case .proxy: String(localized: "Proxy")
        }
    }

    var icon: String {
        switch self {
        case .laravel: "leaf.fill"
        case .php: "chevron.left.forwardslash.chevron.right"
        case .next: "triangle.fill"
        case .astro: "sparkles"
        case .dotnet: "number"
        case .node: "hexagon.fill"
        case .plain: "doc.fill"
        case .proxy: "arrow.left.arrow.right"
        }
    }

    var color: Color {
        switch self {
        case .laravel: .red
        case .php: .indigo
        case .next: .primary
        case .astro: .orange
        case .dotnet: .purple
        case .node: .green
        case .plain: .secondary
        case .proxy: .blue
        }
    }

    var badgeColor: Color {
        switch self {
        case .laravel: .red
        case .php: .indigo
        case .next: .primary
        case .astro: .purple
        case .dotnet: .purple
        case .node: .green
        case .plain: .gray
        case .proxy: .blue
        }
    }

    /// Served by proxying to a Node dev server instead of PHP-FPM.
    var isNodeApp: Bool { self == .next || self == .astro }

    /// Simple Icons slug of the technology's logo.
    var brand: String? {
        switch self {
        case .laravel: "laravel"
        case .php: "php"
        case .next: "nextdotjs"
        case .astro: "astro"
        case .dotnet: "dotnet"
        case .node: "nodedotjs"
        case .plain, .proxy: nil
        }
    }

    /// Served by proxying to the project's own dev server.
    var isProxied: Bool { isNodeApp || self == .dotnet }
}

struct Site: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let path: URL
    let docroot: URL
    let kind: SiteKind
    let linked: Bool
    var config: SiteConfig
    /// Upstream of a proxy-only site; such a site has no folder of its own.
    var proxyTarget: String? = nil

    var isLaravel: Bool { kind == .laravel }
    var isProxy: Bool { kind == .proxy }

    var hasPackageJSON: Bool {
        !isProxy && FileManager.default.fileExists(atPath: path.appendingPathComponent("package.json").path)
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

// MARK: - .NET

struct DotnetVersion: Identifiable, Hashable {
    var id: String { major }
    let major: String            // "10", "9", "8"
    let formula: String          // "dotnet", "dotnet@8"
    let prefix: String           // /opt/homebrew/opt/dotnet@8
    let installed: Bool

    var bin: String { prefix + "/bin/dotnet" }
    var binDir: String { prefix + "/bin" }
    var root: String { prefix + "/libexec" }
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

    var brand: String? {
        switch formula {
        case "mysql": "mysql"
        case "mariadb": "mariadb"
        case "postgresql@17", "postgresql@18": "postgresql"
        case "redis": "redis"
        case "meilisearch": "meilisearch"
        case "minio": "minio"
        default: nil
        }
    }

    var color: Color {
        switch formula {
        case "mysql": .blue
        case "mariadb": .brown
        case "redis": .red
        case "valkey": .pink
        case "memcached": .mint
        case "mailpit": .teal
        case "meilisearch": .purple
        case "minio": .orange
        default: .indigo // postgresql
        }
    }

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
        case .sqlite: String(localized: "SQLite")
        case .mysql: String(localized: "MySQL / MariaDB")
        case .pgsql: String(localized: "PostgreSQL")
        }
    }
    var color: Color {
        switch self {
        case .sqlite: .teal
        case .mysql: .blue
        case .pgsql: .indigo
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
    case blade, livewire, react, vue, svelte, next, astro, razor, mvc, webapi, blazor, plain, custom
    var id: String { rawValue }

    enum Group: String, CaseIterable {
        case laravel = "Laravel", javascript = "JavaScript", dotnet = ".NET", other = "Diğer"
        var title: String { self == .other ? String(localized: "Diğer") : rawValue }
    }

    var group: Group {
        switch self {
        case .blade, .livewire, .react, .vue, .svelte: .laravel
        case .next, .astro: .javascript
        case .razor, .mvc, .webapi, .blazor: .dotnet
        case .plain, .custom: .other
        }
    }

    var isNode: Bool { group == .javascript }
    var isDotnet: Bool { group == .dotnet }

    /// Simple Icons slug of the logo (Vue's logo is not bundled; see NOTICE.md).
    var brand: String? {
        switch self {
        case .blade: "laravel"
        case .livewire: "livewire"
        case .react: "react"
        case .vue: nil
        case .svelte: "svelte"
        case .next: "nextdotjs"
        case .astro: "astro"
        case .razor, .mvc, .webapi: "dotnet"
        case .blazor: "blazor"
        case .plain: "php"
        case .custom: "composer"
        }
    }

    /// `dotnet new` short name.
    var dotnetTemplate: String? {
        switch self {
        case .razor: "webapp"
        case .mvc: "mvc"
        case .webapi: "webapi"
        case .blazor: "blazor"
        default: nil
        }
    }

    var color: Color {
        switch self {
        case .blade: .red
        case .livewire: .pink
        case .react: .cyan
        case .vue: .green
        case .svelte: .orange
        case .next: .primary
        case .astro: .purple
        case .razor, .mvc, .webapi, .blazor: .purple
        case .plain: .indigo
        case .custom: .brown
        }
    }
    var isLaravel: Bool { group == .laravel }

    var title: String {
        switch self {
        case .blade: String(localized: "Blade")
        case .livewire: String(localized: "Livewire")
        case .react: String(localized: "Inertia + React")
        case .vue: String(localized: "Inertia + Vue")
        case .svelte: String(localized: "Inertia + Svelte")
        case .next: String(localized: "Next.js")
        case .astro: String(localized: "Astro")
        case .razor: "ASP.NET Razor Pages"
        case .mvc: "ASP.NET MVC"
        case .webapi: "ASP.NET Web API"
        case .blazor: "Blazor"
        case .plain: String(localized: "Boş PHP")
        case .custom: String(localized: "Özel paket")
        }
    }

    var subtitle: String {
        switch self {
        case .blade: String(localized: "laravel/laravel — sade Laravel iskeleti")
        case .livewire: String(localized: "Resmi Livewire starter kit (Flux UI)")
        case .react: String(localized: "Resmi React starter kit (TypeScript, shadcn)")
        case .vue: String(localized: "Resmi Vue starter kit (TypeScript, shadcn-vue)")
        case .svelte: String(localized: "Resmi Svelte starter kit")
        case .next: String(localized: "create-next-app — TypeScript, Tailwind, App Router")
        case .astro: String(localized: "create-astro — basics şablonu")
        case .razor: String(localized: "dotnet new webapp — sunucu tarafı sayfalar")
        case .mvc: String(localized: "dotnet new mvc — model, view, controller")
        case .webapi: String(localized: "dotnet new webapi — REST API, OpenAPI")
        case .blazor: String(localized: "dotnet new blazor — etkileşimli web arayüzü")
        case .plain: String(localized: "public/index.php ile boş klasör")
        case .custom: String(localized: "Herhangi bir composer create-project paketi")
        }
    }

    var icon: String {
        switch self {
        case .blade: "leaf.fill"
        case .livewire: "bolt.fill"
        case .react: "atom"
        case .vue: "v.circle.fill"
        case .svelte: "s.circle.fill"
        case .next: "triangle.fill"
        case .astro: "sparkles"
        case .razor: "doc.richtext"
        case .mvc: "square.split.2x2"
        case .webapi: "point.3.connected.trianglepath.dotted"
        case .blazor: "flame"
        case .plain: "doc.fill"
        case .custom: "shippingbox.fill"
        }
    }

    var package: String? {
        switch self {
        case .blade: "laravel/laravel"
        case .livewire: "laravel/livewire-starter-kit"
        case .react: "laravel/react-starter-kit"
        case .vue: "laravel/vue-starter-kit"
        case .svelte: "laravel/svelte-starter-kit"
        case .next, .astro, .razor, .mvc, .webapi, .blazor, .plain, .custom: nil
        }
    }
}
