import SwiftUI
import AppKit

struct MainView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            List(selection: $state.selection) {
                Section("Nerd") {
                    ForEach([SidebarItem.dashboard, .sites, .newProject]) { row($0) }
                }
                Section("Ortam") {
                    ForEach([SidebarItem.php, .node, .dotnet, .services]) { row($0) }
                }
                Section("Araçlar") {
                    ForEach([SidebarItem.database, .mail, .jobs, .settings]) { row($0) }
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
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
            .background(Backdrop())
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

    @ViewBuilder
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
            Image(systemName: item.icon)
        }
        .badge(item == .mail ? state.unreadMailCount : 0)
        .tag(item)
    }
}
