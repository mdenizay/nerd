import Foundation
import CryptoKit

/// Composer: Homebrew's or the user's own when present, otherwise Nerd installs
/// the official composer.phar into ~/.nerd/bin (already on Nerd's PATH).
extension AppState {
    static var managedComposer: URL { Paths.bin.appendingPathComponent("composer") }

    /// The composer to run, if any.
    var composerPath: String? {
        Shell.which("composer") ?? (Paths.exists(Self.managedComposer.path) ? Self.managedComposer.path : nil)
    }

    var composerIsManaged: Bool { composerPath == Self.managedComposer.path }

    func composerVersion() async -> String? {
        guard let composer = composerPath, let php = defaultPHP else { return nil }
        let r = await Shell.run(php.bin, [composer, "--version", "--no-ansi"], env: Shell.env(prependPath: [php.binDir]))
        // "Composer version 2.8.12 2025-09-19 13:41:59"
        return r.stdout.split(separator: " ").dropFirst(2).first.map(String.init)
    }

    /// Returns a composer, installing the official phar first when none is found.
    func ensureComposer(_ job: Job) async -> String? {
        if let path = composerPath { return path }
        job.note("\nComposer bulunamadı; getcomposer.org'dan kuruluyor…\n")
        return await installComposer(job) ? Self.managedComposer.path : nil
    }

    @discardableResult
    func installComposer(_ existing: Job? = nil) async -> Bool {
        busy.insert("composer")
        defer { busy.remove("composer") }
        let job = existing ?? newJob("Composer kurulumu")
        do {
            let base = "https://getcomposer.org/download/latest-stable/composer.phar"
            let (phar, _) = try await URLSession.shared.data(from: URL(string: base)!)
            let (sumData, _) = try await URLSession.shared.data(from: URL(string: base + ".sha256sum")!)
            let expected = String(decoding: sumData, as: UTF8.self).split(separator: " ").first.map(String.init) ?? ""
            let actual = SHA256.hash(data: phar).map { String(format: "%02x", $0) }.joined()
            guard !expected.isEmpty, actual == expected else {
                job.note("Composer indirmesi doğrulanamadı (SHA-256 uyuşmuyor).\n")
                if existing == nil { job.finish(false) }
                return false
            }
            Paths.ensure()
            try phar.write(to: Self.managedComposer, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: Self.managedComposer.path)
            job.note("Composer kuruldu: ~/.nerd/bin/composer (SHA-256 doğrulandı).\n")
            if existing == nil { job.finish(true) }
            return true
        } catch {
            job.note("Composer indirilemedi: \(error.localizedDescription)\n")
            if existing == nil { job.finish(false) }
            return false
        }
    }

    /// Updates Nerd's composer with self-update, or Homebrew's with brew.
    func updateComposer() async {
        guard let composer = composerPath else { await installComposer(); return }
        busy.insert("composer")
        defer { busy.remove("composer") }
        if composerIsManaged, let php = defaultPHP {
            await runJob("Composer güncelleniyor", php.bin, [composer, "self-update", "--no-interaction"],
                         env: Shell.env(prependPath: [php.binDir]))
        } else if composer.hasPrefix(Paths.brew) {
            await brew("Composer güncelleniyor", ["upgrade", "composer"])
        } else if let php = defaultPHP {
            await runJob("Composer güncelleniyor", php.bin, [composer, "self-update", "--no-interaction"],
                         env: Shell.env(prependPath: [php.binDir]))
        }
    }
}
