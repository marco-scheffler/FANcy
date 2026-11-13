<div align="center">

<img src="assets/fancy-logo.svg" alt="FANcy" width="120" />

# FANcy

**Take control of your MacBook's fans.**

![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)
![Version](https://img.shields.io/badge/version-1.3.0-blue.svg)
![Platform](https://img.shields.io/badge/Platform-macOS%2013%2B-lightgrey.svg)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-required-black.svg)
![Built with](https://img.shields.io/badge/SwiftUI%20%C2%B7%20SMC-orange.svg)
[![CI](https://github.com/marco-scheffler/FANcy/actions/workflows/ci.yml/badge.svg)](https://github.com/marco-scheffler/FANcy/actions/workflows/ci.yml)

Manual control · interactive fan-curve editor · hysteresis — **a native macOS app that talks straight to the SMC.**

</div>

---

## Why FANcy?

Apple Silicon MacBooks keep their fans quiet by design — which is lovely until you're compiling,
gaming, or pushing a sustained load and the machine would rather thermal-throttle than spin up. macOS
gives you no dial for this.

FANcy is that dial. It's a **native SwiftUI app** that reads temperatures and writes fan speeds
directly through the System Management Controller, so you can nudge the fans manually, draw your own
temperature→speed curve, or hand control straight back to macOS whenever you like.

## Highlights

- 🎛️ **Manual control** — set each fan by RPM, or move every fan at once with the **All Fans** slider
- 📈 **Interactive fan curve** — drag points on a live temp→speed graph; FANcy interpolates the rest
- 🌡️ **Hysteresis** — a deadband around each threshold so fans don't hunt and oscillate
- 🖥️ **Lives in the menu bar** — no Dock clutter; live CPU temp in the menu bar with quick-action shortcuts (⌘0 Auto · ⌘1 Silent · ⌘2 Performance). Open the full window only when you need it.
- 🍎 **Native macOS feel** — SwiftUI, automatic light/dark mode, no Electron, no web view
- 🛟 **Crash guard** — if FANcy ever exits uncleanly, automatic fan control is restored on next launch
- 🔄 **Automatic updates** — checks daily via [Sparkle](https://sparkle-project.org); every download is EdDSA-signed and verified, and nothing installs without your click
- 🔒 **Local & minimal privilege** — SMC writes go through a tiny bundled helper; nothing leaves your Mac

## Requirements

- An **Apple Silicon MacBook with a fan** (the M-series MacBook **Pro**), running **macOS 13+**.
  The fanless **MacBook Air has no fan to control**, so FANcy has nothing to do there.
- **Admin rights** — writing fan speeds via the SMC needs a one-time privileged helper install
  (or run with `sudo` during development).

> Developed and tested on an Apple Silicon MacBook Pro. SMC fan keys can differ between models, so
> behaviour on a model I haven't tested isn't guaranteed — if something's off, please open an issue.

## Quick start

### Install (recommended)

Download **`FANcy-<version>.dmg`** from the [latest release](https://github.com/marco-scheffler/FANcy/releases/latest),
open it, and drag **FANcy** into **Applications**. The app is signed and **notarized by Apple**, so it
launches straight from a double-click — no Gatekeeper warnings, no `xattr` workaround needed.

On first launch, open the **HELPER** section and click **Install**, then enable **FANcy** under
**System Settings → General → Login Items & Extensions**. That one-time approval starts the small
privileged helper FANcy uses to write fan speeds — registered the modern way via `SMAppService`, so
it stays versioned with the app.

From 1.3.0 on, FANcy keeps itself up to date: it checks once a day and offers new versions in-app
(or use **Check for Updates…** in the menu bar). Coming from an older version? Install 1.3.0 once
from the DMG.

### Build from source

```bash
cd native
./build.sh
open build/FANcy.app
```

To produce a signed, notarized DMG yourself, see [`native/package.sh`](native/package.sh).

### Python prototype

The original Flet prototype still lives in the repo root if you'd rather run it from source:

```bash
make                         # compiles the smc_helper binary
pip install -r requirements.txt
python3 app.py               # writes need sudo
```

## Usage

- **Automatic** — the default; macOS owns the fans. FANcy always restores this on quit or crash.
- **Manual** — pick a fan (or **All Fans**) and set the target RPM directly.
- **Fan curve** — drag the points on the graph to shape a temperature→speed response, then activate it;
  FANcy samples the CPU temperature and drives the fans along your curve with hysteresis.

## How it works

A small C bridge (`SMCBridge.c` / `smc_helper.c`) reads and writes SMC keys through **IOKit** — fan
RPM, targets, and temperature sensors. Fan **writes** are privileged, so the native app ships a
minimal helper (`FANcyHelper`), registered as a root LaunchDaemon via **`SMAppService`** (macOS's
modern login-items mechanism), that performs them; the Python prototype uses `sudo` instead. On exit —
clean or not — FANcy hands the fans back to macOS's automatic control, and a crash-guard file lets it
recover if the app was killed mid-session.

## Project layout

| Path | What it is |
|---|---|
| `native/` | The shipping **SwiftUI app** — `build.sh` produces `FANcy.app` |
| `native/Core/` | Pure logic (fan curve, profiles, deadband, strings) — built into the app and unit-tested |
| `native/Sources/` | App, views, fan-curve editor, SMC kit, helper installer, Sparkle updater |
| `Package.swift` · `Tests/` | Swift package wrapping `native/Core` for `swift test` |
| `native/package.sh` | Release pipeline: sign, notarize, DMG, Sparkle signature + `appcast.xml` entry |
| `appcast.xml` · `docs/release-notes/` | The update feed installed copies read, and the notes shown in it |
| `app.py` · `smc_helper.c` | The original **Python/Flet** prototype and its SMC helper |
| `fan_curve.json` | Saved curve (regenerated from the built-in default if missing) |

## Config

The fan curve is stored as a list of `[temperature, speed%]` points. FANcy manages it from the UI, but
you can edit it by hand too — if the file is missing, it falls back to the built-in `DEFAULT_CURVE`.

## Tests

```bash
swift test
```

Covers the fan-curve math (interpolation, RPM mapping, the deadband that stops fans from hunting),
the saved-curve format, and the built-in profiles — including that every profile is monotonic and
that Silent → Balanced → Performance → Gaming really get louder at every temperature — plus the
update setup (feed URL, signing key, a well-formed and correctly ordered `appcast.xml`), where a
mistake wouldn't crash anything but would silently stop every installed copy from updating. CI runs
the tests and a full app build on every push.

## Safety & limitations

⚠️ **Use at your own risk.** FANcy overrides the SMC's automatic fan control, so running the fans too
slow under sustained load lets your Mac get warmer. A few things keep that in check:

- macOS keeps its own **thermal protection** — it throttles (and ultimately shuts down) regardless of
  what FANcy requests, so you can't cook the machine by setting fans low.
- The curve uses **hysteresis** so fans don't oscillate around a threshold.
- FANcy **always restores automatic control on quit** — and a crash-guard restores it on next launch
  if the app ever exits uncleanly.

Known limitations:

- An update replaces the app right away, but the root **helper keeps running its old binary until the
  next restart** — fine as long as the helper's protocol doesn't change between versions.
- Only the **native app** is maintained for day-to-day use; `app.py` is the original prototype.

## License

MIT — see [`LICENSE`](LICENSE).

<div align="center">

Made for Apple Silicon MacBooks that deserve a fan dial.

</div>
