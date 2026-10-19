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
            case .type: "Tür"
            case .details: "Ayrıntılar"
            case .options: "Seçenekler"
            case .create: "Kurulum"
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
            stepper.padding(.vertical, 14)
            Divider()
            ScrollView {
                Group {
                    switch step {
                    case .type: typeStep
                    case .details: detailsStep
                    case .options: optionsStep
                    case .create: createStep
                    }
                }
                .frame(maxWidth: 560)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            Divider()
            footer.padding(12)
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
                        Circle().fill(s == step ? Color.accentColor : (done ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.15)))
                        if done {
                            Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(Color.accentColor)
                        } else {
                            Text("\(s.rawValue + 1)").font(.caption2.bold()).foregroundStyle(s == step ? .white : .secondary)
                        }
                    }
                    .frame(width: 18, height: 18)
                    Text(s.title).font(.callout).foregroundStyle(s == step ? .primary : .secondary)
                }
                if s != Step.allCases.last {
                    Rectangle().fill(.separator).frame(width: 28, height: 1)
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
                    Button("Siteyi aç") { state.openSite(site) }.buttonStyle(.borderedProminent)
                } else if job?.state == .failed {
                    Button("Geri") { step = .options }
                }
            } else {
                if step != .type { Button("Geri") { step = Step(rawValue: step.rawValue - 1)! } }
                Spacer()
                if step == .options {
                    Button { create() } label: { Label("Oluştur", systemImage: "sparkles") }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Devam") { step = Step(rawValue: step.rawValue + 1)! }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canContinue)
                }
            }
        }
        .controlSize(.large)
    }

    // MARK: Steps

    private var typeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepTitle("Ne oluşturalım?", "Bir başlangıç şablonu seçin.")
            ForEach(ProjectTemplate.Group.allCases, id: \.self) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.rawValue.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    VStack(spacing: 0) {
                        let items = ProjectTemplate.allCases.filter { $0.group == group }
                        ForEach(items) { t in
                            templateRow(t)
                            if t != items.last { Divider().padding(.leading, 50) }
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
            HStack(spacing: 12) {
                IconBadge(systemName: t.icon, color: t.color, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.title)
                    Text(t.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: o.template == t ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(o.template == t ? Color.accentColor : Color.secondary.opacity(0.4))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onTapGesture(count: 2) { o.template = t; step = .details }
    }

    private var detailsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepTitle("Proje adı", "\(o.template.title) projesi için bir ad ve konum.")
            VStack(alignment: .leading, spacing: 6) {
                TextField("my-app", text: $o.name)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .padding(10)
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
        VStack(alignment: .leading, spacing: 18) {
            StepTitle("Seçenekler", "Varsayılanlar çoğu proje için uygundur.")
            Form {
                Section {
                    if !o.template.isNode {
                        Picker("PHP", selection: $o.php) {
                            Text("Varsayılan (\(state.defaultPHP?.version ?? "—"))").tag(String?.none)
                            ForEach(state.installedPHP) { Text("PHP \($0.version)").tag(Optional($0.version)) }
                        }
                    }
                    Picker("Node", selection: $o.node) {
                        Text("Varsayılan (\(state.defaultNode?.version ?? "—"))").tag(String?.none)
                        ForEach(state.nodeVersions) { Text($0.label).tag(Optional($0.version)) }
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
            IconBadge(systemName: o.template.icon, color: o.template.color, size: 18)
            Text("\(o.template.title) · \(slug.ifEmpty("—")) · \((o.location as NSString).abbreviatingWithTildeInPath)")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var createStep: some View {
        VStack(spacing: 16) {
            Group {
                switch job?.state {
                case .success:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed:
                    Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                default:
                    ProgressView().controlSize(.large)
                }
            }
            .font(.system(size: 44))
            .frame(height: 50)

            VStack(spacing: 4) {
                Text(headline).font(.title3.bold())
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
        case .success: "\(slug) hazır"
        case .failed: "Kurulum başarısız"
        default: "\(slug) oluşturuluyor…"
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
    let title: String
    let subtitle: String
    init(_ title: String, _ subtitle: String) { self.title = title; self.subtitle = subtitle }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title2.bold())
            Text(subtitle).foregroundStyle(.secondary)
        }
    }
}
