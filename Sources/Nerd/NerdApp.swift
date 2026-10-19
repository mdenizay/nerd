import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var signalSources: [DispatchSourceSignal] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Opened from Finder, the Dock or Launchpad: show the window. Started at
        // login, or with --window / --page (which present it themselves): stay quiet.
        let event = NSAppleEventManager.shared().currentAppleEvent
        let atLogin = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        let presentsItself = CommandLine.arguments.contains { $0 == "--window" || $0 == "--debug" || $0 == "--panel" }
        MainActor.assumeIsolated { AppState.shared.showWindowOnLaunch = !atLogin && !presentsItself }
    }

    /// Clicking the app icon while Nerd only lives in the menu bar.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { AppState.shared.openMainWindow?() }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Quit cleanly (stopping caddy / php-fpm / vite) on SIGTERM & SIGINT too
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { NSApp.terminate(nil) }
            src.resume()
            signalSources.append(src)
        }
        Task { @MainActor in await AppState.shared.boot() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppState.shared.shutdown() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct NerdApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state = AppState.shared

    init() {
        // `nerd …` (~/.nerd/bin/nerd runs `Nerd --cli …`); `Nerd mcp` / `Nerd docker <dir>` still work directly
        let args = CommandLine.arguments
        if args.count >= 2, args[1] == "--cli" || CLI.commands.contains(args[1]) {
            let cliArgs = Array(args.dropFirst(args[1] == "--cli" ? 2 : 1))
            exit(MainActor.assumeIsolated { CLI.run(cliArgs) })
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(state)
        } label: {
            MenuBarLabel(state: state)
        }
        .menuBarExtraStyle(.window)

        Window("Nerd", id: "main") {
            MainView()
                .environment(state)
                .frame(minWidth: 820, minHeight: 520)
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(after: .windowArrangement) {
                OpenDebugButton()
            }
        }
        .defaultLaunchBehavior(CommandLine.arguments.contains("--window") ? .presented : .suppressed)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 980, height: 620)

        // Development: `--panel` shows the menu bar panel in a window, for screenshots.
        Window("Panel", id: "panel-preview") {
            MenuBarView().environment(state).background(.regularMaterial)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(CommandLine.arguments.contains("--panel") ? .presented : .suppressed)

        Window("Debug", id: "debug") {
            DebugView()
                .environment(state)
                .frame(minWidth: 820, minHeight: 480)
        }
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(width: 1040, height: 640)
        .defaultLaunchBehavior(CommandLine.arguments.contains("--debug") ? .presented : .suppressed)
    }
}

private struct OpenDebugButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Debug") { openWindow(id: "debug") }.keyboardShortcut("d", modifiers: [.command, .shift])
    }
}

/// The menu bar icon. It exists for the app's whole life, so it is also where
/// AppKit gets a way to open the main window (app icon clicks, launch).
private struct MenuBarLabel: View {
    let state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: state.webRunning ? "cube.fill" : "cube")
            .onAppear {
                state.openMainWindow = {
                    openWindow(id: "main")
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
                if state.showWindowOnLaunch {
                    state.showWindowOnLaunch = false
                    state.openMainWindow?()
                }
            }
    }
}
