<div align="center">

<img src="assets/fancy-logo.svg" alt="FANcy" width="120" />

# FANcy

**Take control of your MacBook's fans.**

![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)
![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)
![Platform](https://img.shields.io/badge/Platform-macOS%2013%2B-lightgrey.svg)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-required-black.svg)
![Built with](https://img.shields.io/badge/SwiftUI%20%C2%B7%20SMC-orange.svg)

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
- 🖥️ **Menu bar extra** — live CPU temp at a glance, with quick auto / curve / quit actions
- 🍎 **Native macOS feel** — SwiftUI, automatic light/dark mode, no Electron, no web view
- 🛟 **Crash guard** — if FANcy ever exits uncleanly, automatic fan control is restored on next launch
- 🔄 **Self-updating** — built-in Sparkle updater keeps you on the latest build
- 🔒 **Local & minimal privilege** — SMC writes go through a tiny bundled helper; nothing leaves your Mac

## Requirements

- An **Apple Silicon** MacBook (M-series), running **macOS 13+**
- **Admin rights** — writing fan speeds via the SMC needs a one-time privileged helper install
  (or run with `sudo` during development)

## Quick start

### Native app (recommended)

```bash
cd native
./build.sh
open build/FANcy.app
```

On first launch, open the **HELPER** section and click **Install** — that sets up the small
privileged helper FANcy uses to write fan speeds. That's it.

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
minimal helper (`FANcyHelper`) that performs them; the Python prototype uses `sudo` instead. On exit —
clean or not — FANcy hands the fans back to macOS's automatic control, and a crash-guard file lets it
recover if the app was killed mid-session.

## Project layout

| Path | What it is |
|---|---|
| `native/` | The shipping **SwiftUI app** — `build.sh` produces `FANcy.app` |
| `native/Sources/` | App, views, fan-curve editor, SMC kit, helper installer, Sparkle updater |
| `app.py` · `smc_helper.c` | The original **Python/Flet** prototype and its SMC helper |
| `fan_curve.json` | Saved curve (regenerated from the built-in default if missing) |

## Config

The fan curve is stored as a list of `[temperature, speed%]` points. FANcy manages it from the UI, but
you can edit it by hand too — if the file is missing, it falls back to the built-in `DEFAULT_CURVE`.

## License

MIT — see [`LICENSE`](LICENSE).

<div align="center">

Made for Apple Silicon MacBooks that deserve a fan dial.

</div>
