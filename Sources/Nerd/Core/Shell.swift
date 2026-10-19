import Foundation
import Observation

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let root = home.appendingPathComponent(".nerd")
    static let bin = root.appendingPathComponent("bin")
    static let run = root.appendingPathComponent("run")
    static let logs = root.appendingPathComponent("logs")
    static let fpm = root.appendingPathComponent("fpm")
    static let node = root.appendingPathComponent("node")
    static let caddyfile = root.appendingPathComponent("Caddyfile")
    static let config = root.appendingPathComponent("config.json")
    static let caddyRootCert = home.appendingPathComponent("Library/Application Support/Caddy/pki/authorities/local/root.crt")

    static let brew: String = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") ? "/opt/homebrew" : "/usr/local"
    static var brewBin: String { brew + "/bin/brew" }

    static func ensure() {
        for dir in [root, bin, run, logs, fpm, node] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    static func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }
}

struct ShellResult {
    var status: Int32
    var stdout: String
    var stderr: String
    var ok: Bool { status == 0 }
}

private final class DataBox: @unchecked Sendable { var data = Data() }

enum Shell {
    static func env(prependPath: [String] = [], _ extra: [String: String] = [:]) -> [String: String] {
        var e = ProcessInfo.processInfo.environment
        let home = Paths.home.path
        let path = prependPath + [
            Paths.bin.path,
            "\(Paths.brew)/bin", "\(Paths.brew)/sbin",
            "\(home)/.composer/vendor/bin", "\(home)/.config/composer/vendor/bin",
            "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
        ]
        e["PATH"] = path.joined(separator: ":")
        e["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        e["HOMEBREW_NO_ENV_HINTS"] = "1"
        e["NO_COLOR"] = "1"
        e["TERM"] = "dumb"
        if e["LANG"] == nil { e["LANG"] = "en_US.UTF-8" }
        e.merge(extra) { $1 }
        return e
    }

    static func which(_ name: String) -> String? {
        let dirs = (env()["PATH"] ?? "").split(separator: ":")
        for dir in dirs {
            let p = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    static func run(_ exe: String, _ args: [String] = [], cwd: URL? = nil, env: [String: String]? = nil, input: Data? = nil) async -> ShellResult {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: exe)
                p.arguments = args
                if let cwd { p.currentDirectoryURL = cwd }
                p.environment = env ?? Shell.env()
                let out = Pipe(), err = Pipe(), inp = Pipe()
                p.standardOutput = out
                p.standardError = err
                p.standardInput = input == nil ? FileHandle.nullDevice : inp
                do { try p.run() } catch {
                    cont.resume(returning: ShellResult(status: -1, stdout: "", stderr: error.localizedDescription))
                    return
                }
                if let input {
                    inp.fileHandleForWriting.write(input)
                    try? inp.fileHandleForWriting.close()
                }
                let errBox = DataBox()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    errBox.data = err.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                p.waitUntilExit()
                cont.resume(returning: ShellResult(
                    status: p.terminationStatus,
                    stdout: String(decoding: outData, as: UTF8.self),
                    stderr: String(decoding: errBox.data, as: UTF8.self)))
            }
        }
    }

    static func sh(_ command: String, cwd: URL? = nil, env: [String: String]? = nil) async -> ShellResult {
        await run("/bin/zsh", ["-c", command], cwd: cwd, env: env)
    }

    /// Runs a command and streams merged stdout/stderr chunks.
    static func stream(_ exe: String, _ args: [String], cwd: URL? = nil, env: [String: String]? = nil,
                       onOutput: @escaping @Sendable (String) -> Void) async -> Int32 {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = args
            if let cwd { p.currentDirectoryURL = cwd }
            p.environment = env ?? Shell.env()
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            p.standardInput = FileHandle.nullDevice
            pipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty { h.readabilityHandler = nil; return }
                onOutput(String(decoding: d, as: UTF8.self))
            }
            p.terminationHandler = { proc in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    cont.resume(returning: proc.terminationStatus)
                }
            }
            do { try p.run() } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                onOutput("Hata: \(error.localizedDescription)\n")
                cont.resume(returning: -1)
            }
        }
    }

    /// Runs a shell script with administrator privileges (system password dialog).
    static func runAsAdmin(_ script: String) async -> ShellResult {
        let escaped = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return await run("/usr/bin/osascript", ["-e", "do shell script \"\(escaped)\" with administrator privileges"])
    }

    static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func stripANSI(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression)
    }
}

// MARK: - Process tree helpers

func childPIDs(of pid: Int32) -> [Int32] {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    p.arguments = ["-P", String(pid)]
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return [] }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { Int32($0) }
}

func killTree(_ pid: Int32, signal sig: Int32 = SIGTERM) {
    for child in childPIDs(of: pid) {
        killTree(child, signal: sig)
        kill(child, sig)
    }
}

// MARK: - Long running child processes

@MainActor @Observable
final class ManagedProcess {
    let name: String
    @ObservationIgnored private var process: Process?
    @ObservationIgnored var onExit: ((Int32) -> Void)?
    private(set) var running = false
    private(set) var lastExitStatus: Int32?

    var logURL: URL { Paths.logs.appendingPathComponent("\(name).log") }

    init(name: String) { self.name = name }

    func start(_ exe: String, _ args: [String], cwd: URL? = nil, env: [String: String]? = nil) throws {
        stop()
        let fm = FileManager.default
        if !fm.fileExists(atPath: logURL.path) { fm.createFile(atPath: logURL.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: logURL)
        handle.seekToEndOfFile()
        handle.write("\n--- \(Date()) \(exe) \(args.joined(separator: " "))\n".data(using: .utf8)!)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        p.environment = env ?? Shell.env()
        p.standardOutput = handle
        p.standardError = handle
        p.standardInput = FileHandle.nullDevice
        p.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.didExit(proc, status) }
            }
        }
        try p.run()
        process = p
        running = true
        lastExitStatus = nil
    }

    private func didExit(_ p: Process, _ status: Int32) {
        guard p === process else { return }
        process = nil
        running = false
        lastExitStatus = status
        onExit?(status)
    }

    func stop() {
        guard let p = process else { return }
        process = nil
        running = false
        guard p.isRunning else { return }
        killTree(p.processIdentifier)
        p.terminate()
        let deadline = Date().addingTimeInterval(3)
        while p.isRunning && Date() < deadline { usleep(50_000) }
        if p.isRunning { kill(p.processIdentifier, SIGKILL) }
    }

    func tail(_ lines: Int = 40) -> String {
        guard let data = try? Data(contentsOf: logURL) else { return "" }
        let text = String(decoding: data.suffix(64_000), as: UTF8.self)
        return text.split(separator: "\n", omittingEmptySubsequences: false).suffix(lines).joined(separator: "\n")
    }
}

// MARK: - Jobs (visible task log)

@MainActor @Observable
final class Job: Identifiable {
    enum State { case running, success, failed }
    let id = UUID()
    let title: String
    let started = Date()
    var output = ""
    var state: State = .running

    init(title: String) { self.title = title }

    func append(_ s: String) {
        output += Shell.stripANSI(s).replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if output.count > 300_000 { output = String(output.suffix(200_000)) }
    }

    func finish(_ ok: Bool) {
        state = ok ? .success : .failed
        append(ok ? "\n✓ Tamamlandı\n" : "\n✗ Başarısız\n")
    }
}
