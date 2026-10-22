# MacStats

A native, menu bar system monitor for macOS — built with SwiftUI and AppKit, no Electron, no third-party dependencies. See CPU, memory, disk, network, GPU, battery, temperature, and more at a glance, styled with macOS's native Liquid Glass material.

![platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![swift](https://img.shields.io/badge/swift-6.2-orange)
![license](https://img.shields.io/badge/license-MIT-green)

## Features

- **Live CPU load** — overall usage with a sparkline history, plus a per-core breakdown
- **Memory** — used / total, with live percentage
- **Disk** — free / used space on the boot volume, plus a list of other mounted volumes
- **Network** — live download/upload throughput
- **Disk I/O** — live read/write throughput
- **GPU utilization** — best-effort via `IOAccelerator` (works on most discrete/integrated GPUs)
- **Swap usage** — shown only when swap is active
- **CPU temperature** — via SMC on supported Macs ([see note](#apple-silicon-sensor-caveats))
- **Battery** — percentage, charging state, and time remaining
- **Wi-Fi** — SSID and signal strength (RSSI)
- **Bluetooth accessories** — battery level for connected devices (AirPods, Magic peripherals, etc.)
- **Top processes** — top 5 by CPU usage, with a one-click kill button
- **Uptime** and **display info** (resolution, refresh rate)
- **Mac model** — friendly marketing name where known, otherwise the raw hardware identifier
- **High CPU/RAM alerts** — local notification when usage is sustained above 90%
- **Launch at login** — toggle, backed by `SMAppService`
- **Adjustable refresh interval** — 1s / 2s / 5s / 10s, persisted across launches
- **Pause/resume monitoring** — stop polling without quitting
- **Global keyboard shortcut** — `Cmd+Shift+M` to toggle the panel (needs Input Monitoring permission)
- Panel stays open when you click into another app — closes only on an outside click, matching native menu bar apps

## Screenshots

_Add a screenshot or two here before publishing — `cmd+shift+4` and drop the PNG into a `docs/` folder, then reference it:_

```markdown
![MacStats panel](docs/screenshot.png)
```

## Requirements

- macOS 14 (Sonoma) or later to build and run; the native Liquid Glass material (`.glassEffect()`) additionally requires **macOS 26 (Tahoe)** or later to render — on older macOS versions the cards fall back to the system's standard translucent material.
- Xcode Command Line Tools or Xcode, with Swift 6.2+

## Building

MacStats is a plain Swift Package — no Xcode project required.

```bash
git clone git@github.com:Sienz16/MacStats.git
cd MacStats
swift run
```

This builds a debug binary and launches it directly. It runs fine for development, but **Launch at Login and local notifications require a real `.app` bundle** (macOS refuses to register a loose executable). Use the packaging script for that:

```bash
./build-app.sh
```

This builds a release binary, assembles `MacStats.app` with the correct `Info.plist`, and ad-hoc code-signs it. Then either:

```bash
open MacStats.app
```

or drag `MacStats.app` into `/Applications`.

## Project structure

```
Sources/MacStats/
├── App.swift              — @main entry point
├── AppDelegate.swift      — status item, floating panel, global hotkey/click monitors
├── SystemStats.swift      — all system data collection (Mach/IOKit/sysctl/libproc)
├── ContentView.swift      — SwiftUI panel UI
├── SMCReader.swift        — best-effort SMC temperature sensor reader
├── LoginItemManager.swift — SMAppService wrapper for Launch at Login
└── AlertManager.swift     — UNUserNotificationCenter wrapper for threshold alerts

Resources/
└── Info.plist             — bundle metadata used by build-app.sh

build-app.sh                — packages the release build into MacStats.app
```

All system data is read through public (if low-level) Apple APIs — Mach host statistics, IOKit, `sysctl`, and `libproc` — no private frameworks, no shelling out except for Bluetooth battery levels (see below).

## Apple Silicon sensor caveats

Two features are best-effort by nature, and will gracefully show nothing (not fake data) if unsupported on your Mac:

- **CPU temperature** — Intel Macs expose temperature through well-known, documented SMC keys (`TC0P`, etc.). Apple Silicon Macs use different, undocumented keys that vary by chip generation (M1/M2/M3/M4...) and aren't publicly specified. MacStats tries a handful of known candidate keys; if none resolve, the temperature badge simply doesn't appear.
- **GPU utilization** — read from the `IOAccelerator` registry's `PerformanceStatistics` dictionary, a technique used by several existing menu bar monitors. Reliable on most Macs, but not guaranteed across all configurations.

**Bluetooth battery levels** are read by shelling out to `system_profiler SPBluetoothDataType -json` — there's no stable public API for this, and it's the same approach most Bluetooth battery menu bar apps use. It only runs every 5th refresh tick since it's noticeably slower than the other readers.

## Permissions

- **Notifications** — requested on first launch of the packaged `.app`, for the high CPU/RAM alert feature.
- **Input Monitoring** — needed for the `Cmd+Shift+M` global shortcut to work. Grant it under System Settings → Privacy & Security → Input Monitoring if the shortcut doesn't respond.
- No network access, no data collection, nothing leaves your Mac.

## License

MIT
