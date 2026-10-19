import Foundation

/// Tiny UDP DNS responder that answers *.<tld> with loopback addresses.
/// macOS is pointed at it through /etc/resolver/<tld> (nameserver 127.0.0.1 + port).
final class DNSServer: @unchecked Sendable {
    private let lock = NSLock()
    private var fd: Int32 = -1
    private var _tld = "test"

    var tld: String {
        get { lock.withLock { _tld } }
        set { lock.withLock { _tld = newValue.lowercased() } }
    }

    var isRunning: Bool { lock.withLock { fd >= 0 } }

    @discardableResult
    func start(port: UInt16) -> Bool {
        stop()
        let s = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard s >= 0 else { return false }
        var yes: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard r == 0 else { close(s); return false }
        lock.withLock { fd = s }
        Thread.detachNewThread { [weak self] in self?.loop(s) }
        return true
    }

    func stop() {
        let s: Int32 = lock.withLock { let v = fd; fd = -1; return v }
        if s >= 0 {
            shutdown(s, SHUT_RDWR)
            close(s)
        }
    }

    private func loop(_ s: Int32) {
        var buf = [UInt8](repeating: 0, count: 1500)
        while true {
            var from = sockaddr_storage()
            var len = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let n = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(s, &buf, buf.count, 0, $0, &len)
                }
            }
            if n <= 0 {
                if errno == EINTR { continue }
                break
            }
            guard let resp = DNSServer.response(to: Array(buf[0..<n]), tld: tld) else { continue }
            _ = resp.withUnsafeBytes { raw in
                withUnsafePointer(to: &from) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(s, raw.baseAddress, resp.count, 0, $0, len)
                    }
                }
            }
        }
    }

    static func response(to q: [UInt8], tld: String) -> [UInt8]? {
        guard q.count >= 12 else { return nil }
        let qdCount = Int(q[4]) << 8 | Int(q[5])
        guard qdCount >= 1 else { return nil }

        var i = 12
        var labels: [String] = []
        while i < q.count {
            let l = Int(q[i])
            if l == 0 { i += 1; break }
            if l & 0xC0 != 0 { return nil }
            guard i + 1 + l <= q.count else { return nil }
            labels.append(String(decoding: q[(i + 1)..<(i + 1 + l)], as: UTF8.self))
            i += 1 + l
        }
        guard i + 4 <= q.count else { return nil }
        let qtype = Int(q[i]) << 8 | Int(q[i + 1])
        let questionEnd = i + 4

        let name = labels.joined(separator: ".").lowercased()
        let matches = name == tld || name.hasSuffix("." + tld)

        var answers: [[UInt8]] = []
        var flags2: UInt8 = 0x80 // RA
        if matches {
            if qtype == 1 || qtype == 255 { answers.append(record(type: 1, data: [127, 0, 0, 1])) }
            if qtype == 28 { answers.append(record(type: 28, data: [UInt8](repeating: 0, count: 15) + [1])) }
        } else {
            flags2 |= 0x03 // NXDOMAIN
        }

        var r: [UInt8] = [q[0], q[1], 0x84 | (q[2] & 0x01), flags2, 0, 1, 0, UInt8(answers.count), 0, 0, 0, 0]
        r += q[12..<questionEnd]
        for a in answers { r += a }
        return r
    }

    private static func record(type: UInt16, data: [UInt8]) -> [UInt8] {
        [0xC0, 0x0C, UInt8(type >> 8), UInt8(type & 0xFF), 0x00, 0x01, 0, 0, 0, 60, 0, UInt8(data.count)] + data
    }
}
