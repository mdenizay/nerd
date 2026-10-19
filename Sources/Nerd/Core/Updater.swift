import AppKit
import Foundation
import Observation
import Security

/// Keeps the app current from its GitHub releases: downloads the newest build
/// in the background, checks that it is signed by the same developer as the
/// running app, and swaps it in on restart.
@MainActor @Observable
final class Updater {
    static let shared = Updater()

    enum State: Equatable {
        case idle, checking, upToDate
        case downloading(String)
        case ready(String)
        case failed(String)
    }

    private(set) var state = State.idle
    private(set) var lastCheck: Date?
    var automatic = UserDefaults.standard.object(forKey: "autoUpdate") as? Bool ?? true {
        didSet { UserDefaults.standard.set(automatic, forKey: "autoUpdate") }
    }

    @ObservationIgnored private static let latestRelease = URL(string: "https://api.github.com/repos/mdenizay/nerd/releases/latest")!
    @ObservationIgnored private var staged: URL?
    @ObservationIgnored private var timer: Timer?

    /// The team that signed this build; nil for local (ad hoc) builds, which
    /// never update themselves because nothing could vouch for the download.
    @ObservationIgnored private let teamID: String? = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }()

    var available: Bool { teamID != nil }

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// NERD_UPDATE_FROM pretends to be an older version, to exercise an update.
    private var currentVersion: String {
        ProcessInfo.processInfo.environment["NERD_UPDATE_FROM"] ?? Self.version
    }

    var readyVersion: String? {
        if case .ready(let v) = state { return v }
        return nil
    }

    func start() {
        guard available else { return }
        if automatic { check() }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in
            MainActor.assumeIsolated {
                if Updater.shared.automatic { Updater.shared.check() }
            }
        }
    }

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let assets: [Asset]
    }

    func check() {
        guard available else { return }
        switch state {
        case .checking, .downloading, .ready: return
        default: break
        }
        state = .checking
        Task {
            defer { lastCheck = Date() }
            do {
                let (data, _) = try await URLSession.shared.data(from: Self.latestRelease)
                let release = try JSONDecoder().decode(Release.self, from: data)
                let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
                guard Self.isNewer(version, than: currentVersion),
                      let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") }) else {
                    state = .upToDate
                    return
                }
                state = .downloading(version)
                staged = try await fetch(asset.browser_download_url)
                state = .ready(version)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedDescending
    }

    /// Downloads and unpacks a release and returns the verified app inside it.
    private func fetch(_ url: URL) async throws -> URL {
        let (zip, _) = try await URLSession.shared.download(from: url)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nerd-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let result = await Shell.run("/usr/bin/ditto", ["-x", "-k", zip.path, dir.path])
        try? FileManager.default.removeItem(at: zip)
        guard result.ok,
              let name = try FileManager.default.contentsOfDirectory(atPath: dir.path).first(where: { $0.hasSuffix(".app") }) else {
            throw DBError(message: String(localized: "Güncelleme açılamadı."))
        }
        let app = dir.appendingPathComponent(name)
        guard verify(app) else { throw DBError(message: String(localized: "Güncelleme bu uygulamanın geliştiricisi tarafından imzalanmamış.")) }
        return app
    }

    /// True if the bundle is intact and signed with our Developer ID.
    private func verify(_ app: URL) -> Bool {
        guard let teamID, let bundleID = Bundle.main.bundleIdentifier else { return false }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return false }
        let rule = "anchor apple generic and identifier \"\(bundleID)\" and certificate leaf[subject.OU] = \"\(teamID)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess, let requirement else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }

    /// Replaces the running app with the downloaded one and starts it again.
    /// The swap happens in a small helper once this process has exited, so the
    /// app never runs from a bundle that was moved away.
    func installAndRelaunch() {
        guard let staged else { return }
        let current = Bundle.main.bundleURL
        let folder = current.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: folder.path) else {
            state = .failed(String(localized: "Uygulamanın klasörüne yazılamıyor."))
            return
        }
        let old = folder.appendingPathComponent(".\(current.lastPathComponent).old-\(getpid())")
        let script = """
            while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
            if mv "$2" "$4"; then
              if mv "$3" "$2"; then rm -rf "$4"; else mv "$4" "$2"; fi
            fi
            /usr/bin/open "$2"
            """
        Self.relaunch(script: script, args: ["\(getpid())", current.path, staged.path, old.path])
    }

    /// Starts the app again (e.g. after a language change).
    static func restart() {
        relaunch(script: "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done\n/usr/bin/open \"$2\"",
                 args: ["\(getpid())", Bundle.main.bundleURL.path])
    }

    private static func relaunch(script: String, args: [String]) {
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", script, "sh"] + args
        guard (try? helper.run()) != nil else { return }
        for window in NSApp.windows {
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
        }
        NSApp.terminate(nil)
        // Should quitting still be refused, leave anyway; the helper is waiting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { exit(0) }
    }
}
