import SwiftUI

@MainActor @Observable
final class DBBrowser {
    var connection: DBConnection?
    var databases: [String] = []
    var tables: [String] = []
    var table: String?
    var result = QueryResult()
    var primaryKey: [String] = []
    var total = 0
    var page = 0
    let pageSize = 100
    var orderBy: String?
    var descending = false
    var error: String?
    var loading = false

    var sql = ""
    var sqlResult: QueryResult?
    var sqlError: String?
    var sqlRunning = false

    var client: DBClient? { connection.map { DBClient(conn: $0) } }
    var pageCount: Int { max(1, Int((Double(total) / Double(pageSize)).rounded(.up))) }

    func select(_ c: DBConnection) async {
        connection = c
        table = nil
        result = QueryResult()
        databases = []
        await loadTables()
        if let client { databases = (try? await client.databases()) ?? [] }
    }

    func useDatabase(_ name: String) async {
        connection?.database = name
        table = nil
        result = QueryResult()
        await loadTables()
    }

    func loadTables() async {
        guard let client else { return }
        loading = true
        defer { loading = false }
        do {
            tables = try await client.tables()
            error = nil
        } catch {
            tables = []
            self.error = error.localizedDescription
        }
    }

    func open(_ t: String) async {
        table = t
        page = 0
        orderBy = nil
        descending = false
        if let client { primaryKey = (try? await client.primaryKey(t)) ?? [] }
        await reload()
    }

