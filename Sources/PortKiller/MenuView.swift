import SwiftUI

struct MenuView: View {
    @EnvironmentObject var state: AppState
    @State private var confirmKillAll = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 420)
        .animation(.easeOut(duration: 0.15), value: state.selection)
        // Opening the panel hands keyboard focus to the first focusable control, which then wears
        // the accent-coloured focus ring as if it were selected. Nobody tabs through a menu bar
        // popover, so drop the ring rather than let it sit on the refresh button.
        .focusEffectDisabled()
        .onAppear { state.startPolling() }
        .onDisappear { state.stopPolling() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("Running processes")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            // The whole machine, not just the rows below: that is what drains the battery.
            Chip(text: String(format: "%.0f%% CPU", state.system.cpuPercent),
                 tint: cpuTint(state.system.cpuPercent))
                .help(String(format: "System-wide CPU. Listed here: %.0f%%", state.totalCPU))
            Chip(text: memoryText(state.system.ramUsedMB), tint: .secondary)
                .help(String(format: "Memory in use system-wide. Listed here: %@",
                             memoryText(state.totalRAM)))
            Button(action: state.refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .pointerCursor()
            .help("Refresh")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - List

    @ViewBuilder
    private var content: some View {
        if state.visible.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.tertiary)
                Text("Nothing running")
                    .font(.system(size: 12, weight: .medium))
                Text("Your battery thanks you")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 34)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(state.visible) { group in
                        ProcessRow(group: group)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 480)
        }
    }

    // MARK: - Footer

    /// The same button either way — only the wording changes with the selection.
    private var killTitle: String {
        let selected = state.selected
        guard !selected.isEmpty else { return confirmKillAll ? "Sure?" : "Kill all" }
        let what = selected.count == 1 ? (selected[0].label) : "\(selected.count) processes"
        return "Kill \(what) · \(memorySize(state.selectedRAM))"
    }

    private var killHelp: String {
        guard !state.selection.isEmpty else { return "Kill everything listed, except protected entries" }
        let cpu = state.selectedCPU
        let cpuPart = cpu >= 0.5 ? String(format: ", %.0f%% CPU", cpu) : ""
        return "Frees \(memoryText(state.selectedRAM))\(cpuPart)"
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Toggle("Show all", isOn: $state.showAll)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .pointerCursor()
                .help("Includes system and editor processes that merely hold a port")

            Spacer()

            if !state.killable.isEmpty || !state.selection.isEmpty {
                Button(killTitle) {
                    // An explicit selection needs no confirmation; wiping the whole list does.
                    if !state.selection.isEmpty {
                        state.killSelected()
                    } else if confirmKillAll {
                        state.killAll()
                        confirmKillAll = false
                    } else {
                        confirmKillAll = true
                        Task {
                            try? await Task.sleep(for: .seconds(3))
                            confirmKillAll = false
                        }
                    }
                }
                .controlSize(.small)
                .tint(.red)
                .buttonStyle(.borderedProminent)
                .pointerCursor()
                .help(killHelp)
            }

            Menu {
                Toggle("Launch at login", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.launchAtLogin = $0 }
                ))
                Divider()
                Button("Quit PortKiller") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .pointerCursor()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

// MARK: - Row

struct ProcessRow: View {
    let group: ProcGroup
    @EnvironmentObject var state: AppState
    @State private var hovering = false
    @State private var expanded = false

    private var isSelected: Bool { state.selection.contains(group.id) }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.16) }
        return hovering ? Color.primary.opacity(0.06) : .clear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                // Disclosure arrow on the left, where macOS puts it, so it reads as "expand"
                // and not as an action competing with the kill button on the right.
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .help(expanded ? "Hide command" : "Show command")

                GroupIcon(group: group)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(group.label)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        if let project = group.project {
                            Text(project)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if group.isProtected {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                                .help("Protected: your editor, Claude, or PortKiller itself")
                        }
                    }
                    HStack(spacing: 4) {
                        ForEach(group.ports, id: \.self) { port in
                            PortBadge(port: port)
                        }
                        Text(String(format: "%.0f%%", group.cpu))
                            .foregroundStyle(cpuTint(group.cpu))
                        Text(memoryText(group.rssMB))
                            .foregroundStyle(.secondary)
                        if group.childCount > 0 {
                            Text("+\(group.childCount)")
                                .foregroundStyle(.tertiary)
                                .help("\(group.childCount) child processes, killed along with it")
                        }
                    }
                    .font(.system(size: 10, design: .rounded))
                }

                Spacer(minLength: 4)

                Button {
                    state.kill(group)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(hovering ? Color.red : Color.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .help("Kill \(group.label) (PID \(group.id))")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            if expanded {
                Text(group.command)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(4)
                    .padding(.leading, 50)
                    .padding(.trailing, 10)
                    .padding(.bottom, 7)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.55) : .clear, lineWidth: 1)
        )
        // Without an explicit shape the empty space and the Spacer aren't hit-tested, so hover
        // only fires over the text itself.
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onHover { hovering = $0 }
        .pointerCursor()
        .onTapGesture { state.toggleSelection(group.id) }
    }
}

/// Pointing-hand cursor over anything clickable.
///
/// An `onHover` that pushes and pops `NSCursor` loses track whenever the view is rebuilt — and
/// this list rebuilds every 3 seconds, so the cursor kept snapping back to an arrow mid-hover.
/// A cursor rect is owned by AppKit instead: it survives redraws and needs no push/pop balance.
private struct PointerCursorOverlay: NSViewRepresentable {
    final class CursorView: NSView {
        override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
        // Invisible to clicks, so the SwiftUI view underneath still receives them.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> NSView { CursorView() }

