import SwiftUI

/// Step-by-step project creation wizard.
struct NewProjectView: View {
    @Environment(AppState.self) private var state
    @State private var o = NewProjectOptions()
    @State private var step: Step = .type
    @State private var job: Job?
    @State private var showLog = false

    enum Step: Int, CaseIterable {
        case type, details, options, create
        var title: String {
            switch self {
            case .type: String(localized: "Tür")
            case .details: String(localized: "Ayrıntılar")
            case .options: String(localized: "Seçenekler")
            case .create: String(localized: "Kurulum")
            }
        }
    }

    private var slug: String { AppState.slug(o.name) }
    private var exists: Bool {
        !slug.isEmpty && FileManager.default.fileExists(atPath: URL(fileURLWithPath: o.location).appendingPathComponent(slug).path)
    }

    private var canContinue: Bool {
        switch step {
        case .type: true
        case .details: !slug.isEmpty && !exists && (o.template != .custom || !o.customPackage.isEmpty)
        case .options: true
        case .create: false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Group {
                    switch step {
                    case .type: typeStep
                    case .details: detailsStep
                    case .options: optionsStep
                    case .create: createStep
                    }
                }
                .frame(maxWidth: 500)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(maxWidth: .infinity)
            }
            Divider()
            footer.padding(.horizontal, 12).padding(.vertical, 8)
        }
        .toolbar {
            ToolbarItem(placement: .principal) { stepper }
        }
        .onAppear {
            if o.location.isEmpty { o.location = state.config.parkedPaths.first ?? Paths.home.path }
        }
    }

    // MARK: Chrome

    private var stepper: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.self) { s in
                let done = s.rawValue < step.rawValue
                HStack(spacing: 6) {
                    ZStack {
                        Circle().fill(s == step ? Color.brand : (done ? Color.brand.opacity(0.25) : Color.secondary.opacity(0.15)))
                        if done {
                            NerdIcon(name: "checkmark").font(.caption2.bold()).foregroundStyle(Color.brand)
                        } else {
                            Text("\(s.rawValue + 1)").font(.caption2.bold()).foregroundStyle(s == step ? .white : .secondary)
                        }
                    }
                    .frame(width: 18, height: 18)
                    Text(s.title).font(.system(size: 12)).foregroundStyle(s == step ? .primary : .secondary)
                }
                if s != Step.allCases.last {
                    Rectangle().fill(.separator).frame(width: 18, height: 1)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if step == .create {
                if job?.state != .running {
                    Button("Yeni proje") { reset() }
                }
                Spacer()
                if let job, job.state == .success, let site = state.site(slug) {
                    Button("Editörde aç") { state.openInEditor(site.path) }
                    Button("Siteyi aç") { state.openSite(site) }.primaryButton()
                } else if job?.state == .failed {
                    Button("Geri") { step = .options }
                }
            } else {
                if step != .type { Button("Geri") { step = Step(rawValue: step.rawValue - 1)! } }
                Spacer()
                if step == .options {
                    Button { create() } label: { Label("Oluştur", systemImage: "sparkles") }
                        .primaryButton()
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Devam") { step = Step(rawValue: step.rawValue + 1)! }
                        .primaryButton()
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canContinue)
                }
            }
        }
        .controlSize(.regular)
    }

    // MARK: Steps

    private var typeStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            StepTitle("Ne oluşturalım?", "Bir başlangıç şablonu seçin.")
            ForEach(ProjectTemplate.Group.allCases, id: \.self) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.5).foregroundStyle(.tertiary)
                    VStack(spacing: 0) {
                        let items = ProjectTemplate.allCases.filter { $0.group == group }
                        ForEach(items) { t in
                            templateRow(t)
                            if t != items.last { Divider().padding(.leading, 40) }
                        }
                    }
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator.opacity(0.5)))
                }
            }
        }
    }

    private func templateRow(_ t: ProjectTemplate) -> some View {
        Button { o.template = t } label: {
            HStack(spacing: 10) {
                Tile(systemName: t.icon, brand: t.brand, size: 20)
                Text(t.title).font(.system(size: 12.5, weight: .medium))
                Text(t.subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 6)
                Image(systemName: o.template == t ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(o.template == t ? Color.brand : Color.secondary.opacity(0.4))
            }
            .padding(.horizontal, 10).frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onTapGesture(count: 2) { o.template = t; step = .details }
    }

    private var detailsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            StepTitle("Proje adı", "\(o.template.title) projesi için bir ad ve konum.")
            VStack(alignment: .leading, spacing: 6) {
                TextField("my-app", text: $o.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .padding(8)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
                    .onSubmit { if canContinue { step = .options } }
                Group {
                    if exists {
                        Label("Bu klasör zaten var.", systemImage: "exclamationmark.circle").foregroundStyle(.red)
                    } else if !slug.isEmpty {
                        Label("\(o.secure ? "https" : "http")://\(slug).\(state.config.tld)", systemImage: "globe").foregroundStyle(.secondary)
                    } else {
                        Text(" ")
                    }
                }
                .font(.callout)
            }
            Form {
                Picker("Konum", selection: $o.location) {
                    ForEach(state.config.parkedPaths, id: \.self) { Text(($0 as NSString).abbreviatingWithTildeInPath).tag($0) }
                    if !state.config.parkedPaths.contains(o.location) && !o.location.isEmpty {
                        Text((o.location as NSString).abbreviatingWithTildeInPath).tag(o.location)
                    }
                }
                if o.template == .custom {
                    TextField("Composer paketi", text: $o.customPackage, prompt: Text("vendor/package"))
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .padding(.horizontal, -20)
        }
    }

    private var optionsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            StepTitle("Seçenekler", "Varsayılanlar çoğu proje için uygundur.")
            Form {
                Section {
                    if o.template.isDotnet {
                        Picker(".NET", selection: $o.dotnet) {
                            Text("Varsayılan (\(state.defaultDotnet?.major ?? "—"))").tag(String?.none)
                            ForEach(state.installedDotnet) { Text(verbatim: ".NET \($0.major)").tag(Optional($0.major)) }
                        }
                    }
                    if !o.template.isNode && !o.template.isDotnet {
                        Picker("PHP", selection: $o.php) {
                            Text("Varsayılan (\(state.defaultPHP?.version ?? "—"))").tag(String?.none)
                            ForEach(state.installedPHP) { Text("PHP \($0.version)").tag(Optional($0.version)) }
                        }
                    }
                    if !o.template.isDotnet {
                    Picker("Node", selection: $o.node) {
                        Text("Varsayılan (\(state.defaultNode?.version ?? "—"))").tag(String?.none)
                        ForEach(state.nodeVersions) { Text($0.label).tag(Optional($0.version)) }
                    }
                    }
                    if o.template.isLaravel || o.template == .custom {
                        Picker("Veritabanı", selection: $o.database) {
                            ForEach(DBDriver.allCases) { Text($0.title).tag($0) }
                        }
                    }
                }
                Section {
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
            .scrollDisabled(true)
            .padding(.horizontal, -20)
            summary
        }
    }

    private var summary: some View {
        HStack(spacing: 8) {
            Tile(systemName: o.template.icon, brand: o.template.brand, size: 18)
            Text("\(o.template.title) · \(slug.ifEmpty("—")) · \((o.location as NSString).abbreviatingWithTildeInPath)")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var createStep: some View {
        VStack(spacing: 16) {
            Group {
                switch job?.state {
                case .success:
                    NerdIcon(name: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed:
                    NerdIcon(name: "xmark.octagon.fill").foregroundStyle(.red)
                default:
                    ProgressView().controlSize(.large)
                }
            }
            .font(.system(size: 44))
            .frame(height: 50)

            VStack(spacing: 4) {
                Text(headline).font(.system(size: 15, weight: .semibold))
                Text(currentLine).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }

            if job?.state == .success, let site = state.site(slug) {
                Button(state.url(for: site).absoluteString) { state.openSite(site) }.buttonStyle(.link)
            }

            DisclosureGroup("Ayrıntılar", isExpanded: $showLog) {
                LogText(text: job?.output ?? "")
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 20)
    }

    private var headline: String {
        switch job?.state {
        case .success: String(localized: "\(slug) hazır")
        case .failed: String(localized: "Kurulum başarısız")
        default: String(localized: "\(slug) oluşturuluyor…")
        }
    }

    private var currentLine: String {
        guard let out = job?.output else { return "" }
        return out.split(separator: "\n").last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }).map(String.init) ?? ""
    }

    // MARK: Actions

    private func create() {
        step = .create
        showLog = false
        let options = o
        Task { job = await state.createProject(options) }
        // createProject registers its job synchronously before its first await
        DispatchQueue.main.async { job = state.jobs.first }
    }

    private func reset() {
        let location = o.location
        o = NewProjectOptions()
        o.location = location
        job = nil
        step = .type
    }
}

struct StepTitle: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    init(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey) { self.title = title; self.subtitle = subtitle }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(subtitle).foregroundStyle(.secondary)
        }
    }
}
