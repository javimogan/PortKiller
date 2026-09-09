import SwiftUI
import ServiceManagement

@MainActor
final class AppState: ObservableObject {
    /// Shared so the menu bar popover and the dev window show the same live state.
    static let shared = AppState()

    @Published private(set) var groups: [ProcGroup] = []
    @Published private(set) var system = SystemUsage()
    @Published private(set) var isScanning = false
    @Published var showAll = UserDefaults.standard.bool(forKey: "showAll") {
        didSet { UserDefaults.standard.set(showAll, forKey: "showAll") }
    }

    private var timer: Timer?

    @Published var selection: Set<Int32> = []

    var visible: [ProcGroup] { showAll ? groups : groups.filter { $0.isDev && !$0.isProtected } }
    var totalCPU: Double { visible.reduce(0) { $0 + $1.cpu } }
    var totalRAM: Double { visible.reduce(0) { $0 + $1.rssMB } }
    var killable: [ProcGroup] { visible.filter { !$0.isProtected } }

    var selected: [ProcGroup] { visible.filter { selection.contains($0.id) } }
    var selectedCPU: Double { selected.reduce(0) { $0 + $1.cpu } }
    var selectedRAM: Double { selected.reduce(0) { $0 + $1.rssMB } }

    func toggleSelection(_ id: Int32) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    func killSelected() {
        let targets = selected
        for group in targets { Scanner.kill(pids: group.pids) }
        let ids = Set(targets.map(\.id))
        groups.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
        Task {
            try? await Task.sleep(for: .seconds(3))
            self.refresh()
        }
    }

    func refresh() {
        guard !isScanning else { return }
        isScanning = true
        Task {
            let snapshot = await Task.detached(priority: .userInitiated) {
                (groups: Scanner.scan(), system: SystemStats.sample())
            }.value
            self.groups = snapshot.groups
            self.system = snapshot.system
            // Drop anything that died or got filtered out, so the selection can't go stale.
            self.selection.formIntersection(Set(snapshot.groups.map(\.id)))
            self.isScanning = false
        }
    }

    /// Poll only while the popover is open — a background timer is exactly the battery drain
    /// this app exists to avoid.
    func startPolling() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func kill(_ group: ProcGroup) {
        Scanner.kill(pids: group.pids)
        groups.removeAll { $0.id == group.id }
        Task {
            try? await Task.sleep(for: .seconds(3))
            self.refresh()
        }
    }

    func killAll() {
        for group in killable { Scanner.kill(pids: group.pids) }
        let ids = Set(killable.map(\.id))
        groups.removeAll { ids.contains($0.id) }
        Task {
            try? await Task.sleep(for: .seconds(3))
            self.refresh()
        }
    }

    // MARK: - First run

    /// Asked once, on the first launch of an installed copy. It doubles as the only chance to
    /// tell a new user where the app actually went: a menu bar app with no Dock icon and no
    /// window is easy to install and never find.
    func offerLaunchAtLoginOnFirstRun() {
        let key = "didAskLaunchAtLogin"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: key),
              Bundle.main.bundleURL.pathExtension == "app",
              SMAppService.mainApp.status != .enabled else { return }
        defaults.set(true, forKey: key)

        let alert = NSAlert()
        alert.messageText = "Open PortKiller at login?"
        alert.informativeText = """
            PortKiller lives in the menu bar — look for the ⚡ icon at the top right of the \
            screen. Opening it at login keeps it there whenever you're working.

            You can change this any time in the ⚙️ menu.
            """
        alert.addButton(withTitle: "Open at Login")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            launchAtLogin = true
        }
    }

    // MARK: - Uninstall

    /// Removes the login item, forgets the stored preferences and puts the bundle in the Trash,
    /// which is recoverable — deleting outright would leave the user no way back.
    func uninstall() {
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app" else {
            // A bare `swift build` binary has no bundle to move; nothing to uninstall.
            NSSound.beep()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Move PortKiller to the Trash?"
        alert.informativeText = """
            PortKiller quits, stops opening at login, and its app goes to the Trash. \
            Nothing else on your Mac is touched, and you can put it back from the Trash.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        try? SMAppService.mainApp.unregister()
        if let identifier = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: identifier)
        }

        NSWorkspace.shared.recycle([bundle]) { _, error in
            DispatchQueue.main.async {
                if let error {
                    let failure = NSAlert(error: error)
                    failure.messageText = "Couldn't move PortKiller to the Trash"
                    failure.runModal()
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - Login item

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("PortKiller: login item toggle failed: \(error)")
            }
            objectWillChange.send()
        }
    }
}
