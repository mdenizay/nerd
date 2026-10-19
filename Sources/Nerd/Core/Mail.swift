import Foundation

struct MailMessage: Identifiable, Hashable {
    var id: String { url.lastPathComponent }
    let url: URL
    let date: Date
    let from: String
    let to: String
    let subject: String
    let html: String?
    let text: String?
    let attachments: [String]
    let size: Int
}

// MARK: - MIME parsing

enum MIME {
    struct Part {
        var headers: [String: String] = [:]   // lowercased keys, unfolded values
        var body: String = ""                 // raw bytes as Latin-1 (1:1 byte mapping)
    }

    static func parse(_ data: Data, url: URL) -> MailMessage {
        let raw = String(data: data, encoding: .isoLatin1) ?? ""
        let root = split(raw)
        var html: String?, text: String?
        var attachments: [String] = []
        walk(root, html: &html, text: &text, attachments: &attachments)

        let dateHeader = root.headers["date"] ?? ""
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        var date: Date?
        for f in ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss zzz"] {
            formatter.dateFormat = f
            let cleaned = dateHeader.replacingOccurrences(of: #"\s*\(.*\)$"#, with: "", options: .regularExpression)
            if let d = formatter.date(from: cleaned) { date = d; break }
        }
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()

        return MailMessage(
            url: url,
            date: date ?? mtime,
            from: decodeWords(root.headers["from"] ?? ""),
            to: decodeWords(root.headers["to"] ?? ""),
            subject: decodeWords(root.headers["subject"] ?? "(konu yok)"),
            html: html,
            text: text,
            attachments: attachments,
            size: data.count)
    }

    static func split(_ raw: String) -> Part {
        var part = Part()
        let separator = raw.range(of: "\r\n\r\n") ?? raw.range(of: "\n\n")
        let headerBlock = separator.map { String(raw[..<$0.lowerBound]) } ?? raw
        part.body = separator.map { String(raw[$0.upperBound...]) } ?? ""

        var current: (String, String)?
        for line in headerBlock.components(separatedBy: "\n").map({ $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }) {
            if line.first == " " || line.first == "\t" {
                current?.1 += " " + line.trimmingCharacters(in: .whitespaces)
                continue
            }
            if let c = current, part.headers[c.0] == nil { part.headers[c.0] = c.1 }
            guard let colon = line.firstIndex(of: ":") else { current = nil; continue }
            current = (line[..<colon].lowercased(), line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
        }
        if let c = current, part.headers[c.0] == nil { part.headers[c.0] = c.1 }
        return part
    }

    static func param(_ name: String, in header: String?) -> String? {
        guard let header else { return nil }
        let pattern = "\(name)\\*?=\\s*(\"([^\"]*)\"|([^;\\s]+))"
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = re.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)) else { return nil }
        for i in [2, 3] {
            guard let r = Range(m.range(at: i), in: header) else { continue }
            let value = String(header[r])
            // RFC 2231: charset'lang'percent-encoded
            if let quote = value.range(of: "''") {
                return String(value[quote.upperBound...]).removingPercentEncoding ?? value
            }
            return value
        }
        return nil
    }

    private static func walk(_ part: Part, html: inout String?, text: inout String?, attachments: inout [String]) {
        let type = (part.headers["content-type"] ?? "text/plain").lowercased()
        if type.hasPrefix("multipart/"), let boundary = param("boundary", in: part.headers["content-type"]) {
            let delimiter = "--" + boundary
            var chunks = part.body.components(separatedBy: delimiter)
            guard chunks.count > 1 else { return }
            chunks.removeFirst() // preamble
            for chunk in chunks {
                if chunk.hasPrefix("--") { break } // closing delimiter
                // "\r\n" is a single Character in Swift, so drop exactly one line break
                let trimmed = chunk.first == "\r\n" || chunk.first == "\n" ? String(chunk.dropFirst()) : chunk
                walk(split(trimmed), html: &html, text: &text, attachments: &attachments)
            }
            return
        }
        let disposition = part.headers["content-disposition"] ?? ""
        if let name = param("filename", in: disposition) ?? (disposition.lowercased().hasPrefix("attachment") ? param("name", in: part.headers["content-type"]) : nil) {
            attachments.append(decodeWords(name))
            return
        }
        if type.hasPrefix("text/html"), html == nil {
            html = decodeBody(part)
        } else if type.hasPrefix("text/plain"), text == nil {
            text = decodeBody(part)
        } else if !type.hasPrefix("text/"), let name = param("name", in: part.headers["content-type"]) {
            attachments.append(decodeWords(name))
        }
    }

    static func decodeBody(_ part: Part) -> String {
        let encoding = (part.headers["content-transfer-encoding"] ?? "").lowercased()
        var bytes = part.body.data(using: .isoLatin1) ?? Data()
        if encoding.contains("base64") {
            let compact = part.body.components(separatedBy: .whitespacesAndNewlines).joined()
            bytes = Data(base64Encoded: compact, options: .ignoreUnknownCharacters) ?? bytes
        } else if encoding.contains("quoted-printable") {
            bytes = quotedPrintable(part.body)
        }
        return string(bytes, charset: param("charset", in: part.headers["content-type"]))
    }

    static func quotedPrintable(_ s: String, underscoreIsSpace: Bool = false) -> Data {
        var out = Data()
        let chars = Array(s.utf8)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == UInt8(ascii: "=") {
                if i + 1 < chars.count, chars[i + 1] == 13 || chars[i + 1] == 10 { // soft line break
                    i += chars[i + 1] == 13 && i + 2 < chars.count && chars[i + 2] == 10 ? 3 : 2
                    continue
                }
                if i + 2 < chars.count, let v = UInt8(String(bytes: chars[(i + 1)...(i + 2)], encoding: .ascii) ?? "", radix: 16) {
                    out.append(v); i += 3; continue
                }
            }
            out.append(underscoreIsSpace && c == UInt8(ascii: "_") ? 32 : c)
            i += 1
        }
        // `s` held Latin-1 code points as UTF-8; map them back to single bytes
        return String(decoding: out, as: UTF8.self).data(using: .isoLatin1) ?? out
    }

    static func string(_ data: Data, charset: String?) -> String {
        switch (charset ?? "utf-8").lowercased() {
        case "iso-8859-1", "latin1": return String(data: data, encoding: .isoLatin1) ?? ""
        case "windows-1252", "cp1252": return String(data: data, encoding: .windowsCP1252) ?? ""
        case "iso-8859-9", "windows-1254":
            let enc = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.isoLatin5.rawValue))
            return String(data: data, encoding: String.Encoding(rawValue: enc)) ?? String(decoding: data, as: UTF8.self)
        default: return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        }
    }

    /// RFC 2047 encoded words: =?charset?B|Q?text?=
    static func decodeWords(_ s: String) -> String {
        guard s.contains("=?"), let re = try? NSRegularExpression(pattern: #"=\?([^?]+)\?([BbQq])\?([^?]*)\?=(\s+(?==\?))?"#) else {
            return utf8Repair(s)
        }
        var result = ""
        var last = s.startIndex
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let full = Range(m.range, in: s), let cs = Range(m.range(at: 1), in: s),
                  let enc = Range(m.range(at: 2), in: s), let txt = Range(m.range(at: 3), in: s) else { continue }
            result += s[last..<full.lowerBound]
            let payload = String(s[txt])
            let data = s[enc].uppercased() == "B"
                ? (Data(base64Encoded: payload, options: .ignoreUnknownCharacters) ?? Data())
                : quotedPrintable(payload, underscoreIsSpace: true)
            result += string(data, charset: String(s[cs]))
            last = full.upperBound
        }
        result += s[last...]
        return result
    }

    /// Headers are read as Latin-1; re-decode raw UTF-8 header bytes.
    private static func utf8Repair(_ s: String) -> String {
        guard let data = s.data(using: .isoLatin1), let fixed = String(data: data, encoding: .utf8) else { return s }
        return fixed
    }
}

