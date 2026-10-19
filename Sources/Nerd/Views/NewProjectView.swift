import SwiftUI

/// New project, on one native form: template gallery, project, runtime, options.
/// While creating, the same page shows progress and then the result.
struct NewProjectView: View {
    @Environment(AppState.self) private var state
    @State private var o = NewProjectOptions()
    @State private var group: ProjectTemplate.Group = .laravel
    @State private var job: Job?
    @State private var showLog = false

    private var slug: String { AppState.slug(o.name) }
    private var exists: Bool {
        !slug.isEmpty && FileManager.default.fileExists(atPath: URL(fileURLWithPath: o.location).appendingPathComponent(slug).path)
    }
    private var canCreate: Bool {
        !slug.isEmpty && !exists && (o.template != .custom || !o.customPackage.isEmpty)
    }

    var body: some View {
        Group {
            if let job { progress(job) } else { form }
        }
        .onAppear {
            if o.location.isEmpty { o.location = state.config.parkedPaths.first ?? Paths.home.path }
            group = o.template.group
        }
    }

    // MARK: Form

    private var form: some View {
        Form {
            Section {
                Picker("", selection: $group) {
                    ForEach(ProjectTemplate.Group.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: group) {
                    if o.template.group != group, let first = ProjectTemplate.allCases.first(where: { $0.group == group }) {
                        o.template = first
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(ProjectTemplate.allCases.filter { $0.group == group }) { t in
                        TemplateCard(template: t, selected: o.template == t) { o.template = t }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Şablon")
            }

            Section("Proje") {
                TextField("Proje adı", text: $o.name, prompt: Text(verbatim: "my-app"))
                LabeledContent("Adres") {
                    if exists {
                        Text("Bu klasör zaten var.").foregroundStyle(.red)
                    } else {
                        Text(verbatim: slug.isEmpty ? "—" : "\(o.secure ? "https" : "http")://\(slug).\(state.config.tld)")
                            .foregroundStyle(slug.isEmpty ? Color.secondary : Color.brand)
                    }
                }
                Picker("Konum", selection: $o.location) {
                    ForEach(state.config.parkedPaths, id: \.self) { Text(($0 as NSString).abbreviatingWithTildeInPath).tag($0) }
                    if !state.config.parkedPaths.contains(o.location) && !o.location.isEmpty {
                        Text((o.location as NSString).abbreviatingWithTildeInPath).tag(o.location)
                    }
                }
                if o.template == .custom {
                    TextField("Composer paketi", text: $o.customPackage, prompt: Text(verbatim: "vendor/package"))
                }
            }

            Section("Ortam") {
                if o.template.isDotnet {
                    Picker(selection: $o.dotnet) {
                        Text("Varsayılan (\(state.defaultDotnet?.major ?? "—"))").tag(String?.none)
                        ForEach(state.installedDotnet) { Text(verbatim: ".NET \($0.major)").tag(Optional($0.major)) }
                    } label: { Text(verbatim: ".NET") }
                } else {
                    if !o.template.isNode {
                        Picker("PHP", selection: $o.php) {
                            Text("Varsayılan (\(state.defaultPHP?.version ?? "—"))").tag(String?.none)
                            ForEach(state.installedPHP) { Text(verbatim: "PHP \($0.version)").tag(Optional($0.version)) }
                        }
                    }
                    Picker("Node", selection: $o.node) {
                        Text("Varsayılan (\(state.defaultNode?.version ?? "—"))").tag(String?.none)
                        ForEach(state.nodeVersions) { Text(verbatim: $0.label).tag(Optional($0.version)) }
                    }
                }
                if o.template.isLaravel || o.template == .custom {
                    Picker("Veritabanı", selection: $o.database) {
                        ForEach(DBDriver.allCases) { Text($0.title).tag($0) }
                    }
                }
            }

            Section("Seçenekler") {
                if o.template.isLaravel || o.template == .custom {
                    Toggle("Frontend'i derle (npm install && build)", isOn: $o.npmBuild)
                }
                Toggle("Git deposu başlat", isOn: $o.gitInit)
                Toggle("HTTPS", isOn: $o.secure)
                Toggle("Docker dosyaları ekle (Dokploy)", isOn: $o.docker)
                Toggle("Bitince editörde aç", isOn: $o.openEditor)
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { create() } label: { Label("Oluştur", systemImage: "sparkles").labelStyle(.titleAndIcon) }
                    .primaryButton()
                    .disabled(!canCreate)
                    .keyboardShortcut(.defaultAction)
                    .help(canCreate ? "" : "Proje adı")
            }
        }
    }

    // MARK: Progress and result

    private func progress(_ job: Job) -> some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Group {
                        switch job.state {
                        case .success: NerdIcon(name: "checkmark.circle.fill", size: 34).foregroundStyle(.green)
                        case .failed: NerdIcon(name: "xmark.octagon.fill", size: 34).foregroundStyle(.red)
                        case .running: ProgressView().controlSize(.regular)
                        }
                    }
                    .frame(width: 40, height: 40)
                    Tile(systemName: o.template.icon, brand: o.template.brand, size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(headline(job)).font(.system(size: 15, weight: .semibold))
                        Text(currentLine(job)).font(.system(size: 11)).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
                if job.state == .success, let site = state.site(slug) {
                    LabeledContent("Adres") {
                        Button(state.url(for: site).absoluteString) { state.openSite(site) }.buttonStyle(.link)
                    }
                    HStack {
                        Button("Siteyi aç") { state.openSite(site) }.primaryButton()
                        Button("Editörde aç") { state.openInEditor(site.path) }
                        Button("Siteye git") { state.selectedSiteID = site.name; state.selection = .sites }
                        Spacer()
                        Button("Yeni proje") { reset() }
                    }
                } else if job.state == .failed {
                    HStack {
                        Spacer()
                        Button("Geri") { self.job = nil }
                    }
                }
            }
            Section {
                DisclosureGroup("Ayrıntılar", isExpanded: $showLog) {
                    LogText(text: job.output)
                        .frame(height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .formStyle(.grouped)
    }

    private func headline(_ job: Job) -> String {
        switch job.state {
        case .success: String(localized: "\(slug) hazır")
        case .failed: String(localized: "Kurulum başarısız")
        case .running: String(localized: "\(slug) oluşturuluyor…")
        }
    }

    private func currentLine(_ job: Job) -> String {
        job.output.split(separator: "\n").last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }).map(String.init) ?? ""
    }

    // MARK: Actions

    private func create() {
        guard canCreate else { return }
        showLog = false
        let options = o
        Task { _ = await state.createProject(options) }
        // createProject registers its job synchronously before its first await
        DispatchQueue.main.async { job = state.jobs.first }
    }

    private func reset() {
        let location = o.location
        o = NewProjectOptions()
        o.location = location
        group = .laravel
        job = nil
    }
}

/// A selectable template card: logo, name, one-line description.
private struct TemplateCard: View {
    let template: ProjectTemplate
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Tile(systemName: template.icon, brand: template.brand, size: 34)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(selected ? Color.brand : Color.secondary.opacity(0.35))
                }
                Text(template.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(template.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(hover || selected ? 0.06 : 0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Color.brand : Color.primary.opacity(0.08), lineWidth: selected ? 1.5 : 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