    func reload() async {
        guard let client, let table else { return }
        loading = true
        defer { loading = false }
        do {
            total = try await client.count(table)
            result = try await client.page(table, limit: pageSize, offset: page * pageSize, orderBy: orderBy, descending: descending)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func sort(by column: String) async {
        if orderBy == column { descending.toggle() } else { orderBy = column; descending = false }
        await reload()
    }

    private func keys(for row: Int) -> [String: String?]? {
        guard !primaryKey.isEmpty, row < result.rows.count else { return nil }
        var k: [String: String?] = [:]
        for pk in primaryKey {
            guard let i = result.columns.firstIndex(of: pk) else { return nil }
            k[pk] = result.rows[row][i]
        }
        return k
    }

    var editable: Bool { !primaryKey.isEmpty && primaryKey.allSatisfy(result.columns.contains) }

    func commit(row: Int, column: Int, value: String?) async {
        guard let client, let table, let keys = keys(for: row) else { return }
        do {
            try await client.update(table, column: result.columns[column], value: value, keys: keys)
            result.rows[row][column] = value
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func delete(row: Int) async {
        guard let client, let table, let keys = keys(for: row) else { return }
        do {
            try await client.delete(table, keys: keys)
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func runSQL() async {
        guard let client, !sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        sqlRunning = true
        defer { sqlRunning = false }
        do {
            sqlResult = try await client.run(sql)
            sqlError = nil
            await loadTables()
        } catch {
            sqlResult = nil
            sqlError = error.localizedDescription
        }
    }
}

struct DatabaseView: View {
    @Environment(AppState.self) private var state
    @State private var browser = DBBrowser()
    @State private var editingConnection: DBConnection?
    @State private var tab = 0
    @State private var tableFilter = ""

    private var allConnections: [DBConnection] { state.siteConnections + state.config.connections }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 250)
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(item: $editingConnection) { c in
            ConnectionEditor(connection: c) { saved in
                if let i = state.config.connections.firstIndex(where: { $0.id == saved.id }) {
                    state.config.connections[i] = saved
                } else {
                    state.config.connections.append(saved)
                }
                Task { await browser.select(saved) }
            }
        }
        .task(id: state.databaseFocus) {
            guard let focus = state.databaseFocus else { return }
            // "<connection id>" or "<connection id>#<table>"
            let parts = focus.split(separator: "#", maxSplits: 1).map(String.init)
            if let c = allConnections.first(where: { $0.id == parts[0] }) {
                state.databaseFocus = nil
                await browser.select(c)
                if parts.count > 1 { await browser.open(parts[1]) }
            }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List {
                Section("Bağlantılar") {
                    ForEach(allConnections) { c in
                        Button { Task { await browser.select(c) } } label: {
                            HStack {
                                Tile(systemName: c.driver == .sqlite ? "doc.fill" : "cylinder.fill", size: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(c.name.ifEmpty(c.summary)).lineLimit(1)
                                    Text(c.driver.title).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if c.site != nil { NerdIcon(name: "globe").font(.caption2).foregroundStyle(.secondary) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 2)
                        .background(browser.connection?.id == c.id ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 5))
                        .contextMenu {
                            if c.site == nil {
                                Button("Düzenle") { editingConnection = c }
                                Button("Sil", role: .destructive) { state.config.connections.removeAll { $0.id == c.id } }
                            } else {
                                Button("Kopyala ve düzenle") {
                                    var copy = c; copy.id = UUID().uuidString; copy.site = nil
                                    editingConnection = copy
                                }
                            }
                        }
                    }
                }
                if browser.connection != nil {
                    Section("Tablolar (\(browser.tables.count))") {
                        ForEach(browser.tables.filter { tableFilter.isEmpty || $0.localizedCaseInsensitiveContains(tableFilter) }, id: \.self) { t in
                            Button { tab = 0; Task { await browser.open(t) } } label: {
                                Label(t, systemImage: "tablecells").lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 1)
                            .background(browser.table == t ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 5))
                        }
                    }
                }
            }
            if browser.connection != nil {
                TextField("Tablo ara", text: $tableFilter).textFieldStyle(.roundedBorder).padding(.horizontal, 8).padding(.top, 6)
            }
            HStack {
                Button { editingConnection = DBConnection(name: String(localized: "Yeni bağlantı")) } label: { Label("Bağlantı", systemImage: "plus") }
                Spacer()
                Button { Task { await browser.loadTables() } } label: { NerdIcon(name: "arrow.clockwise") }
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let conn = browser.connection {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(browser.table ?? conn.name.ifEmpty("Bağlantı")).font(.system(size: 15, weight: .semibold))
                        Text(conn.summary).font(.caption).foregroundStyle(.secondary)
                    }
                    if !browser.databases.isEmpty {
                        Picker("Veritabanı", selection: Binding(
                            get: { browser.connection?.database ?? "" },
                            set: { v in Task { await browser.useDatabase(v) } })) {
                            ForEach(browser.databases, id: \.self) { Text($0).tag($0) }
                            if !browser.databases.contains(conn.database) { Text(conn.database.ifEmpty("—")).tag(conn.database) }
                        }
                        .frame(width: 220)
                    }
                    Spacer()
                    if browser.loading { ProgressView().controlSize(.small) }
                    Picker("", selection: $tab) {
                        Text("Veri").tag(0)
                        Text("SQL").tag(1)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 140)
                }
                if let err = browser.error {
                    Text(err).font(.caption.monospaced()).foregroundStyle(.red).textSelection(.enabled)
                }
                if tab == 0 { dataTab } else { sqlTab }
            }
            .padding(14)
        } else {
            ContentUnavailableView("Bağlantı seçin", systemImage: "tablecells",
                                   description: Text("Site .env dosyalarındaki veritabanları otomatik listelenir."))
        }
    }

    @ViewBuilder
    private var dataTab: some View {
        if browser.table != nil {
            ResultGrid(result: browser.result,
                       editable: browser.editable,
                       sortColumn: browser.orderBy,
                       descending: browser.descending,
                       onSort: { c in Task { await browser.sort(by: c) } },
                       onCommit: { r, c, v in Task { await browser.commit(row: r, column: c, value: v) } },
                       onDelete: { r in Task { await browser.delete(row: r) } })
            HStack {
                Text("\(browser.total) satır").foregroundStyle(.secondary)
                if !browser.editable { Text("· birincil anahtar yok, salt okunur").foregroundStyle(.tertiary) }
                Spacer()
                Button { browser.page -= 1; Task { await browser.reload() } } label: { NerdIcon(name: "chevron.left") }
                    .disabled(browser.page == 0)
                Text("\(browser.page + 1) / \(browser.pageCount)").monospacedDigit()
                Button { browser.page += 1; Task { await browser.reload() } } label: { NerdIcon(name: "chevron.right") }
                    .disabled(browser.page + 1 >= browser.pageCount)
                Button { Task { await browser.reload() } } label: { NerdIcon(name: "arrow.clockwise") }
            }
            .font(.callout)
        } else {
            ContentUnavailableView("Tablo seçin", systemImage: "sidebar.left")
        }
    }

    private var sqlTab: some View {
        @Bindable var browser = browser
        return VSplitView {
            VStack(alignment: .leading, spacing: 6) {
                TextEditor(text: $browser.sql)
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                HStack {
                    Text("⌘↩ ile çalıştır").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if browser.sqlRunning { ProgressView().controlSize(.small) }
                    Button("Çalıştır") { Task { await browser.runSQL() } }
                        .keyboardShortcut(.return, modifiers: .command)
                        .buttonStyle(.borderedProminent)
                }
            }
            .frame(minHeight: 120, idealHeight: 180)
            VStack(alignment: .leading) {
                if let err = browser.sqlError {
                    Text(err).font(.callout.monospaced()).foregroundStyle(.red).textSelection(.enabled)
                } else if let r = browser.sqlResult {
                    if let msg = r.message, r.columns.isEmpty {
                        Text(msg).foregroundStyle(.secondary)
                    } else {
                        Text("\(r.rows.count) satır").font(.caption).foregroundStyle(.secondary)
                        ResultGrid(result: r)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 150, maxHeight: .infinity)
            .padding(.top, 6)
        }
    }
}

// MARK: - Grid

private struct CellRef: Identifiable {
    var id: String { "\(row):\(column)" }
    let row: Int
    let column: Int
    let value: String?
}

struct ResultGrid: View {
    let result: QueryResult
    var editable = false
    var sortColumn: String? = nil
    var descending = false
    var onSort: ((String) -> Void)? = nil
    var onCommit: ((Int, Int, String?) -> Void)? = nil
    var onDelete: ((Int) -> Void)? = nil

    @State private var editing: CellRef?
    @State private var selectedRow: Int?

    private var widths: [CGFloat] {
        result.columns.enumerated().map { i, name in
            let sample = result.rows.prefix(50).map { ($0[safe: i] ?? nil)?.count ?? 4 }.max() ?? 4
            return min(320, max(70, CGFloat(max(sample, name.count)) * 7.4 + 20))
        }
    }

    var body: some View {
        let widths = widths
        GeometryReader { geo in
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(result.rows.indices, id: \.self) { r in
                        HStack(spacing: 0) {
                            ForEach(result.columns.indices, id: \.self) { c in
                                cell(result.rows[r][safe: c] ?? nil)
                                    .frame(width: widths[c], alignment: .leading)
                                    .contentShape(Rectangle())
                                    .onTapGesture(count: 2) {
                                        if editable { editing = CellRef(row: r, column: c, value: result.rows[r][safe: c] ?? nil) }
                                    }
                                    .onTapGesture { selectedRow = r }
                                Divider()
                            }
                        }
                        .frame(height: 24)
                        .background(selectedRow == r ? Color.accentColor.opacity(0.18) : (r.isMultiple(of: 2) ? Color.clear : Color.secondary.opacity(0.05)))
                        .contextMenu {
                            if editable {
                                Button("Satırı sil", role: .destructive) { onDelete?(r) }
                            }
                            Button("Satırı kopyala (TSV)") {
                                let line = result.rows[r].map { $0 ?? "NULL" }.joined(separator: "\t")
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(line, forType: .string)
                            }
                        }
                    }
                } header: {
                    HStack(spacing: 0) {
                        ForEach(result.columns.indices, id: \.self) { c in
                            let name = result.columns[c]
                            Button { onSort?(name) } label: {
                                HStack(spacing: 3) {
                                    Text(name).font(.caption.bold()).lineLimit(1)
                                    if sortColumn == name {
                                        NerdIcon(name: descending ? "chevron.down" : "chevron.up").font(.caption2)
                                    }
                                }
                                .padding(.horizontal, 6)
                                .frame(width: widths[c], height: 26, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(onSort == nil)
                            Divider()
                        }
                    }
                    .background(.bar)
                    .overlay(alignment: .bottom) { Divider() }
                }
            }
            .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
        }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
        .sheet(item: $editing) { ref in
            CellEditor(column: result.columns[ref.column], value: ref.value) { newValue in
                onCommit?(ref.row, ref.column, newValue)
            }
        }
    }

    @ViewBuilder
    private func cell(_ value: String?) -> some View {
        Group {
            if let value {
                Text(value.replacingOccurrences(of: "\n", with: "⏎ "))
            } else {
                Text("NULL").italic().foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: 12, design: .monospaced))
        .lineLimit(1)
        .padding(.horizontal, 6)
    }
}

struct CellEditor: View {
    @Environment(\.dismiss) private var dismiss
    let column: String
    let value: String?
    let onSave: (String?) -> Void
    @State private var text = ""
    @State private var isNull = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(column).font(.headline)
            TextEditor(text: $text)
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: 160)
                .disabled(isNull)
                .opacity(isNull ? 0.4 : 1)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator))
            Toggle("NULL", isOn: $isNull)
            HStack {
                Spacer()
                Button("Vazgeç") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Kaydet") { onSave(isNull ? nil : text); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 460)
        .onAppear { text = value ?? ""; isNull = value == nil }
    }
}

struct ConnectionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var connection: DBConnection
    let onSave: (DBConnection) -> Void
    @State private var testResult: String?

    var body: some View {
        VStack(alignment: .leading) {
            Form {
                TextField("Ad", text: $connection.name)
                Picker("Sürücü", selection: $connection.driver) {
                    ForEach(DBDriver.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: connection.driver) {
                    connection.port = connection.driver.defaultPort
                    if connection.driver == .pgsql && connection.username == "root" { connection.username = NSUserName() }
                }
                if connection.driver == .sqlite {
                    HStack {
                        TextField("Dosya", text: $connection.file)
                        Button("Seç…") { if let u = Panels.chooseFile() { connection.file = u.path } }
                    }
                } else {
                    TextField("Sunucu", text: $connection.host)
                    TextField("Port", value: $connection.port, format: .number.grouping(.never))
                    TextField("Kullanıcı", text: $connection.username)
                    SecureField("Şifre", text: $connection.password)
                    TextField("Veritabanı", text: $connection.database)
                }
            }
            .formStyle(.grouped)
            if let testResult { Text(testResult).font(.caption).padding(.horizontal) }
            HStack {
                Button("Bağlantıyı test et") {
                    let c = connection
                    Task {
                        do { _ = try await DBClient(conn: c).run("SELECT 1"); testResult = String(localized: "✓ Bağlantı başarılı") }
                        catch { testResult = "✗ \(error.localizedDescription)" }
                    }
                }
                Spacer()
                Button("Vazgeç") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Kaydet") { onSave(connection); dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 460)
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
