import Foundation

/// One `dump()` / `dd()` call sent by the PHP prepend file.
struct DumpEntry: Identifiable, Decodable, Hashable {
    let id: String
    let request: String
    let time: Double
    let kind: String          // "dump" or "dd"
    let host: String?
    let method: String?
    let uri: String?
    let command: String?      // CLI: the command line
    let root: String?         // project directory
    let file: String?
    let line: Int?
    let html: String
    let text: String

    var date: Date { Date(timeIntervalSince1970: time) }
}

/// Accepts one JSON document per connection on 127.0.0.1 and hands it to `onPayload`.
final class DumpServer: @unchecked Sendable {
    private let lock = NSLock()
    private var fd: Int32 = -1
    var onPayload: (@Sendable (Data) -> Void)?

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
        guard r == 0, listen(s, 32) == 0 else { close(s); return false }
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
            Thread.detachNewThread { [weak self] in self?.read(client) }
        }
    }

    private func read(_ c: Int32) {
        defer { close(c) }
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while data.count < 16 * 1024 * 1024 {
            let n = Darwin.read(c, &chunk, chunk.count)
            if n <= 0 { break }
            data.append(contentsOf: chunk[0..<n])
        }
        if !data.isEmpty { onPayload?(data) }
    }
}

// MARK: - PHP side

/// The PHP half: an `auto_prepend_file` that, for projects that ship
/// symfony/var-dumper, defines `dump()` / `dd()` before Composer does. They
/// behave like Symfony's (so the page still shows the dump) and also send each
/// dump to Nerd. Projects without var-dumper are left untouched.
enum DumpHook {
    static let dir = Paths.root.appendingPathComponent("php")
    static let prepend = dir.appendingPathComponent("prepend.php")
    /// Named like Symfony's file on purpose: Laravel finds the caller of a dump
    /// by looking for a frame in ".../symfony/var-dumper/Resources/functions/dump.php".
    static let functions = dir.appendingPathComponent("symfony/var-dumper/Resources/functions/dump.php")

    static func write(port: Int, browser: Bool) {
        try? FileManager.default.createDirectory(at: functions.deletingLastPathComponent(), withIntermediateDirectories: true)
        writeIfChanged(prependSource(port: port, browser: browser), to: prepend)
        writeIfChanged(functionsSource, to: functions)
    }

