import Foundation

/// `PORTKILLER_DEMO=1` swaps the real scan for a fixed, good-looking list. It exists so the
/// README screenshot shows a believable workday instead of whatever happens to run on the
/// machine taking it — and so nobody's real processes end up in a public image.
enum Demo {
    static let isEnabled = ProcessInfo.processInfo.environment["PORTKILLER_DEMO"] == "1"

    static let system = SystemUsage(cpuPercent: 47, ramUsedMB: 19_250, ramPercent: 59)

    static let groups: [ProcGroup] = [
        group(pid: 90_001, label: "Next.js", icon: "n.square.fill", project: "acme-storefront",
              ports: [3000], cpu: 34.2, ram: 1_180, children: 4,
              command: "node /Users/you/Code/acme-storefront/node_modules/.bin/next dev --turbo"),
        group(pid: 90_002, label: "Vite", icon: "bolt.fill", project: "acme-design-system",
              ports: [5173], cpu: 12.6, ram: 618, children: 2,
              command: "node /Users/you/Code/acme-design-system/node_modules/.bin/vite --host"),
        group(pid: 90_003, label: "Storybook", icon: "book.fill", project: "acme-design-system",
              ports: [6006], cpu: 4.1, ram: 402, children: 1,
              command: "node /Users/you/Code/acme-design-system/node_modules/.bin/storybook dev -p 6006"),
        group(pid: 90_004, label: "Supabase", icon: "bolt.horizontal.fill", project: "acme-storefront",
              ports: [54321, 54322], cpu: 2.3, ram: 286, children: 3,
              command: "supabase start --workdir /Users/you/Code/acme-storefront"),
        group(pid: 90_005, label: "tsc --watch", icon: "arrow.triangle.2.circlepath", project: "acme-storefront",
              ports: [], cpu: 1.4, ram: 142, children: 0,
              command: "node /Users/you/Code/acme-storefront/node_modules/.bin/tsc --watch --noEmit"),
        group(pid: 90_006, label: "Postgres", icon: "cylinder.fill", project: nil,
              ports: [5432], cpu: 0.8, ram: 190, children: 0,
              command: "/opt/homebrew/opt/postgresql@16/bin/postgres -D /opt/homebrew/var/postgresql@16"),
    ]

    private static func group(pid: Int32, label: String, icon: String, project: String?,
                              ports: [Int], cpu: Double, ram: Double, children: Int,
                              command: String) -> ProcGroup {
        ProcGroup(
            id: pid,
            label: label,
            icon: icon,
            appBundle: nil,
            command: command,
            cwd: project.map { "/Users/you/Code/\($0)" },
            ports: ports,
            cpu: cpu,
            rssMB: ram,
            pids: Array(pid...(pid + Int32(children))),
            isProtected: false,
            isDev: true
        )
    }
}
