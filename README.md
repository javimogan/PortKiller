# PortKiller

Menu bar app for macOS that lists the dev servers and processes running on your machine
and kills them in one click, so nothing keeps burning battery after you stop working.

![menu bar icon: ⚡ in a circle]

## What it shows

Each row is one **process tree**, not one process: `pnpm dev` and the `next-server` it spawned
collapse into a single "Next.js" entry, and killing it takes the children with it.

- Framework name (Next.js, Vite, Astro, Storybook, Postgres, Docker…) — detected from the command line
- Icon: the real macOS app icon when the process lives in a `.app` (Spotify, VS Code, Docker…),
  resolved from the executable path via `proc_pidpath`. Dev tools have no icon the system knows
  about, so they get an SF Symbol in their brand colour instead (`brandTints` in `MenuView.swift`)
- Project folder — the process's working directory
- Listening ports — click one to open `http://localhost:PORT`
- CPU % and RAM, summed across the whole tree
- `+N` = how many child processes go down with it

**Show all** adds everything else holding a port (Spotify, Control Center, VS Code…).
Protected entries — VS Code, Claude, MCP servers, PortKiller itself — are marked 🔒 and are
never included in **Kill all**, though you can still kill them one by one.

Only processes owned by your user are listed; root daemons can't be killed anyway.

## Interacting

| Action | What it does |
|---|---|
| Click a row | Selects it (click again to deselect). Click more rows to select several |
| The red button | `Kill all` with nothing selected, `Kill Next.js · 1.0 GB` once something is. Hover it for the CPU freed too |
| Chevron on the left | Expands the full command line |
| `×` on the right | Kills that one entry without selecting it |
| Port badge | Opens `http://localhost:PORT` |

## Install

```bash
./install.sh      # builds, copies to /Applications, launches
```

Then enable **Launch at login** in the ⚙️ menu.

To build without installing: `./build.sh` → `dist/PortKiller.app`.

## Live development

```bash
./dev.sh
```

Watches `Sources/` and `Package.swift`, rebuilds on save (~1s incremental) and relaunches.
In dev mode the app also opens a **floating window** with the same UI, so you see changes
without opening the menu every time; the window keeps its position across reloads. The menu bar
item still works as usual. `Ctrl+C` to quit.

For layout work alone: open `Package.swift` in Xcode and use the `#Preview` at the end of
`MenuView.swift` — the canvas updates without rebuilding the whole app.

When you like the change, `./install.sh` replaces the copy in `/Applications`.

## How killing works

`SIGTERM` to the whole tree, deepest child first. Anything still alive 2.5s later gets `SIGKILL`.

## Battery

The process list refreshes every 3s **only while the popover is open**. Closed, the app does
nothing — a background poller would be exactly the drain this app exists to remove.

## Debugging detection

```bash
.build/release/PortKiller --list
```

Prints what the menu would show. If a tool is mislabelled or missing, add a pattern to
`rules` in [Sources/PortKiller/Scanner.swift](Sources/PortKiller/Scanner.swift) — the list is
ordered by specificity, first match wins.

## Requirements

macOS 14+, Swift 6 toolchain (Xcode).
