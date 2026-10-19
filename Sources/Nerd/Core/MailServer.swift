import Foundation

/// Minimal SMTP server that accepts every message and hands the raw data to `onMessage`.
/// Point apps at 127.0.0.1:<port> (no TLS, any credentials).
final class SMTPServer: @unchecked Sendable {
    private let lock = NSLock()
    private var fd: Int32 = -1
    var onMessage: (@Sendable (Data) -> Void)?

    var isRunning: Bool { lock.withLock { fd >= 0 } }

    @discardableResult
    func start(port: UInt16) -> Bool {
        stop()
        let s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard s >= 0 else { return false }
        var yes: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard r == 0, listen(s, 16) == 0 else { close(s); return false }
        lock.withLock { fd = s }
        Thread.detachNewThread { [weak self] in self?.acceptLoop(s) }
        return true
    }

    func stop() {
        let s: Int32 = lock.withLock { let v = fd; fd = -1; return v }
        if s >= 0 { shutdown(s, SHUT_RDWR); close(s) }
    }

    private func acceptLoop(_ s: Int32) {
        while true {
            let client = accept(s, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                break
            }
            var yes: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
            Thread.detachNewThread { [weak self] in self?.session(client) }
        }
    }

    private func send(_ c: Int32, _ line: String) {
        let data = Array((line + "\r\n").utf8)
        _ = data.withUnsafeBytes { write(c, $0.baseAddress, data.count) }
    }

    private func session(_ c: Int32) {
        defer { close(c) }
        var timeout = timeval(tv_sec: 60, tv_usec: 0)
        setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        send(c, "220 nerd ESMTP ready")

        var buffer = Data()
        var message = Data()
        var inData = false
        var authLoginSteps = 0
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        let crlf = Data([13, 10])

        while true {
            let n = read(c, &chunk, chunk.count)
            if n <= 0 { return }
            buffer.append(contentsOf: chunk[0..<n])

            while let range = buffer.range(of: crlf) {
                let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)

                if inData {
                    if lineData == Data([46]) { // "."
                        inData = false
                        onMessage?(message)
                        message = Data()
                        send(c, "250 OK: queued")
                    } else {
                        // dot-unstuffing
                        message.append(lineData.first == 46 ? lineData.dropFirst() : lineData)
                        message.append(crlf)
                    }
                    continue
                }

                let line = String(decoding: lineData, as: UTF8.self)
                if authLoginSteps > 0 {
                    authLoginSteps -= 1
                    send(c, authLoginSteps == 1 ? "334 UGFzc3dvcmQ6" : "235 2.7.0 Authentication successful")
                    continue
                }
                let cmd = line.prefix(while: { $0 != " " }).uppercased()
                switch cmd {
                case "EHLO":
                    send(c, "250-nerd")
                    send(c, "250-SIZE 52428800")
                    send(c, "250-8BITMIME")
                    send(c, "250 AUTH PLAIN LOGIN")
                case "HELO": send(c, "250 nerd")
                case "AUTH":
                    if line.uppercased().contains("LOGIN") {
                        let parts = line.split(separator: " ")
                        // "AUTH LOGIN <user>" skips the username prompt
                        authLoginSteps = parts.count > 2 ? 1 : 2
                        send(c, parts.count > 2 ? "334 UGFzc3dvcmQ6" : "334 VXNlcm5hbWU6")
                    } else if line.split(separator: " ").count > 2 {
                        send(c, "235 2.7.0 Authentication successful")
                    } else {
                        authLoginSteps = 1
                        send(c, "334 ")
                    }
                case "MAIL", "RCPT", "RSET", "NOOP": send(c, "250 OK")
                case "DATA":
                    inData = true
                    message = Data()
                    send(c, "354 End data with <CR><LF>.<CR><LF>")
                case "QUIT":
                    send(c, "221 Bye")
                    return
                default: send(c, "502 Command not implemented")
                }
            }
        }
    }
}
