import SwiftUI

/// `PORTKILLER_DEV=1` opens a floating window with the same UI, so `./dev.sh` can rebuild and
/// relaunch without you having to click the menu bar item after every change.
let isDevMode = ProcessInfo.processInfo.environment["PORTKILLER_DEV"] == "1"

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var devWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard isDevMode else { return }

        NSApp.setActivationPolicy(.regular)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 560),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "PortKiller — dev"
        window.titlebarAppearsTransparent = true
        window.contentView = NSHostingView(rootView: MenuView().environmentObject(AppState.shared))
        window.level = .floating
        window.isReleasedWhenClosed = false
        // Keeps the window where you left it across the rebuild-relaunch cycle.
        window.setFrameAutosaveName("PortKillerDevWindow")
        // Screenshots want a canonical size and a title without the dev suffix; the everyday
        // dev window keeps whatever size you last dragged it to.
        if Demo.isEnabled {
            window.title = "PortKiller"
            window.setContentSize(NSSize(width: 420, height: 620))
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        devWindow = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct PortKillerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState.shared

    init() {
        // `PortKiller --list` prints what the menu would show. Handy for debugging detection.
        if CommandLine.arguments.contains("--list") {
            let system = SystemStats.sample()
            print(String(format: "system: cpu %.1f%%  ram %.0fMB (%.0f%%)",
                         system.cpuPercent, system.ramUsedMB, system.ramPercent))
            for group in Scanner.scan() {
                let ports = group.ports.map { ":\($0)" }.joined(separator: " ")
                print(String(format: "%@ %-16@ %-22@ cpu %5.1f%%  ram %6.0fMB  pids %d  %@ %@",
                             group.isDev ? "DEV " : "    ",
                             group.label,
                             group.project ?? "-",
                             group.cpu, group.rssMB, group.pids.count,
                             ports, [group.appBundle.map { "icon:\(($0 as NSString).lastPathComponent)" },
                                     group.isProtected ? "[protected]" : nil]
                                 .compactMap { $0 }.joined(separator: " ")))
            }
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(state)
        } label: {
            Image(systemName: "bolt.horizontal.circle")
        }
        .menuBarExtraStyle(.window)
    }
}
