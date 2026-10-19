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

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(state)
        } label: {
            Image(systemName: state.webRunning ? "cube.fill" : "cube")
        }
        .menuBarExtraStyle(.window)

        Window("Nerd", id: "main") {
            MainView()
                .environment(state)
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultLaunchBehavior(CommandLine.arguments.contains("--window") ? .presented : .suppressed)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1180, height: 760)
    }
}