    private static func writeIfChanged(_ text: String, to url: URL) {
        if (try? String(contentsOf: url, encoding: .utf8)) == text { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Plain PHP 7.2 syntax so every installed version can parse it.
    static func prependSource(port: Int, browser: Bool) -> String {
        #"""
        <?php
        // Written by Nerd: sends dump() / dd() output to the app. Regenerated on launch.

        if (!class_exists('NerdDumps', false)) {
            final class NerdDumps
            {
                const PORT = \#(port);
                const BROWSER = \#(browser ? "true" : "false");

                public static $root;
                public static $request;

                /** The project directory, when it has symfony/var-dumper installed. */
                public static function detect()
                {
                    $dirs = array();
                    if (PHP_SAPI === 'cli' || PHP_SAPI === 'phpdbg') {
                        $dirs[] = getcwd();
                    }
                    if (!empty($_SERVER['SCRIPT_FILENAME'])) {
                        $script = realpath($_SERVER['SCRIPT_FILENAME']);
                        $dirs[] = dirname($script ? $script : $_SERVER['SCRIPT_FILENAME']);
                    }
                    foreach ($dirs as $dir) {
                        for ($i = 0; $i < 4 && $dir; $i++) {
                            if (is_dir($dir . '/vendor/symfony/var-dumper')) {
                                return $dir;
                            }
                            $parent = dirname($dir);
                            if ($parent === $dir) {
                                break;
                            }
                            $dir = $parent;
                        }
                    }
                    return null;
                }

                /** Whether the dump should also be printed as usual. */
                public static function output()
                {
                    return self::BROWSER || PHP_SAPI === 'cli' || PHP_SAPI === 'phpdbg';
                }

                public static function send(array $vars, $kind)
                {
                    try {
                        if (!class_exists('Symfony\Component\VarDumper\Cloner\VarCloner')) {
                            return;
                        }
                        if (!$vars) {
                            $vars = array(class_exists('Symfony\Component\VarDumper\Caster\ScalarStub')
                                ? new \Symfony\Component\VarDumper\Caster\ScalarStub('🐛') : '🐛');
                        }
                        $cloner = new \Symfony\Component\VarDumper\Cloner\VarCloner();
                        $html = new \Symfony\Component\VarDumper\Dumper\HtmlDumper();
                        $cli = new \Symfony\Component\VarDumper\Dumper\CliDumper();
                        $cli->setColors(false);
                        $htmlOut = '';
                        $textOut = '';
                        foreach ($vars as $k => $v) {
                            $data = $cloner->cloneVar($v);
                            $htmlOut .= $html->dump($data, true);
                            $textOut .= $cli->dump($data, true);
                        }

                        list($file, $line) = self::source();
                        if (self::$request === null) {
                            self::$request = bin2hex(random_bytes(8));
                        }
                        $cliMode = PHP_SAPI === 'cli' || PHP_SAPI === 'phpdbg';
                        $payload = array(
                            'id' => bin2hex(random_bytes(8)),
                            'request' => self::$request,
                            'time' => microtime(true),
                            'kind' => $kind,
                            'host' => isset($_SERVER['HTTP_HOST']) ? $_SERVER['HTTP_HOST'] : null,
                            'method' => isset($_SERVER['REQUEST_METHOD']) ? $_SERVER['REQUEST_METHOD'] : null,
                            'uri' => isset($_SERVER['REQUEST_URI']) ? $_SERVER['REQUEST_URI'] : null,
                            'command' => $cliMode && isset($_SERVER['argv']) ? implode(' ', $_SERVER['argv']) : null,
                            'root' => self::$root,
                            'file' => $file,
                            'line' => $line,
                            'html' => $htmlOut,
                            'text' => $textOut,
                        );
                        $json = json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE);
                        if ($json === false) {
                            return;
                        }
                        $socket = @stream_socket_client('tcp://127.0.0.1:' . self::PORT, $errno, $errstr, 0.25);
                        if (!$socket) {
                            return;
                        }
                        stream_set_timeout($socket, 1);
                        for ($written = 0; $written < strlen($json); $written += $n) {
                            $n = @fwrite($socket, substr($json, $written));
                            if (!$n) {
                                break;
                            }
                        }
                        fclose($socket);
                    } catch (\Throwable $e) {
                        // Never let Nerd break the page
                    }
                }

                /** The first caller outside vendor/ and this hook. */
                private static function source()
                {
                    $trace = debug_backtrace(DEBUG_BACKTRACE_IGNORE_ARGS, 30);
                    $fallback = array(null, null);
                    foreach ($trace as $frame) {
                        if (!isset($frame['file']) || strpos($frame['file'], __DIR__ . '/') === 0) {
                            continue;
                        }
                        if (strpos($frame['file'], "eval()'d code") !== false) {
                            return array(null, null); // tinker
                        }
                        $found = array($frame['file'], isset($frame['line']) ? $frame['line'] : null);
                        if ($fallback[0] === null) {
                            $fallback = $found;
                        }
                        if (strpos($frame['file'], '/vendor/') === false) {
                            return self::view($found);
                        }
                    }
                    return self::view($fallback);
                }

                /** Maps a compiled Blade view back to its template. */
                private static function view(array $source)
                {
                    if ($source[0] && strpos($source[0], '/storage/framework/views/') !== false) {
                        $code = @file_get_contents($source[0]);
                        if ($code && preg_match('/\/\*\*PATH\s(.*)\sENDPATH/', $code, $m)) {
                            return array($m[1], null);
                        }
                    }
                    return $source;
                }
            }

            NerdDumps::$root = NerdDumps::detect();
            if (NerdDumps::$root !== null && !function_exists('dump') && !function_exists('dd')) {
                require __DIR__ . '/symfony/var-dumper/Resources/functions/dump.php';
            }
        }

        """#
    }

    /// Mirrors symfony/var-dumper's functions; `VarDumper::dump` must stay called
    /// directly from these functions for Laravel's source detection.
    static let functionsSource = #"""
    <?php
    // Written by Nerd. Mirrors symfony/var-dumper/Resources/functions/dump.php
    // and also sends every dump to the Nerd app.

    use Symfony\Component\VarDumper\VarDumper;

    function dump(...$vars)
    {
        NerdDumps::send($vars, 'dump');

        if (NerdDumps::output()) {
            if (!$vars) {
                VarDumper::dump(class_exists('Symfony\Component\VarDumper\Caster\ScalarStub')
                    ? new \Symfony\Component\VarDumper\Caster\ScalarStub('🐛') : '🐛');

                return null;
            }

            if (array_key_exists(0, $vars) && 1 === count($vars)) {
                VarDumper::dump($vars[0]);
            } else {
                foreach ($vars as $k => $v) {
                    VarDumper::dump($v, is_int($k) ? 1 + $k : $k);
                }
            }
        }

        if (!$vars) {
            return null;
        }
        if (1 < count($vars)) {
            return $vars;
        }

        return reset($vars);
    }

    function dd(...$vars)
    {
        if (!in_array(\PHP_SAPI, array('cli', 'phpdbg', 'embed'), true) && !headers_sent()) {
            header('HTTP/1.1 500 Internal Server Error');
        }

        NerdDumps::send($vars, 'dd');

        if (NerdDumps::output()) {
            if (!$vars) {
                VarDumper::dump(class_exists('Symfony\Component\VarDumper\Caster\ScalarStub')
                    ? new \Symfony\Component\VarDumper\Caster\ScalarStub('🐛') : '🐛');

                exit(1);
            }

            if (array_key_exists(0, $vars) && 1 === count($vars)) {
                VarDumper::dump($vars[0]);
            } else {
                foreach ($vars as $k => $v) {
                    VarDumper::dump($v, is_int($k) ? 1 + $k : $k);
                }
            }
        }

        exit(1);
    }

    """#

    /// CLI (artisan, tinker, tests) reads conf.d instead of the FPM pool.
    static func cliIni(_ v: PHPVersion) -> URL {
        URL(fileURLWithPath: "\(Paths.brew)/etc/php/\(v.version)/conf.d/zz-nerd-dumps.ini")
    }
}

// MARK: - App state

extension AppState {
    static let maxDumps = 300

    func startDumpServer() {
        writeDumpHook()
        dumpServer.onPayload = { data in
            guard let entry = try? JSONDecoder().decode(DumpEntry.self, from: data) else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let state = AppState.shared
                    guard !state.dumpsPaused else { return }
                    state.dumps.insert(entry, at: 0)
                    if state.dumps.count > Self.maxDumps { state.dumps.removeLast(state.dumps.count - Self.maxDumps) }
                }
            }
        }
        dumpsRunning = dumpServer.start(port: UInt16(config.dumpPort))
    }

    func writeDumpHook() {
        DumpHook.write(port: config.dumpPort, browser: config.dumpsInBrowser)
        for v in installedPHP {
            let ini = DumpHook.cliIni(v)
            if config.dumpsCLI {
                let text = "; Written by Nerd: sends dump() / dd() from artisan, tinker and tests to the app.\nauto_prepend_file = \"\(DumpHook.prepend.path)\"\n"
                if (try? String(contentsOf: ini, encoding: .utf8)) != text {
                    try? FileManager.default.createDirectory(at: ini.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? text.write(to: ini, atomically: true, encoding: .utf8)
                }
            } else if Paths.exists(ini.path) {
                try? FileManager.default.removeItem(at: ini)
            }
        }
    }

    /// The site a dump came from: its project directory, else its host name.
    func siteName(for dump: DumpEntry) -> String? {
        if let root = dump.root {
            let resolved = URL(fileURLWithPath: root).resolvingSymlinksInPath().path
            if let site = sites.first(where: { $0.path.resolvingSymlinksInPath().path == resolved }) { return site.name }
            return (root as NSString).lastPathComponent
        }
        return dump.host?.components(separatedBy: ":").first
    }
}
