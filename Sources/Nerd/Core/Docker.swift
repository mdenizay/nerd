import Foundation

/// Production Docker setup generator, aimed at Dokploy (Docker Compose apps) but
/// usable anywhere `docker compose` runs.
struct DockerPlan {
    var files: [(name: String, content: String)]
    var port: Int
    var services: [String]
}

private enum PackageManager {
    case npm, pnpm, yarn

    static func detect(_ dir: URL) -> PackageManager {
        let fm = FileManager.default
        if fm.fileExists(atPath: dir.appendingPathComponent("pnpm-lock.yaml").path) { return .pnpm }
        if fm.fileExists(atPath: dir.appendingPathComponent("yarn.lock").path) { return .yarn }
        return .npm
    }

    func install(_ dir: URL) -> String {
        switch self {
        case .pnpm: "corepack enable && pnpm install --frozen-lockfile"
        case .yarn: "corepack enable && yarn install --frozen-lockfile"
        case .npm:
            FileManager.default.fileExists(atPath: dir.appendingPathComponent("package-lock.json").path) ? "npm ci" : "npm install"
        }
    }

    var lockfiles: String {
        switch self {
        case .pnpm: "pnpm-lock.yaml"
        case .yarn: "yarn.lock"
        case .npm: "package-lock.json*"
        }
    }

    var run: String {
        switch self {
        case .pnpm: "pnpm run"
        case .yarn: "yarn run"
        case .npm: "npm run"
        }
    }
}

extension AppState {
    static let dockerFileNames = ["Dockerfile", "docker-compose.yml", ".dockerignore"]

    func dockerFilesExist(_ site: Site) -> Bool {
        Self.dockerFileNames.contains { FileManager.default.fileExists(atPath: site.path.appendingPathComponent($0).path) }
    }

    var dockerBinary: String? {
        Shell.which("docker") ?? [
            Paths.home.appendingPathComponent(".orbstack/bin/docker").path,
            "/Applications/Docker.app/Contents/Resources/bin/docker",
        ].first(where: Paths.exists)
    }

    @discardableResult
    func writeDockerFiles(_ site: Site) -> [String] {
        let plan = dockerPlan(for: site)
        for f in plan.files {
            try? f.content.write(to: site.path.appendingPathComponent(f.name), atomically: true, encoding: .utf8)
        }
        if site.kind == .next { Self.enableNextStandalone(site.path) }
        return plan.files.map(\.name)
    }

    func dockerUp(_ site: Site) async {
        guard let docker = dockerBinary else { return }
        await runJob("\(site.name): docker compose up", docker, ["compose", "up", "--build", "-d"], cwd: site.path)
    }

    func dockerDown(_ site: Site) async {
        guard let docker = dockerBinary else { return }
        await runJob("\(site.name): docker compose down", docker, ["compose", "down"], cwd: site.path)
    }

