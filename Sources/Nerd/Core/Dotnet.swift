import Foundation

/// .NET SDKs from Homebrew, ASP.NET projects served through `dotnet watch`.
extension AppState {
    static let knownDotnet: [(major: String, formula: String)] = [("10", "dotnet"), ("9", "dotnet@9"), ("8", "dotnet@8")]

    var installedDotnet: [DotnetVersion] { dotnetVersions.filter(\.installed) }

    var defaultDotnet: DotnetVersion? {
        installedDotnet.first { $0.major == config.defaultDotnet } ?? installedDotnet.first
    }

    func dotnetVersion(_ major: String?) -> DotnetVersion? {
        guard let major else { return nil }
        return installedDotnet.first { $0.major == major }
    }

    func dotnet(for site: Site) -> DotnetVersion? {
        dotnetVersion(site.config.dotnet) ?? defaultDotnet
    }

    func detectDotnet() {
        let brew = Paths.brew
        // `dotnet` is whatever major is current; read it from the Cellar path
        var latestMajor: String?
        if let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: "\(brew)/opt/dotnet"),
           let full = dest.split(separator: "/").last {
            latestMajor = full.split(separator: ".").first.map(String.init)
        }
        dotnetVersions = Self.knownDotnet.map { known in
            let versioned = "\(brew)/opt/dotnet@\(known.major)"
            if Paths.exists("\(versioned)/bin/dotnet") {
                return DotnetVersion(major: known.major, formula: latestMajor == known.major ? "dotnet" : "dotnet@\(known.major)",
                                     prefix: versioned, installed: true)
            }
            if latestMajor == known.major, Paths.exists("\(brew)/opt/dotnet/bin/dotnet") {
                return DotnetVersion(major: known.major, formula: "dotnet", prefix: "\(brew)/opt/dotnet", installed: true)
            }
            return DotnetVersion(major: known.major, formula: known.formula, prefix: versioned, installed: false)
        }
    }

    func installDotnet(_ v: DotnetVersion) async {
        busy.insert("dotnet-\(v.major)")
        defer { busy.remove("dotnet-\(v.major)") }
        await brew(".NET \(v.major) kurulumu", ["install", v.formula])
        detectDotnet()
    }

    func uninstallDotnet(_ v: DotnetVersion) async {
        busy.insert("dotnet-\(v.major)")
        defer { busy.remove("dotnet-\(v.major)") }
        await brew(".NET \(v.major) kaldırılıyor", ["uninstall", v.formula])
        if config.defaultDotnet == v.major { config.defaultDotnet = nil }
        detectDotnet()
    }

    func setDefaultDotnet(_ v: DotnetVersion) {
        config.defaultDotnet = v.major
        link(v.bin, as: "dotnet")
    }

    func dotnetEnv(_ v: DotnetVersion, _ extra: [String: String] = [:]) -> [String: String] {
        Shell.env(prependPath: [v.binDir], [
            "DOTNET_ROOT": v.root,
            "DOTNET_CLI_TELEMETRY_OPTOUT": "1",
            "DOTNET_NOLOGO": "1",
            "DOTNET_SKIP_FIRST_TIME_EXPERIENCE": "1",
        ].merging(extra) { $1 })
    }

    /// The project file to run: one in the root, else a web project one level down (solution layouts).
    static func dotnetProject(in dir: URL) -> URL? {
        let fm = FileManager.default
        func projects(_ d: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
                .filter { ["csproj", "fsproj"].contains($0.pathExtension) }
        }
        if let root = projects(dir).first { return root }
        let subdirs = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        let candidates = subdirs.flatMap(projects)
        return candidates.first { (try? String(contentsOf: $0, encoding: .utf8))?.contains("Microsoft.NET.Sdk.Web") == true }
            ?? candidates.first
    }

    func startDotnet(_ site: Site, process p: ManagedProcess) {
        guard let v = dotnet(for: site), let project = Self.dotnetProject(in: site.path), let port = site.config.port else { return }
        let env = dotnetEnv(v, [
            "ASPNETCORE_URLS": "http://127.0.0.1:\(port)",
            "ASPNETCORE_ENVIRONMENT": "Development",
            "DOTNET_WATCH_RESTART_ON_RUDE_EDIT": "true",
            "DOTNET_WATCH_SUPPRESS_LAUNCH_BROWSER": "1",
        ])
        try? p.start(v.bin, ["watch", "run", "--project", project.path, "--no-launch-profile"],
                     cwd: project.deletingLastPathComponent(), env: env)
    }

    // MARK: New project

    func createDotnetProject(_ o: NewProjectOptions, name: String, dir: URL, job: Job) async -> Job {
        guard let v = dotnetVersion(o.dotnet) ?? defaultDotnet else {
            job.note("\nKurulu .NET SDK bulunamadı. Önce .NET sekmesinden bir sürüm kurun.\n")
            job.finish(false)
            return job
        }
        let parent = dir.deletingLastPathComponent()
        let env = dotnetEnv(v)
        job.note(".NET \(v.major) ile oluşturuluyor → \(dir.path)\n")
        guard let template = o.template.dotnetTemplate,
              await step(job, v.bin, ["new", template, "-o", name, "--no-https"], cwd: parent, env: env) else {
            job.note("\nProje oluşturulamadı.\n")
            job.finish(false)
            return job
        }
        if o.gitInit {
            await step(job, v.bin, ["new", "gitignore"], cwd: dir, env: env)
            await step(job, "/usr/bin/git", ["init", "-q"], cwd: dir)
            await step(job, "/usr/bin/git", ["add", "-A"], cwd: dir)
            await step(job, "/usr/bin/git", ["commit", "-q", "-m", "Initial commit"], cwd: dir)
        }
        if o.docker {
            let files = writeDockerFiles(adhocSite(dir))
            job.note("\nDocker dosyaları oluşturuldu: \(files.joined(separator: ", "))\n")
        }

        if !config.parkedPaths.contains(parent.path) { config.linkedPaths.append(dir.path) }
        var c = SiteConfig(secure: o.secure, dotnet: o.dotnet)
        c.port = config.sites[name]?.port
        config.sites[name] = c
        scanSites()
        await reloadWebServer()
        if !webRunning && caddyInstalled { await startWebServer() }
        selectedSiteID = name
        if let site = site(name) {
            startDev(site)
            job.note("\nDev sunucusu başlatıldı → \(url(for: site).absoluteString)\n")
        }
        job.finish(true)
        if o.openEditor { openInEditor(dir) }
        return job
    }

    // MARK: Docker

    func dotnetDockerPlan(_ site: Site) -> DockerPlan {
        let project = Self.dotnetProject(in: site.path)
        let csproj = project.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        // net10.0 -> 10.0
        let tfm = csproj.range(of: #"<TargetFramework>net([0-9]+\.[0-9]+)</TargetFramework>"#, options: .regularExpression)
            .map { String(csproj[$0]).replacingOccurrences(of: #"[^0-9.]"#, with: "", options: .regularExpression) }
            ?? "\(dotnet(for: site)?.major ?? "10").0"
        let assembly = csproj.range(of: #"<AssemblyName>[^<]+</AssemblyName>"#, options: .regularExpression)
            .map { String(csproj[$0]).replacingOccurrences(of: #"</?AssemblyName>"#, with: "", options: .regularExpression) }
            ?? project?.deletingPathExtension().lastPathComponent ?? site.name
        let relative = project.map { String($0.path.dropFirst(site.path.path.count + 1)) } ?? "\(site.name).csproj"

        let dockerfile = """
        # syntax=docker/dockerfile:1
        # Generated by Nerd: ASP.NET Core (.NET \(tfm))

        FROM mcr.microsoft.com/dotnet/sdk:\(tfm) AS build
        WORKDIR /src
        COPY . .
        RUN dotnet publish "\(relative)" -c Release -o /app/publish /p:UseAppHost=false

        FROM mcr.microsoft.com/dotnet/aspnet:\(tfm)
        WORKDIR /app
        COPY --from=build /app/publish .
        ENV ASPNETCORE_URLS=http://+:8080 \\
            ASPNETCORE_ENVIRONMENT=Production
        USER $APP_UID
        EXPOSE 8080
        ENTRYPOINT ["dotnet", "\(assembly).dll"]

        """
        let ignore = ".git\n.env\n.env.*\n**/bin\n**/obj\n.vs\n.vscode\n.idea\nDockerfile\ndocker-compose.yml\n.dockerignore\n.DS_Store\n"
        return DockerPlan(files: [("Dockerfile", dockerfile), ("docker-compose.yml", appCompose(8080)), (".dockerignore", ignore)],
                          port: 8080, services: ["app"])
    }
}
