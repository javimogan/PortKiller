import Foundation

/// One row of `ps` output.
struct RawProc {
    let pid: Int32
    let ppid: Int32
    let cpu: Double
    let rssKB: Double
    let command: String
}

/// A dev server / task shown in the menu: one root process plus every descendant it spawned.
struct ProcGroup: Identifiable, Equatable {
    let id: Int32          // root pid
    var label: String      // "Next.js", "Vite", "Postgres"…
    var icon: String       // SF Symbol, used when there is no app bundle
    var appBundle: String? // path to the owning .app, so we can show its real icon
    var command: String    // full command line of the root
    var cwd: String?       // working directory of the root
    var ports: [Int]
    var cpu: Double        // % summed over the whole tree
    var rssMB: Double      // resident memory summed over the whole tree
    var pids: [Int32]      // root first, then descendants
    var isProtected: Bool  // VS Code / Claude / this app: never in "kill all"
    var isDev: Bool        // matched a dev-tool pattern (vs. just holding a port)

    var project: String? {
        guard let cwd, cwd != NSHomeDirectory(), cwd != "/" else { return nil }
        return (cwd as NSString).lastPathComponent
    }
    var childCount: Int { max(0, pids.count - 1) }
}
