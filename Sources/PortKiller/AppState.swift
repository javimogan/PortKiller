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