    /// `Nerd docker <dir>`: write Docker files for a project without opening the UI.
    func cliDocker(_ path: String) -> Int32 {
        Paths.ensure()
        loadConfigForCLI()
        detectPHP()
        detectNode()
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("Klasör bulunamadı: \(url.path)")
            return 1
        }
        let site = adhocSite(url)
        let plan = dockerPlan(for: site)
        for f in writeDockerFiles(site) { print("✓ \(f)") }
        print("\(site.kind.title) · port \(plan.port) · servisler: \(plan.services.joined(separator: ", "))")
        return 0
    }

    /// A Site value for a folder that may not be registered (yet).
    func adhocSite(_ url: URL) -> Site {
        let pub = url.appendingPathComponent("public")
        let name = Self.slug(url.lastPathComponent)
        return Site(name: name, path: url,
                    docroot: FileManager.default.fileExists(atPath: pub.path) ? pub : url,
                    kind: Self.detectKind(url), linked: true, config: config.sites[name] ?? SiteConfig())
    }

    // MARK: Plan

    func dockerPlan(for site: Site) -> DockerPlan {
        let nodeMajor = node(for: site)?.major ?? 22
        switch site.kind {
        case .laravel: return laravelPlan(site, nodeMajor: nodeMajor)
        case .next: return nextPlan(site, nodeMajor: nodeMajor)
        case .astro: return astroPlan(site, nodeMajor: nodeMajor)
        default: return phpPlan(site)
        }
    }

    private func phpVersionTag(_ site: Site) -> String { php(for: site)?.version ?? "8.4" }

    private func header(_ port: Int) -> String {
        """
        # Nerd tarafından oluşturuldu.
        #
        # Dokploy: "Compose" türünde uygulama oluşturun, bu repoyu bağlayın ve
        # Domains sekmesinden "app" servisine \(port) portuyla domain ekleyin.
        # Gizli değerleri (APP_KEY, şifreler…) Environment sekmesine yazın;
        # Dokploy bunları bu dosyanın yanındaki .env'e koyar.
        #
        # Yerelde: docker compose up --build

        """
    }

    // MARK: Laravel

    private func laravelPlan(_ site: Site, nodeMajor: Int) -> DockerPlan {
        let env = Self.parseEnv(site.path.appendingPathComponent(".env"))
        let driver = env["DB_CONNECTION"] ?? "sqlite"
        let usesRedis = ["CACHE_STORE", "QUEUE_CONNECTION", "SESSION_DRIVER", "BROADCAST_CONNECTION"]
            .contains { env[$0] == "redis" }
        let usesQueue = (env["QUEUE_CONNECTION"] ?? "database") != "sync"
        let hasFrontend = site.hasPackageJSON
        let pm = PackageManager.detect(site.path)
        let php = phpVersionTag(site)
        let dbName = Self.slug(site.name).replacingOccurrences(of: "-", with: "_")

        var dockerfile = """
        # syntax=docker/dockerfile:1
        # Nerd tarafından oluşturuldu — Laravel production imajı (serversideup/php)

        ARG PHP_VERSION=\(php)

        FROM serversideup/php:${PHP_VERSION}-cli AS build
        USER root
        WORKDIR /var/www/html

        """
        if hasFrontend {
            dockerfile += """
            # Node.js (Vite / Wayfinder derlemesi PHP'ye de ihtiyaç duyabilir)
            COPY --from=node:\(nodeMajor)-bookworm-slim /usr/local/bin/node /usr/local/bin/node
            COPY --from=node:\(nodeMajor)-bookworm-slim /usr/local/lib/node_modules /usr/local/lib/node_modules
            RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \\
             && ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \\
             && ln -s /usr/local/lib/node_modules/corepack/dist/corepack.js /usr/local/bin/corepack


            """
        }
        dockerfile += """
        COPY composer.json composer.lock ./
        RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist --no-interaction

        """
        if hasFrontend {
            dockerfile += """

            COPY package.json \(pm.lockfiles) ./
            RUN \(pm.install(site.path))

            """
        }
        dockerfile += """

        COPY . .
        RUN composer dump-autoload --optimize --no-dev --classmap-authoritative
        """
        if hasFrontend {
            dockerfile += " \\\n && \(pm.run) build \\\n && rm -rf node_modules"
        }
        dockerfile += """


        FROM serversideup/php:${PHP_VERSION}-fpm-nginx
        USER root
        RUN install-php-extensions intl bcmath
        USER www-data
        WORKDIR /var/www/html
        COPY --from=build --chown=www-data:www-data /var/www/html /var/www/html

        ENV PHP_OPCACHE_ENABLE=1 \\
            LOG_CHANNEL=stderr

        """

        // Compose
        var dbEnv: [String] = []
        var dbService = ""
        var dependsOn: [String] = []
        var volumes = ["storage"]
        switch driver {
        case "mysql", "mariadb":
            dbEnv = ["DB_CONNECTION: mysql", "DB_HOST: db", "DB_PORT: \"3306\"",
                     "DB_DATABASE: ${DB_DATABASE:-\(dbName)}", "DB_USERNAME: ${DB_USERNAME:-laravel}",
                     "DB_PASSWORD: ${DB_PASSWORD:?DB_PASSWORD gerekli}"]
            dbService = """
              db:
                image: mysql:8.4
                restart: unless-stopped
                environment:
                  MYSQL_DATABASE: ${DB_DATABASE:-\(dbName)}
                  MYSQL_USER: ${DB_USERNAME:-laravel}
                  MYSQL_PASSWORD: ${DB_PASSWORD:?DB_PASSWORD gerekli}
                  MYSQL_ROOT_PASSWORD: ${DB_ROOT_PASSWORD:-${DB_PASSWORD}}
                volumes:
                  - db-data:/var/lib/mysql
                healthcheck:
                  test: ["CMD", "mysqladmin", "ping", "-h", "127.0.0.1", "--silent"]
                  interval: 5s
                  timeout: 5s
                  retries: 20

            """
            dependsOn.append("db")
            volumes.append("db-data")
        case "pgsql":
            dbEnv = ["DB_CONNECTION: pgsql", "DB_HOST: db", "DB_PORT: \"5432\"",
                     "DB_DATABASE: ${DB_DATABASE:-\(dbName)}", "DB_USERNAME: ${DB_USERNAME:-laravel}",
                     "DB_PASSWORD: ${DB_PASSWORD:?DB_PASSWORD gerekli}"]
            dbService = """
              db:
                image: postgres:17-alpine
                restart: unless-stopped
                environment:
                  POSTGRES_DB: ${DB_DATABASE:-\(dbName)}
                  POSTGRES_USER: ${DB_USERNAME:-laravel}
                  POSTGRES_PASSWORD: ${DB_PASSWORD:?DB_PASSWORD gerekli}
                volumes:
                  - db-data:/var/lib/postgresql/data
                healthcheck:
                  test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
                  interval: 5s
                  timeout: 5s
                  retries: 20

            """
            dependsOn.append("db")
            volumes.append("db-data")
        default:
            // SQLite lives on the persistent storage volume
            dbEnv = ["DB_CONNECTION: sqlite", "DB_DATABASE: /var/www/html/storage/app/database.sqlite"]
        }

        var redisService = ""
        if usesRedis {
            dbEnv += ["REDIS_HOST: redis", "REDIS_PORT: \"6379\""]
            redisService = """
              redis:
                image: redis:7-alpine
                restart: unless-stopped
                volumes:
                  - redis-data:/data
                healthcheck:
                  test: ["CMD", "redis-cli", "ping"]
                  interval: 5s
                  timeout: 3s
                  retries: 20

            """
            dependsOn.append("redis")
            volumes.append("redis-data")
        }

        let envLines = (["APP_ENV: ${APP_ENV:-production}", "APP_DEBUG: ${APP_DEBUG:-false}", "APP_KEY: ${APP_KEY:?APP_KEY gerekli (php artisan key:generate --show)}",
                         "APP_URL: ${APP_URL:-http://localhost:8080}", "LOG_CHANNEL: stderr"] + dbEnv)
            .map { "    \($0)" }.joined(separator: "\n")
        let dependsBlock = dependsOn.isEmpty ? "" : "  depends_on:\n" + dependsOn.map { "    \($0):\n      condition: service_healthy" }.joined(separator: "\n") + "\n"

        var compose = header(8080) + """
        x-app: &app
          build:
            context: .
          restart: unless-stopped
          env_file:
            - path: .env
              required: false
          environment: &app-env
        \(envLines)
          volumes:
            - storage:/var/www/html/storage
        \(dependsBlock)
        services:
          app:
            <<: *app
            expose:
              - "8080"
            environment:
              <<: *app-env
              AUTORUN_ENABLED: "true"

        """
        var services = ["app"]
        if usesQueue {
            services.append("queue")
            compose += """
              queue:
                <<: *app
                command: ["php", "/var/www/html/artisan", "queue:work", "--tries=3", "--sleep=3"]
                stop_signal: SIGTERM
                depends_on:
                  app:
                    condition: service_healthy
                healthcheck:
                  test: ["CMD", "healthcheck-queue"]
                  start_period: 10s

            """
        }
        services.append("scheduler")
        compose += """
          scheduler:
            <<: *app
            command: ["php", "/var/www/html/artisan", "schedule:work"]
            stop_signal: SIGTERM
            depends_on:
              app:
                condition: service_healthy
            healthcheck:
              test: ["CMD", "healthcheck-schedule"]
              start_period: 10s

        """
        if !dbService.isEmpty { compose += dbService; services.append("db") }
        if !redisService.isEmpty { compose += redisService; services.append("redis") }
        compose += "volumes:\n" + volumes.map { "  \($0):" }.joined(separator: "\n") + "\n"

        let ignore = """
        .git
        .env
        .env.*
        !.env.example
        node_modules
        vendor
        public/build
        public/hot
        public/storage
        storage/*.key
        storage/logs/*
        storage/framework/cache/*
        storage/framework/sessions/*
        storage/framework/views/*
        database/*.sqlite*
        tests
        .phpunit.result.cache
        docker-compose.yml
        Dockerfile
        .dockerignore
        .idea
        .vscode
        .DS_Store

        """
        return DockerPlan(files: [("Dockerfile", dockerfile), ("docker-compose.yml", compose), (".dockerignore", ignore)],
                          port: 8080, services: services)
    }

    // MARK: Plain PHP

    private func phpPlan(_ site: Site) -> DockerPlan {
        let hasPublic = site.docroot != site.path
        let dockerfile = """
        # syntax=docker/dockerfile:1
        # Nerd tarafından oluşturuldu — PHP production imajı (serversideup/php)
        FROM serversideup/php:\(phpVersionTag(site))-fpm-nginx
        \(hasPublic ? "" : "ENV NGINX_WEBROOT=/var/www/html\n")WORKDIR /var/www/html
        COPY --chown=www-data:www-data . .
        \(FileManager.default.fileExists(atPath: site.path.appendingPathComponent("composer.json").path)
          ? "RUN composer install --no-dev --optimize-autoloader --no-interaction\n" : "")
        """
        let compose = header(8080) + """
        services:
          app:
            build:
              context: .
            restart: unless-stopped
            env_file:
              - path: .env
                required: false
            expose:
              - "8080"

        """
        return DockerPlan(files: [("Dockerfile", dockerfile), ("docker-compose.yml", compose), (".dockerignore", ".git\n.env\nvendor\nnode_modules\n.DS_Store\n")],
                          port: 8080, services: ["app"])
    }

    // MARK: Next.js

    private func nextPlan(_ site: Site, nodeMajor: Int) -> DockerPlan {
        let pm = PackageManager.detect(site.path)
        let hasPublic = FileManager.default.fileExists(atPath: site.path.appendingPathComponent("public").path)
        let dockerfile = """
        # syntax=docker/dockerfile:1
        # Nerd tarafından oluşturuldu — Next.js (output: "standalone")

        FROM node:\(nodeMajor)-alpine AS deps
        WORKDIR /app
        COPY package.json \(pm.lockfiles) ./
        RUN \(pm.install(site.path))

        FROM node:\(nodeMajor)-alpine AS build
        WORKDIR /app
        ENV NEXT_TELEMETRY_DISABLED=1
        COPY --from=deps /app/node_modules ./node_modules
        COPY . .
        RUN \(pm == .npm ? "npm run" : "corepack enable && \(pm.run)") build

        FROM node:\(nodeMajor)-alpine
        WORKDIR /app
        ENV NODE_ENV=production \\
            NEXT_TELEMETRY_DISABLED=1 \\
            PORT=3000 \\
            HOSTNAME=0.0.0.0
        RUN addgroup -S -g 1001 nodejs && adduser -S -u 1001 -G nodejs nextjs
        \(hasPublic ? "COPY --from=build --chown=nextjs:nodejs /app/public ./public\n" : "")COPY --from=build --chown=nextjs:nodejs /app/.next/standalone ./
        COPY --from=build --chown=nextjs:nodejs /app/.next/static ./.next/static
        USER nextjs
        EXPOSE 3000
        CMD ["node", "server.js"]

        """
        return DockerPlan(files: [("Dockerfile", dockerfile), ("docker-compose.yml", nodeCompose(3000)), (".dockerignore", nodeIgnore + ".next\n")],
                          port: 3000, services: ["app"])
    }

    // MARK: Astro

    private func astroPlan(_ site: Site, nodeMajor: Int) -> DockerPlan {
        let pm = PackageManager.detect(site.path)
        let config = ["astro.config.mjs", "astro.config.ts", "astro.config.js"]
            .compactMap { try? String(contentsOf: site.path.appendingPathComponent($0), encoding: .utf8) }.first ?? ""
        let ssr = config.contains("@astrojs/node")
        let build = """
        # syntax=docker/dockerfile:1
        # Nerd tarafından oluşturuldu — Astro (\(ssr ? "SSR, @astrojs/node" : "statik"))

        FROM node:\(nodeMajor)-alpine AS build
        WORKDIR /app
        COPY package.json \(pm.lockfiles) ./
        RUN \(pm.install(site.path))
        COPY . .
        RUN \(pm == .npm ? "npm run" : "corepack enable && \(pm.run)") build


        """
        let dockerfile: String
        let port: Int
        if ssr {
            port = 4321
            dockerfile = build + """
            FROM node:\(nodeMajor)-alpine
            WORKDIR /app
            ENV NODE_ENV=production HOST=0.0.0.0 PORT=4321
            COPY --from=build /app/node_modules ./node_modules
            COPY --from=build /app/dist ./dist
            USER node
            EXPOSE 4321
            CMD ["node", "./dist/server/entry.mjs"]

            """
        } else {
            port = 80
            dockerfile = build + """
            FROM nginx:1.27-alpine
            COPY --from=build /app/dist /usr/share/nginx/html
            EXPOSE 80

            """
        }
        return DockerPlan(files: [("Dockerfile", dockerfile), ("docker-compose.yml", nodeCompose(port)), (".dockerignore", nodeIgnore + "dist\n.astro\n")],
                          port: port, services: ["app"])
    }

    private var nodeIgnore: String {
        ".git\n.env\n.env.*\nnode_modules\nnpm-debug.log*\nDockerfile\ndocker-compose.yml\n.dockerignore\n.DS_Store\n"
    }

    private func nodeCompose(_ port: Int) -> String {
        header(port) + """
        services:
          app:
            build:
              context: .
            restart: unless-stopped
            env_file:
              - path: .env
                required: false
            expose:
              - "\(port)"

        """
    }

    /// The Next.js Dockerfile needs `output: "standalone"`.
    static func enableNextStandalone(_ dir: URL) {
        for file in ["next.config.ts", "next.config.mjs", "next.config.js"] {
            let url = dir.appendingPathComponent(file)
            guard var s = try? String(contentsOf: url, encoding: .utf8) else { continue }
            guard !s.contains("standalone") else { return }
            if let r = s.range(of: #"nextConfig(\s*:\s*NextConfig)?\s*=\s*\{"#, options: .regularExpression) {
                s.replaceSubrange(r, with: s[r] + "\n  output: \"standalone\",")
                try? s.write(to: url, atomically: true, encoding: .utf8)
            }
            return
        }
    }
}
