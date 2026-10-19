import Foundation

/// An exception (or any error entry) read back from storage/logs/laravel.log.
struct LoggedException: Identifiable, Hashable {
    struct Frame: Hashable {
        let index: Int
        let file: String?
        let line: Int?
        let call: String

        var isVendor: Bool { file?.contains("/vendor/") ?? true }
    }

    var id: String { "\(site)|\(offset)" }
    let site: String
    let offset: Int           // position in the log, unique per site
    let date: Date?
    let environment: String
    let level: String         // ERROR, CRITICAL, …
    let message: String
    let exceptionClass: String?
    let file: String?
    let line: Int?
    let frames: [Frame]
    let previous: [String]    // "[previous exception]" headers, if any

    var shortClass: String? { exceptionClass?.components(separatedBy: "\\").last }

    /// The first frame in the app's own code, else where it was thrown.
    var appSource: (file: String, line: Int?)? {
        if let file, !file.contains("/vendor/") { return (file, line) }
        if let f = frames.first(where: { !$0.isVendor && $0.file != nil }), let file = f.file { return (file, f.line) }
        return file.map { ($0, line) }
    }
}

enum LaravelLog {
    private static let entryStart = try! NSRegularExpression(
        pattern: #"^\[(\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[+-]\d{2}:?\d{2})?)\] ([\w-]+)\.([A-Z]+): "#,
        options: .anchorsMatchLines)
    private static let object = try! NSRegularExpression(
        pattern: #"\[object\] \(([^\s(]+)\(code: [^)]*\): (.*?) at (\S+?):(\d+)\)\n"#,
        options: .dotMatchesLineSeparators)
    private static let frame = try! NSRegularExpression(pattern: #"^#(\d+) (?:(.+?)\((\d+)\)|\[internal function\]|\{main\}):? ?(.*)$"#)

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    /// Error-level entries (ERROR and above) of a log, newest first. Log times are in
    /// the app's timezone; `shift` moves them to the Mac's.
    static func parse(_ text: String, site: String, baseOffset: Int = 0, shift: TimeInterval = 0) -> [LoggedException] {
        let ns = text as NSString
        let starts = entryStart.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var result: [LoggedException] = []
        for (i, m) in starts.enumerated() {
            let level = ns.substring(with: m.range(at: 3))
            guard ["ERROR", "CRITICAL", "ALERT", "EMERGENCY"].contains(level) else { continue }
            let end = i + 1 < starts.count ? starts[i + 1].range.location : ns.length
            let body = ns.substring(with: NSRange(location: m.range.upperBound, length: end - m.range.upperBound))
            let stamp = String(ns.substring(with: m.range(at: 1)).prefix(19)).replacingOccurrences(of: "T", with: " ")
            result.append(entry(body, site: site, offset: baseOffset + m.range.location,
                                date: dateFormatter.date(from: stamp)?.addingTimeInterval(shift),
                                environment: ns.substring(with: m.range(at: 2)), level: level))
        }
        return result.reversed()
    }

    private static func entry(_ body: String, site: String, offset: Int, date: Date?, environment: String, level: String) -> LoggedException {
        let ns = body as NSString
        // The message runs up to the JSON context: ` {"exception":"[object] …` or ` {"userId":…`
        let contextStart = ns.range(of: #" \{"[^"]+":"#, options: .regularExpression).location
        var message = contextStart != NSNotFound ? ns.substring(to: contextStart) : body
        message = message.trimmingCharacters(in: .whitespacesAndNewlines)

        var cls: String?, file: String?, line: Int?
        var previous: [String] = []
        let objects = object.matches(in: body, range: NSRange(location: 0, length: ns.length))
        if let o = objects.first {
            cls = unescape(ns.substring(with: o.range(at: 1)))
            file = ns.substring(with: o.range(at: 3))
            line = Int(ns.substring(with: o.range(at: 4)))
        }
        for o in objects.dropFirst() {
            previous.append(unescape("\(ns.substring(with: o.range(at: 1))): \(ns.substring(with: o.range(at: 2)))"))
        }

        // Frames of the outermost exception: from "[stacktrace]" to the first blank or "[previous exception]"
        var frames: [LoggedException.Frame] = []
        if let trace = body.range(of: "[stacktrace]\n") {
            for raw in body[trace.upperBound...].split(separator: "\n", omittingEmptySubsequences: false) {
                let l = String(raw)
                guard l.hasPrefix("#") else { break }
                let lns = l as NSString
                guard let m = frame.firstMatch(in: l, range: NSRange(location: 0, length: lns.length)) else { continue }
                let f = m.range(at: 2).location != NSNotFound ? lns.substring(with: m.range(at: 2)) : nil
                let ln = m.range(at: 3).location != NSNotFound ? Int(lns.substring(with: m.range(at: 3))) : nil
                var call = m.range(at: 4).location != NSNotFound ? lns.substring(with: m.range(at: 4)) : ""
                if call.isEmpty, l.contains("{main}") { call = "{main}" }
                frames.append(.init(index: Int(lns.substring(with: m.range(at: 1))) ?? frames.count, file: f, line: ln, call: unescape(call)))
            }
        }

        return LoggedException(site: site, offset: offset, date: date, environment: environment, level: level,
                               message: message.isEmpty ? (cls ?? level) : message,
                               exceptionClass: cls, file: file, line: line, frames: frames, previous: previous)
    }

    /// The trace sits inside the JSON context, so its backslashes and quotes are escaped.
    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\\\", with: "\\").replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\/", with: "/")
    }

    /// Reads the tail of a log (large logs are only read from their last few MB).
    static func read(_ url: URL, site: String, limit: UInt64 = 4_000_000) -> [LoggedException] {
        guard let h = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        let start = size > limit ? size - limit : 0
        try? h.seek(toOffset: start)
        let data = (try? h.readToEnd()) ?? Data()
        let text = String(decoding: data, as: UTF8.self)
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return parse(text, site: site, baseOffset: Int(start), shift: timezoneShift(text, written: mtime))
    }

    /// Laravel logs in the app's timezone (UTC by default). The last entry was written
    /// when the file was last modified, so their difference, rounded to a quarter
    /// hour, is the offset to local time.
    static func timezoneShift(_ text: String, written: Date?) -> TimeInterval {
        let ns = text as NSString
        guard let written, let last = entryStart.matches(in: text, range: NSRange(location: 0, length: ns.length)).last,
              let logged = dateFormatter.date(from: String(ns.substring(with: last.range(at: 1)).prefix(19)).replacingOccurrences(of: "T", with: " "))
        else { return 0 }
        let shift = ((written.timeIntervalSince(logged)) / 900).rounded() * 900
        return abs(shift) <= 14 * 3600 ? shift : 0
    }
}
