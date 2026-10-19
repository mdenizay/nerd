import Foundation
import SQLite3

struct QueryResult: Sendable {
    var columns: [String] = []
    var rows: [[String?]] = []
    var message: String?
}

struct DBError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Lightweight database access. SQLite uses the C API; MySQL and PostgreSQL go through their CLI clients.
struct DBClient: Sendable {
    var conn: DBConnection

    static var mysqlBinary: String? {
        Shell.which("mysql") ?? ["mysql-client", "mysql", "mariadb"].map { "\(Paths.brew)/opt/\($0)/bin/mysql" }.first(where: Paths.exists)
    }

    static var psqlBinary: String? {
        Shell.which("psql") ?? (13...20).reversed().map { "\(Paths.brew)/opt/postgresql@\($0)/bin/psql" }.first(where: Paths.exists)
    }

    // MARK: Quoting

    func ident(_ s: String) -> String {
        switch conn.driver {
        case .mysql: "`" + s.replacingOccurrences(of: "`", with: "``") + "`"
        default: "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
    }

    func literal(_ s: String?) -> String {
        guard let s else { return "NULL" }
        var v = s.replacingOccurrences(of: "'", with: "''")
        if conn.driver == .mysql { v = v.replacingOccurrences(of: "\\", with: "\\\\") }
        return "'\(v)'"
    }

    // MARK: Metadata

    func tables() async throws -> [String] {
        let sql: String = switch conn.driver {
        case .sqlite: "SELECT name FROM sqlite_master WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%' ORDER BY name"
        case .mysql: "SHOW FULL TABLES"
        case .pgsql: "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name"
        }
        return try await run(sql).rows.compactMap { $0.first ?? nil }
    }

    func databases() async throws -> [String] {
        switch conn.driver {
        case .sqlite: return []
        case .mysql: return try await run("SHOW DATABASES").rows.compactMap { $0.first ?? nil }
        case .pgsql: return try await run("SELECT datname FROM pg_database WHERE NOT datistemplate ORDER BY datname").rows.compactMap { $0.first ?? nil }
        }
    }

    func columns(_ table: String) async throws -> [String] {
        let sql: String = switch conn.driver {
        case .sqlite: "SELECT name FROM pragma_table_info(\(literal(table)))"
        case .mysql: "SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = \(literal(table)) ORDER BY ORDINAL_POSITION"
        case .pgsql: "SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = \(literal(table)) ORDER BY ordinal_position"
        }
        return try await run(sql).rows.compactMap { $0.first ?? nil }
    }

    func primaryKey(_ table: String) async throws -> [String] {
        let sql: String = switch conn.driver {
        case .sqlite: "SELECT name FROM pragma_table_info(\(literal(table))) WHERE pk > 0 ORDER BY pk"
        case .mysql: "SELECT COLUMN_NAME FROM information_schema.KEY_COLUMN_USAGE WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = \(literal(table)) AND CONSTRAINT_NAME = 'PRIMARY' ORDER BY ORDINAL_POSITION"
        case .pgsql: "SELECT a.attname FROM pg_index i JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey) WHERE i.indrelid = \(literal(ident(table)))::regclass AND i.indisprimary"
        }
        return try await run(sql).rows.compactMap { $0.first ?? nil }
    }

    func count(_ table: String) async throws -> Int {
        let r = try await run("SELECT COUNT(*) FROM \(ident(table))")
        return Int((r.rows.first?.first ?? nil) ?? "0") ?? 0
    }

    func page(_ table: String, limit: Int, offset: Int, orderBy: String? = nil, descending: Bool = false) async throws -> QueryResult {
        var sql = "SELECT * FROM \(ident(table))"
        if let orderBy { sql += " ORDER BY \(ident(orderBy)) \(descending ? "DESC" : "ASC")" }
        sql += " LIMIT \(limit) OFFSET \(offset)"
        var r = try await run(sql)
        if r.columns.isEmpty { r.columns = try await columns(table) }
        return r
    }

    func update(_ table: String, column: String, value: String?, keys: [String: String?]) async throws {
        let whereSQL = keys.map { k, v in v == nil ? "\(ident(k)) IS NULL" : "\(ident(k)) = \(literal(v))" }.joined(separator: " AND ")
        _ = try await run("UPDATE \(ident(table)) SET \(ident(column)) = \(literal(value)) WHERE \(whereSQL)")
    }

    func delete(_ table: String, keys: [String: String?]) async throws {
        let whereSQL = keys.map { k, v in v == nil ? "\(ident(k)) IS NULL" : "\(ident(k)) = \(literal(v))" }.joined(separator: " AND ")
        _ = try await run("DELETE FROM \(ident(table)) WHERE \(whereSQL)")
    }

    // MARK: Execution

    func run(_ sql: String) async throws -> QueryResult {
        switch conn.driver {
        case .sqlite:
            let path = conn.file
            return try await Task.detached { try Self.sqlite(path: path, sql: sql) }.value
        case .mysql:
            return try await mysql(sql)
        case .pgsql:
            return try await pgsql(sql)
        }
    }

    private static func sqlite(path: String, sql: String) throws -> QueryResult {
        guard FileManager.default.fileExists(atPath: path) else { throw DBError(message: String(localized: "Dosya bulunamadı: \(path)")) }
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? String(localized: "açılamadı")
            sqlite3_close(db)
            throw DBError(message: msg)
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 3000)

        var result = QueryResult()
        var error: String?
        sql.withCString { start in
            var cursor: UnsafePointer<CChar>? = start
            while let cur = cursor, cur.pointee != 0 {
                var stmt: OpaquePointer?
                var tail: UnsafePointer<CChar>?
                if sqlite3_prepare_v2(db, cur, -1, &stmt, &tail) != SQLITE_OK {
                    error = String(cString: sqlite3_errmsg(db))
                    return
                }
                cursor = tail
                guard let stmt else { continue } // whitespace / comment
                defer { sqlite3_finalize(stmt) }
                let n = sqlite3_column_count(stmt)
                var current = QueryResult()
                current.columns = (0..<n).map { String(cString: sqlite3_column_name(stmt, $0)) }
                while true {
                    let rc = sqlite3_step(stmt)
                    if rc == SQLITE_ROW {
                        current.rows.append((0..<n).map { i -> String? in
                            switch sqlite3_column_type(stmt, i) {
                            case SQLITE_NULL: return nil
                            case SQLITE_BLOB: return "<BLOB \(sqlite3_column_bytes(stmt, i)) bayt>"
                            default: return sqlite3_column_text(stmt, i).map { String(cString: $0) }
                            }
                        })
                    } else if rc == SQLITE_DONE {
                        break
                    } else {
                        error = String(cString: sqlite3_errmsg(db))
                        return
                    }
                }
                if n == 0 { current.message = String(localized: "\(Int(sqlite3_changes(db))) satır etkilendi") }
                result = current
            }
        }
        if let error { throw DBError(message: error) }
        return result
    }

