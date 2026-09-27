<p align="center">
  <img src="docs/icon.png" alt="PortShow icon" width="256">
</p>

# PortShow

A macOS menu bar app that shows every port in use on your Mac, which app or service owns it, and lets you open, reveal, or kill it in one click.

<img src="docs/screenshot.png" alt="PortShow popover" width="340">

## Features

- **Menu bar popover** listing listening TCP ports and bound UDP ports, refreshed every 3 seconds by default (adjustable in Settings). Outgoing connections (such as a browser's HTTP/3 traffic over UDP) are left out, since nothing is listening on them.
- **Grouped automatically** by where the owning program lives:
  - **Pinned**: ports you've starred, always at the top.
  - **Apps**: ports opened by desktop apps (anything inside a `.app` bundle).
  - **Services**: things you run yourself, such as dev servers, Homebrew databases and scripts.
  - **System**: macOS daemons and app-managed helpers (under `/System`, `/usr`, `~/Library`, …). Hidden unless **System ports** is ticked.
- **Meaningful names** for scripts. A Python/Node/Java process is named after its project folder and what it runs, e.g. `audio-log (uvicorn)` instead of `Python`.
- **Hover a row** for quick actions (left to right):

  <img src="docs/hover-actions.png" alt="Hover actions on a row" width="340">

  - Open `http://host:port` in your browser
  - Copy the port, process and PID
  - Show the start script in Finder (e.g. `app/main.py` for `uvicorn app.main:app`, or the program itself for native binaries)
  - Kill the process (SIGTERM)
- **Right-click a row** for the full menu: Open in Browser, Copy Port, Copy PID, Reveal in Finder, Pin/Unpin, Kill Process.
- **Search** by port, name, PID, or address.
- **Launch at Login** checkbox (installs a per-user LaunchAgent).
- **Settings menu** (gear icon, top right), all remembered between launches:
  - **Refresh Every**: 2, 3 (default), 5, 10 or 30 seconds. Slower uses less CPU.
  - **Show UDP Ports**: hide UDP to keep the list to servers you can connect to.
  - **Notify When Pinned Ports Go Up/Down**: a macOS notification when a pinned port starts or stops.
  - About PortShow, View on GitHub, Quit.

## Requirements

- macOS 13 Ventura or later
- Apple Silicon (the build currently targets `arm64` only)
- Xcode Command Line Tools to build (`xcode-select --install`). Full Xcode isn't needed.

## Build

```sh
./build.sh
```

This compiles the sources with `swiftc`, assembles and ad-hoc signs `build/PortShow.app`, and packages `build/PortShow.dmg`.

## Install

1. Open `build/PortShow.dmg` and drag **PortShow** into **Applications**.
2. The app isn't notarized, so the first time you open it, right-click it in Applications, choose **Open**, then confirm.
3. Look for the `:_` icon in the menu bar.

## Resource usage

Measured over 60 seconds on an Apple Silicon Mac with about 25 ports open, at the default 3-second refresh:

| | |
|---|---|
| Memory | ~34 MB (the figure Activity Monitor shows; stays flat over time) |
| CPU, app | ~1.4% of one core on average |
| CPU, port scan | ~0.05 s of CPU every 3 s for the two `lsof` calls, roughly another 1.7% |
| Threads | 7 |
| App size | 744 KB (`.app`), 988 KB (`.dmg`) |

Most of the CPU goes to the port scan that runs every 3 seconds; choosing a longer interval under **Refresh Every** reduces it proportionally. Tools like `ps` report ~150 MB of memory, but that includes macOS system libraries shared with every other app.

## Limitations

- Ports are read with `lsof` as your user, so sockets owned by root-only daemons may not appear, and **Kill** can't stop processes owned by other users.
- Grouping is a heuristic based on the executable's location; pin anything that lands in the wrong section.

## Project layout

| Path | Purpose |
|---|---|
| `Sources/main.swift` | App delegate, menu bar item and popover |
| `Sources/PopoverViewController.swift` | Popover UI: header, search, sections, footer |
| `Sources/PortRowView.swift` | A single port row, hover actions and context menu |
| `Sources/PortScanner.swift` | `lsof` parsing, naming, categorisation, start-file lookup, kill |
| `Sources/AppState.swift` | Refresh loop, search, sections, settings |
| `Sources/FavoritesStore.swift` | Pinned ports (UserDefaults) |
| `Sources/LoginItemManager.swift` | Launch-at-login LaunchAgent |
| `Sources/NotificationManager.swift` | Pinned port up/down notifications |
| `build.sh`, `make_icon.sh` | Build, icon generation, DMG packaging |
