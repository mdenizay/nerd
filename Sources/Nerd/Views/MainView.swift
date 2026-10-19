import SwiftUI
import AppKit

/// Herd-style main window: a System Settings sidebar (status card on top,
/// coloured icon squares) and native grouped content with a native toolbar.
struct MainView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            List(selection: $state.selection) {
                StatusCard()
                    .padding(.vertical, 4)
                    .listRowSeparator(.hidden)
                    .selectionDisabled()
                Section {
                    ForEach([SidebarItem.dashboard, .sites, .newProject]) { row($0) }
                }
                Section("Ortam") {
                    ForEach([SidebarItem.php, .node, .dotnet, .services]) { row($0) }
                }
                Section("Araçlar") {
                    ForEach([SidebarItem.database, .mail, .jobs, .settings]) { row($0) }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            Group {
                switch state.selection ?? .dashboard {
                case .dashboard: DashboardView()
                case .sites: SitesView()
                case .newProject: NewProjectView()
                case .php: PHPView()
                case .node: NodeView()
                case .dotnet: DotnetView()
                case .services: ServicesView()
                case .database: DatabaseView()
                case .mail: MailView()
                case .jobs: JobsView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle((state.selection ?? .dashboard).title)
        }
        .tint(.brand)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
        .alert(state.confirmation?.title ?? "", isPresented: Binding(
            get: { state.confirmation != nil },
            set: { if !$0 { state.confirmation = nil } }
        ), presenting: state.confirmation) { request in
            Button(request.button, role: .destructive) { Task { await request.action() } }
            Button("Vazgeç", role: .cancel) {}
        } message: { request in
            Text(request.message)
        }
    }

    private func row(_ item: SidebarItem) -> some View {
        Label {
            HStack {
                Text(item.title)
                if item == .jobs, state.jobs.contains(where: { $0.state == .running }) {
                    Spacer()
                    ProgressView().controlSize(.mini)
                }
            }
        } icon: {
            SettingsIcon(name: item.icon, color: item.color)
        }
        .badge(item == .mail ? state.unreadMailCount : 0)
        .tag(item)
    }
}

/// System Settings style icon: a white glyph on a small coloured square.
struct SettingsIcon: View {
    let name: String
    let color: Color
    var size: CGFloat = 20

    var body: some View {
        NerdIcon(name: name, size: size * 0.6)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
    }
}

/// Top of the sidebar: the app, its state and the main switch.
private struct StatusCard: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Nerd").font(.system(size: 13, weight: .semibold))
                HStack(spacing: 5) {
                    StatusDot(on: state.webRunning)
                    Text(state.webRunning ? "Çalışıyor" : "Durdu")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize()
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(
                get: { state.webRunning },
                set: { on in Task { if on { await state.startWebServer() } else { state.stopWebServer() } } }))
                .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                .disabled(!state.caddyInstalled)
                .help(state.webRunning ? "Web sunucusunu durdur" : "Web sunucusunu başlat")
        }
    }
}