    private func mysql(_ sql: String) async throws -> QueryResult {
        guard let bin = Self.mysqlBinary else { throw DBError(message: String(localized: "mysql istemcisi bulunamadı (brew install mysql-client)")) }
        var args = ["-h", conn.host, "-P", String(conn.port), "-u", conn.username, "--xml", "--default-character-set=utf8mb4"]
        if !conn.database.isEmpty { args.append(conn.database) }
        args += ["-e", sql]
        var extra: [String: String] = [:]
        if !conn.password.isEmpty { extra["MYSQL_PWD"] = conn.password }
        let r = await Shell.run(bin, args, env: Shell.env(extra))
        guard r.ok else { throw DBError(message: r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)) }
        var result = MySQLXMLParser.parse(r.stdout)
        if result.columns.isEmpty && result.rows.isEmpty { result.message = String(localized: "Sorgu çalıştırıldı") }
        return result
    }

    private static let pgNull = "\u{2400}NULL\u{2400}"

    private func pgsql(_ sql: String) async throws -> QueryResult {
        guard let bin = Self.psqlBinary else { throw DBError(message: String(localized: "psql bulunamadı (brew install postgresql)")) }
        let args = ["-X", "-q", "--csv", "-v", "ON_ERROR_STOP=1", "-P", "null=\(Self.pgNull)",
                    "-h", conn.host, "-p", String(conn.port), "-U", conn.username,
                    "-d", conn.database.isEmpty ? "postgres" : conn.database, "-c", sql]
        var extra: [String: String] = [:]
        if !conn.password.isEmpty { extra["PGPASSWORD"] = conn.password }
        let r = await Shell.run(bin, args, env: Shell.env(extra))
        guard r.ok else { throw DBError(message: r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let table = CSV.parse(r.stdout)
        guard let header = table.first else { return QueryResult(message: String(localized: "Sorgu çalıştırıldı")) }
        let rows = table.dropFirst().map { $0.map { $0 == Self.pgNull ? nil : $0 } }
        return QueryResult(columns: header, rows: Array(rows))
    }
}

// MARK: - Parsers

enum CSV {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = text.makeIterator()
        var pending: Character?
        while let c = pending ?? chars.next() {
            pending = nil
            if inQuotes {
                if c == "\"" {
                    if let n = chars.next() {
                        if n == "\"" { field.append("\"") } else { inQuotes = false; pending = n }
                    } else { inQuotes = false }
                } else { field.append(c) }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n", "\r\n": row.append(field); rows.append(row); row = []; field = ""
                case "\r": break
                default: field.append(c)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}

final class MySQLXMLParser: NSObject, XMLParserDelegate {
    private var result = QueryResult()
    private var current: [String?] = []
    private var currentColumns: [String] = []
    private var field: String?
    private var isNil = false
    private var inRow = false

    static func parse(_ xml: String) -> QueryResult {
        let p = MySQLXMLParser()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = p
        parser.parse()
        return p.result
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        switch name {
        case "resultset":
            result = QueryResult()
        case "row":
            inRow = true
            current = []
            currentColumns = []
        case "field" where inRow:
            field = ""
            isNil = attributes["xsi:nil"] == "true"
            currentColumns.append(attributes["name"] ?? "")
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if field != nil { field! += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "field" where inRow:
            current.append(isNil ? nil : field)
            field = nil
        case "row":
            inRow = false
            if result.columns.isEmpty { result.columns = currentColumns }
            result.rows.append(current)
        default: break
        }
    }
}