    func updateNSView(_ view: NSView, context: Context) {
        view.window?.invalidateCursorRects(for: view)
    }
}

extension View {
    func pointerCursor() -> some View { overlay(PointerCursorOverlay()) }
}

/// Real macOS icon for anything that lives in a .app; a brand-tinted symbol for dev tools,
/// which have no icon the system knows about.
struct GroupIcon: View {
    let group: ProcGroup

    var body: some View {
        if let bundle = group.appBundle {
            Image(nsImage: IconCache.icon(for: bundle))
                .resizable()
                .interpolation(.high)
                .frame(width: 18, height: 18)
                .frame(width: 22, height: 22)
        } else {
            let tint = brandTint(group.label)
            Image(systemName: group.icon)
                .font(.system(size: 12))
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(tint)
        }
    }
}

/// `NSWorkspace.icon(forFile:)` hits the disk, and the list redraws every 3 seconds.
@MainActor
enum IconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for path: String) -> NSImage {
        if let cached = cache[path] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache[path] = icon
        return icon
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Brand colours, adjusted where the real one would vanish against one of the two themes.
private let brandTints: [String: Color] = [
    "Next.js": .primary, "Deno": .primary, "Ollama": .primary,
    "Vite": Color(hex: 0x646CFF), "Turbopack": Color(hex: 0x646CFF),
    "Nuxt": Color(hex: 0x00DC82), "Astro": Color(hex: 0xFF5D01),
    "Remix": Color(hex: 0x3992FF), "React Router": Color(hex: 0x3992FF),
    "Gatsby": Color(hex: 0x9D7CBF), "Storybook": Color(hex: 0xFF4785),
    "Vitest": Color(hex: 0xFCC72B), "Jest": Color(hex: 0xC63D14),
    "Playwright": Color(hex: 0x2EAD33), "Cypress": Color(hex: 0x00C689),
    "Webpack": Color(hex: 0x4A90D9), "Rollup": Color(hex: 0xEC4A3F),
    "esbuild": Color(hex: 0xFFCF00), "Turborepo": Color(hex: 0xEF4444),
    "Tailwind": Color(hex: 0x38BDF8), "nodemon": Color(hex: 0x76D04B),
    "tsc --watch": Color(hex: 0x3178C6), "ts-node": Color(hex: 0x3178C6),
    "tsx": Color(hex: 0x3178C6), "Expo": Color(hex: 0x4630EB),
    "React Native": Color(hex: 0x61DAFB), "Metro": Color(hex: 0x61DAFB),
    "Wrangler": Color(hex: 0xF38020), "Cloudflare": Color(hex: 0xF38020),
    "ngrok": Color(hex: 0x5C6AC4), "Firebase": Color(hex: 0xFFA000),
    "Supabase": Color(hex: 0x3ECF8E), "Sanity": Color(hex: 0xF03E2F),
    "Prisma": Color(hex: 0x5A67D8), "Drizzle": Color(hex: 0xC5F74F),
    "Postgres": Color(hex: 0x4A87BE), "MySQL": Color(hex: 0xE48E00),
    "MongoDB": Color(hex: 0x47A248), "Redis": Color(hex: 0xDC382D),
    "Docker": Color(hex: 0x2496ED), "Colima": Color(hex: 0x2496ED),
    "Django": Color(hex: 0x0C9D58), "Flask": Color(hex: 0x30A3A3),
    "FastAPI": Color(hex: 0x05998B), "Uvicorn": Color(hex: 0x05998B),
    "Gunicorn": Color(hex: 0x298F44), "Python http": Color(hex: 0x4B8BBE),
    "Rails": Color(hex: 0xCC0000), "Puma": Color(hex: 0xCC0000),
    "Jekyll": Color(hex: 0xCC0000), "Laravel": Color(hex: 0xFF2D20),
    "PHP server": Color(hex: 0x7A86B8), "Gradle": Color(hex: 0x02303A),
    "npm": Color(hex: 0xCB3837), "pnpm": Color(hex: 0xF9AD00),
    "yarn": Color(hex: 0x2C8EBB), "Bun": Color(hex: 0xF472B6),
    "air (Go)": Color(hex: 0x00ADD8), "cargo watch": Color(hex: 0xDEA584),
]

func brandTint(_ label: String) -> Color { brandTints[label] ?? .accentColor }

struct PortBadge: View {
    let port: Int

    var body: some View {
        Button {
            if let url = URL(string: "http://localhost:\(port)") { NSWorkspace.shared.open(url) }
        } label: {
            Text(":\(port)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.accentColor.opacity(0.15), in: Capsule())
                .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help("Open http://localhost:\(port)")
    }
}

struct Chip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12), in: Capsule())
            .foregroundStyle(tint)
    }
}

func cpuTint(_ cpu: Double) -> Color {
    switch cpu {
    case ..<15: return .secondary
    case ..<60: return .orange
    default: return .red
    }
}

/// Total physical RAM, so memory can be shown as a share of the machine and not just a number.
let physicalMemoryMB = Double(ProcessInfo.processInfo.physicalMemory) / 1024 / 1024

func memorySize(_ mb: Double) -> String {
    mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb)
}

func memoryText(_ mb: Double) -> String {
    let size = memorySize(mb)
    let share = mb / physicalMemoryMB * 100
    let percent = share < 1 ? String(format: "%.1f%%", share) : String(format: "%.0f%%", share)
    return "\(size) · \(percent)"
}

// Xcode canvas: open Package.swift in Xcode for instant visual iteration on the layout.
#Preview {
    MenuView().environmentObject(AppState.shared)
}