// MARK: - Mailbox

extension AppState {
    static let mailDir = Paths.root.appendingPathComponent("mail")

    var unreadMailCount: Int { mails.filter { !readMail.contains($0.id) }.count }

    func startMailServer() {
        try? FileManager.default.createDirectory(at: Self.mailDir, withIntermediateDirectories: true)
        let dir = Self.mailDir
        smtp.onMessage = { data in
            let name = "\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(8)).eml"
            try? data.write(to: dir.appendingPathComponent(name))
            DispatchQueue.main.async { MainActor.assumeIsolated { AppState.shared.loadMail() } }
        }
        mailRunning = smtp.start(port: UInt16(config.mailPort))
        readMail = Set(UserDefaults.standard.stringArray(forKey: "nerd.mail.read") ?? [])
        loadMail()
    }

    func loadMail() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Self.mailDir, includingPropertiesForKeys: [.contentModificationDateKey]))?
            .filter { $0.pathExtension == "eml" } ?? []
        let known = Dictionary(uniqueKeysWithValues: mails.map { ($0.id, $0) })
        mails = urls.compactMap { url in
            known[url.lastPathComponent] ?? (try? Data(contentsOf: url)).map { MIME.parse($0, url: url) }
        }
        .sorted { $0.id > $1.id }
    }

    func markRead(_ m: MailMessage) {
        guard !readMail.contains(m.id) else { return }
        readMail.insert(m.id)
        UserDefaults.standard.set(Array(readMail), forKey: "nerd.mail.read")
    }

    func deleteMail(_ m: MailMessage) {
        try? FileManager.default.removeItem(at: m.url)
        loadMail()
    }

    func deleteAllMail() {
        for m in mails { try? FileManager.default.removeItem(at: m.url) }
        readMail = []
        UserDefaults.standard.removeObject(forKey: "nerd.mail.read")
        loadMail()
    }

    var mailEnv: [String: String] {
        ["MAIL_MAILER": "smtp", "MAIL_HOST": "127.0.0.1", "MAIL_PORT": String(config.mailPort),
         "MAIL_USERNAME": "null", "MAIL_PASSWORD": "null"]
    }

    /// Points a Laravel site's mailer at Nerd's SMTP catcher.
    func routeMail(to site: Site) {
        Self.writeEnv(site.path.appendingPathComponent(".env"), mailEnv)
    }

    func mailRouted(_ site: Site) -> Bool {
        let env = Self.parseEnv(site.path.appendingPathComponent(".env"))
        return env["MAIL_MAILER"] == "smtp" && env["MAIL_PORT"] == String(config.mailPort)
            && ["127.0.0.1", "localhost"].contains(env["MAIL_HOST"] ?? "")
    }
}
