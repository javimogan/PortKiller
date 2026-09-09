import Foundation

enum Shell {
    static func run(_ path: String, _ args: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

enum Scanner {

    // MARK: - Raw data

    /// `ps` for every process owned by the current user — root daemons can't be killed anyway.
    static func processes() -> [RawProc] {
        let uid = String(getuid())
        let out = Shell.run("/bin/ps", ["-Ao", "pid=,ppid=,uid=,pcpu=,rss=,command="])
        return out.split(separator: "\n").compactMap { line in
            var fields: [Substring] = []
            var rest = Substring(line)
            for _ in 0..<5 {
                rest = rest.drop(while: { $0 == " " })
                guard let sp = rest.firstIndex(of: " ") else { return nil }
                fields.append(rest[..<sp])
                rest = rest[sp...]
            }
            let command = String(rest.drop(while: { $0 == " " }))
            guard fields[2] == uid,
                  let pid = Int32(fields[0]), let ppid = Int32(fields[1]),
                  let cpu = Double(fields[3]), let rss = Double(fields[4]),
                  !command.isEmpty else { return nil }
            return RawProc(pid: pid, ppid: ppid, cpu: cpu, rssKB: rss, command: command)
        }
    }

    /// pid -> listening TCP ports.
    static func listeningPorts() -> [Int32: [Int]] {
        let out = Shell.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpn"])
        var result: [Int32: Set<Int>] = [:]
        var current: Int32?
        for line in out.split(separator: "\n") {
            switch line.first {
            case "p": current = Int32(line.dropFirst())
            case "n":
                guard let pid = current else { continue }
                let name = line.dropFirst()
                guard let colon = name.lastIndex(of: ":"),
                      let port = Int(name[name.index(after: colon)...]) else { continue }
                result[pid, default: []].insert(port)
            default: continue
            }
        }
        return result.mapValues { $0.sorted() }
    }

    /// Working directory of the given pids, in one `lsof` call.
    static func workingDirs(for pids: [Int32]) -> [Int32: String] {
        guard !pids.isEmpty else { return [:] }
        let out = Shell.run("/usr/sbin/lsof",
                            ["-a", "-d", "cwd", "-Fn", "-p", pids.map(String.init).joined(separator: ",")])
        var result: [Int32: String] = [:]
        var current: Int32?
        for line in out.split(separator: "\n") {
            switch line.first {
            case "p": current = Int32(line.dropFirst())
            case "n": if let pid = current { result[pid] = String(line.dropFirst()) }
            default: continue
            }
        }
        return result
    }

    // MARK: - Classification

    /// Processes we must never offer to kill in bulk: the editor, Claude, this app itself.
    private static let protectedPatterns = [
        "visual studio code.app", "/electron", "cursor.app", "windsurf.app",
        "claude-code", ".claude/local", "anthropic-ai/claude", "mcp-server", "mcp_server",
        "portkiller", "/applications/claude.app", "language_server", "languageserver",
        "copilot", "tsserver", "figma_agent"
    ]

    /// Long-running apps that happen to hold a port but are not dev servers.
    private static let notDevPatterns = [
        "/system/", "/usr/libexec/", "/usr/sbin/", "/applications/spotify",
        "google chrome", "safari", "firefox", "arc.app", "slack.app",
        "dropbox", "controlcenter", "rapportd", "sharingd", "airplay", "steam"
    ]

    /// (needle in command, label, SF Symbol). First match wins, so order matters.
    private static let rules: [(String, String, String)] = [
        ("next-server",       "Next.js",        "n.square.fill"),
        ("/next/dist",        "Next.js",        "n.square.fill"),
        ("next dev",          "Next.js",        "n.square.fill"),
        ("next start",        "Next.js",        "n.square.fill"),
        ("nuxt",              "Nuxt",           "leaf.fill"),
        ("astro",             "Astro",          "sparkles"),
        ("remix",             "Remix",          "r.square.fill"),
        ("react-router",      "React Router",   "r.square.fill"),
        ("gatsby",            "Gatsby",         "g.square.fill"),
        ("storybook",         "Storybook",      "book.fill"),
        ("vitest",            "Vitest",         "checkmark.seal.fill"),
        ("jest",              "Jest",           "checkmark.seal.fill"),
        ("playwright",        "Playwright",     "theatermasks.fill"),
        ("cypress",           "Cypress",        "theatermasks.fill"),
        ("vite",              "Vite",           "bolt.fill"),
        ("webpack",           "Webpack",        "shippingbox.fill"),
        ("rollup",            "Rollup",         "shippingbox.fill"),
        ("esbuild",           "esbuild",        "bolt.fill"),
        ("turbopack",         "Turbopack",      "bolt.fill"),
        ("turbo",             "Turborepo",      "bolt.fill"),
        ("nodemon",           "nodemon",        "arrow.triangle.2.circlepath"),
        ("tsc ",              "tsc --watch",    "arrow.triangle.2.circlepath"),
        ("tailwindcss",       "Tailwind",       "wind"),
        ("expo",             "Expo",            "iphone"),
        ("react-native",      "React Native",   "iphone"),
        ("metro",             "Metro",          "iphone"),
        ("wrangler",          "Wrangler",       "cloud.fill"),
        ("cloudflared",       "Cloudflare",     "cloud.fill"),
        ("ngrok",             "ngrok",          "cloud.fill"),
        ("firebase",          "Firebase",       "flame.fill"),
        ("supabase",          "Supabase",       "bolt.horizontal.fill"),
        ("sanity",            "Sanity",         "square.stack.3d.up.fill"),
        ("prisma",            "Prisma",         "cylinder.split.1x2.fill"),
        ("drizzle",           "Drizzle",        "cylinder.split.1x2.fill"),
        ("http-server",       "http-server",    "globe"),
        ("browser-sync",      "BrowserSync",    "globe"),
        ("http.server",       "Python http",    "globe"),
        ("uvicorn",           "Uvicorn",        "globe"),
        ("gunicorn",          "Gunicorn",       "globe"),
        ("manage.py runserver", "Django",       "globe"),
        ("flask",             "Flask",          "globe"),
        ("fastapi",           "FastAPI",        "globe"),
        ("rails",             "Rails",          "globe"),
        ("puma",              "Puma",           "globe"),
        ("jekyll",            "Jekyll",         "globe"),
        ("php -s",            "PHP server",     "globe"),
        ("artisan serve",     "Laravel",        "globe"),
        ("air ",              "air (Go)",       "arrow.triangle.2.circlepath"),
        ("cargo watch",       "cargo watch",    "arrow.triangle.2.circlepath"),
        ("postgres",          "Postgres",       "cylinder.fill"),
        ("mysqld",            "MySQL",          "cylinder.fill"),
        ("mongod",            "MongoDB",        "cylinder.fill"),
        ("redis-server",      "Redis",          "cylinder.fill"),
        ("com.docker",        "Docker",         "shippingbox.fill"),
        ("colima",            "Colima",         "shippingbox.fill"),
        ("ollama",            "Ollama",         "brain"),
        ("gradle",            "Gradle",         "hammer.fill"),
        ("npm run",           "npm",            "terminal.fill"),
        ("pnpm",              "pnpm",           "terminal.fill"),
        ("yarn",              "yarn",           "terminal.fill"),
        ("bun ",              "Bun",            "terminal.fill"),
        ("deno ",             "Deno",           "terminal.fill"),
        ("ts-node",           "ts-node",        "terminal.fill"),
        ("tsx ",              "tsx",            "terminal.fill"),
    ]

    /// Shells and wrappers repeat the whole command line in their own args, so they match dev
    /// patterns by accident. Never let one anchor a group.
    private static let shellNames: Set<String> = [
        "zsh", "bash", "sh", "dash", "fish", "csh", "tcsh",
        "login", "tmux", "screen", "ssh", "sudo", "env", "xargs"
    ]

    private static let runtimeNames: Set<String> = [
        "node", "bun", "deno", "ruby", "php", "java", "go", "cargo", "dotnet", "elixir", "erl"
    ]

    private static func isShell(_ command: String) -> Bool {
        shellNames.contains(exeName(command))
    }

    /// Index of the first matching rule — i.e. how specific the match is. Lower wins.
    private static func ruleIndex(_ command: String) -> Int? {
        let c = command.lowercased()
        if isShell(command) || notDevPatterns.contains(where: c.contains) { return nil }
        return rules.firstIndex { c.contains($0.0) }
    }

    private static func classify(_ command: String) -> (isDev: Bool, label: String, icon: String) {
        let c = command.lowercased()
        if isShell(command) { return (false, exeName(command), "terminal") }
        if notDevPatterns.contains(where: c.contains) { return (false, exeName(command), "app.dashed") }
        if let index = ruleIndex(command) {
            return (true, rules[index].1, rules[index].2)
        }
        // Bare runtimes still count as dev work even without a matching framework. Match on the
        // executable name, not a substring: "/go" would otherwise swallow "/Google Chrome".
        let exe = exeName(command).lowercased()
        if runtimeNames.contains(exe) || exe.hasPrefix("python") || exe.hasPrefix("node") {
            return (true, exeName(command), "terminal.fill")
        }
        return (false, exeName(command), "app.dashed")
    }

    private static func exeName(_ command: String) -> String {
        let exe = command.split(separator: " ").first.map(String.init) ?? command
        return (exe as NSString).lastPathComponent
    }

    private static func isProtected(_ command: String) -> Bool {
        let c = command.lowercased()
        return protectedPatterns.contains(where: c.contains)
    }

    /// The .app this pid runs from, if any, so the row can show the real system icon.
    /// Uses the real executable path rather than the command line: an argument may well mention
    /// some other bundle, and a helper nested inside an app resolves to the app you recognise.
    private static func appBundle(for pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(cString: buffer)
        guard let match = path.range(of: ".app/") else { return nil }
        let bundle = String(path[path.startIndex..<match.lowerBound]) + ".app"
        return FileManager.default.fileExists(atPath: bundle) ? bundle : nil
    }

    /// "Visual Studio Code" — better than the executable name, which is often a helper.
    private static func bundleName(_ bundle: String) -> String {
        (bundle as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
    }

    // MARK: - Grouping

    /// Build the list shown in the menu: dev trees first, then anything else holding a port.
    static func scan() -> [ProcGroup] {
        let rows = processes()
        let ports = listeningPorts()
        let byPid = Dictionary(uniqueKeysWithValues: rows.map { ($0.pid, $0) })
        var children: [Int32: [Int32]] = [:]
        for row in rows { children[row.ppid, default: []].append(row.pid) }

        let ownPid = ProcessInfo.processInfo.processIdentifier
        var ownAncestors: Set<Int32> = []
        var walk = ownPid
        while let row = byPid[walk], row.ppid > 1 { ownAncestors.insert(row.ppid); walk = row.ppid }

        // A process is interesting if it looks like a dev tool or is listening on a port.
        var interesting: Set<Int32> = []
        for row in rows where classify(row.command).isDev || ports[row.pid] != nil {
            interesting.insert(row.pid)
        }

        // Roll each interesting process up to its topmost interesting ancestor:
        // `npm run dev` -> `next-server` collapses into a single entry.
        func root(of pid: Int32) -> Int32 {
            var current = pid
            while let row = byPid[current], row.ppid > 1, interesting.contains(row.ppid) {
                current = row.ppid
            }
            return current
        }
        let roots = Set(interesting.map(root(of:)))

        func descendants(of pid: Int32) -> [Int32] {
            var out: [Int32] = []
            var stack = children[pid] ?? []
            while let next = stack.popLast() {
                out.append(next)
                stack.append(contentsOf: children[next] ?? [])
            }
            return out
        }

        var groups: [ProcGroup] = []
        for rootPid in roots {
            guard let row = byPid[rootPid] else { continue }
            let tree = [rootPid] + descendants(of: rootPid)
            let members = tree.compactMap { byPid[$0] }
            // `pnpm dev` spawns `next-server`: label the group by its most specific member. Only
            // for real dev roots — an editor's tree contains every framework its extensions touch.
            var info = classify(row.command)
            if info.isDev, let best = members
                .filter({ !isProtected($0.command) })
                .compactMap({ ruleIndex($0.command) })
                .min() {
                info = (true, rules[best].1, rules[best].2)
            }
            let protected = isProtected(row.command)
                || tree.contains(ownPid) || ownAncestors.contains(rootPid) || rootPid == ownPid

            // A plain app (Spotify, the editor) is better named and drawn by its bundle; a dev
            // tool launched from inside one (VS Code's terminal) keeps its own name and symbol.
            let bundle = appBundle(for: rootPid)
            if let bundle, !info.isDev {
                info.label = bundleName(bundle)
            }

            groups.append(ProcGroup(
                id: rootPid,
                label: info.label,
                icon: info.icon,
                appBundle: info.isDev ? nil : bundle,
                command: row.command,
                cwd: nil,
                ports: Array(Set(tree.flatMap { ports[$0] ?? [] })).sorted(),
                cpu: members.reduce(0) { $0 + $1.cpu },
                rssMB: members.reduce(0) { $0 + $1.rssKB } / 1024,
                pids: tree,
                isProtected: protected,
                isDev: info.isDev
            ))
        }

        // Only the roots need a cwd, so one lsof call covers the whole list.
        let dirs = workingDirs(for: groups.map(\.id))
        for index in groups.indices { groups[index].cwd = dirs[groups[index].id] }

        return groups.sorted {
            if $0.isDev != $1.isDev { return $0.isDev }
            if $0.cpu != $1.cpu { return $0.cpu > $1.cpu }
            return $0.label < $1.label
        }
    }

    // MARK: - Killing

    /// SIGTERM the whole tree (deepest first), then SIGKILL whatever is still alive.
    static func kill(pids: [Int32]) {
        let ordered = Array(pids.reversed())
        for pid in ordered { Darwin.kill(pid, SIGTERM) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.5) {
            for pid in ordered where Darwin.kill(pid, 0) == 0 {
                Darwin.kill(pid, SIGKILL)
            }
        }
    }
}
