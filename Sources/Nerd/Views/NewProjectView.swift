import SwiftUI

struct NewProjectView: View {
    @Environment(AppState.self) private var state
    @State private var o = NewProjectOptions()
    @State private var job: Job?

    private var running: Bool { job?.state == .running }

    var body: some View {
        HSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PageHeader(title: "Yeni Proje", subtitle: "Laravel starter kit veya herhangi bir composer paketiyle saniyeler içinde başlayın")
                    templates
                    form
                    HStack {
                        Spacer()
                        Button {
                            Task { job = await state.createProject(o) }
                            // Show the job immediately while it runs
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { job = state.jobs.first }
                        } label: {
                            Label("Projeyi oluştur", systemImage: "sparkles").padding(.horizontal, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(running || AppState.slug(o.name).isEmpty || (o.template == .custom && o.customPackage.isEmpty))
                    }
                }
                .padding(20)
            }
            .frame(minWidth: 520)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Çıktı").font(.headline)
                    Spacer()
                    if running { ProgressView().controlSize(.small) }
                    if let job, job.state == .success, let site = state.site(AppState.slug(o.name)) {
                        Button("Siteyi aç") { state.open(state.url(for: site)) }
                    }
                }
                LogText(text: job?.output ?? "Proje oluşturulduğunda kurulum çıktısı burada görünecek.")
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(12)
            .frame(minWidth: 320, idealWidth: 420)
        }
        .onAppear {
            if o.location.isEmpty { o.location = state.config.parkedPaths.first ?? Paths.home.path }
        }
    }

    private var templates: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
            ForEach(ProjectTemplate.allCases) { t in
                Button { o.template = t } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: t.icon).font(.title2)
                        Text(t.title).font(.headline)
                        Text(t.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(o.template == t ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(o.template == t ? Color.accentColor : .clear, lineWidth: 1.5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var form: some View {
        Form {
            Section {
                TextField("Proje adı", text: $o.name, prompt: Text("my-app"))
                if !o.name.isEmpty {
                    LabeledContent("Adres", value: "\(o.secure ? "https" : "http")://\(AppState.slug(o.name)).\(state.config.tld)")
                }
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
            Section {
                Picker("PHP", selection: $o.php) {
                    Text("Varsayılan (\(state.defaultPHP?.version ?? "—"))").tag(String?.none)
                    ForEach(state.installedPHP) { Text("PHP \($0.version)").tag(Optional($0.version)) }
                }
                Picker("Node", selection: $o.node) {
                    Text("Varsayılan (\(state.defaultNode?.version ?? "—"))").tag(String?.none)
                    ForEach(state.nodeVersions) { Text($0.label).tag(Optional($0.version)) }
                }
                if o.template != .plain {
                    Picker("Veritabanı", selection: $o.database) {
                        ForEach(DBDriver.allCases) { Text($0.title).tag($0) }
                    }
                }
            }
            Section {
                if o.template != .plain {
                    Toggle("npm install && npm run build", isOn: $o.npmBuild)
                }
                Toggle("Git deposu başlat", isOn: $o.gitInit)
                Toggle("HTTPS", isOn: $o.secure)
                Toggle("Bitince editörde aç (\(state.config.editor))", isOn: $o.openEditor)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(minHeight: 520)
    }
}
