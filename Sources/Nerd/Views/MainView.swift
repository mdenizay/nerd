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
                    ForEach([SidebarItem.php, .node, .services]) { row($0) }
                }
                Section("Araçlar") {
                    ForEach([SidebarItem.database, .mail, .jobs, .settings]) { row($0) }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            Group {
                switch state.selection ?? .dashboard {
                case .dashboard: DashboardView()
                case .sites: SitesView()
                case .newProject: NewProjectView()
                case .php: PHPView()
                case .node: NodeView()
                case .services: ServicesView()
                case .database: DatabaseView()
                case .mail: MailView()
                case .jobs: JobsView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }

    @ViewBuilder
    private func row(_ item: SidebarItem) -> some View {
        HStack {
            Label(item.title, systemImage: item.icon)
            Spacer()
            if item == .jobs, state.jobs.contains(where: { $0.state == .running }) {
                ProgressView().controlSize(.mini)
            }
            if item == .mail, state.unreadMailCount > 0 {
                Text("\(state.unreadMailCount)").font(.caption2.bold()).monospacedDigit()
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Color.accentColor, in: Capsule()).foregroundStyle(.white)
            }
        }
        .tag(item)
    }
}
