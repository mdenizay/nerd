import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var signalSources: [DispatchSourceSignal] = []

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
        let args = CommandLine.arguments
        if args.count >= 2, args[1] == "mcp" {
            MainActor.assumeIsolated { MCPServer.run() }
        }
        if args.count >= 3, args[1] == "docker" {
            exit(MainActor.assumeIsolated { AppState.shared.cliDocker(args[2]) })
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(state)
        } label: {
            Image(systemName: state.webRunning ? "cube.fill" : "cube")
        }
        .menuBarExtraStyle(.menu)

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
