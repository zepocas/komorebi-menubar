# Komorebi Indicator

A small native menubar item for [komorebi for Mac](https://komorebi-for-mac.lgug2z.com), inspired
by AeroSpace's built-in workspace indicator.

- Shows the focused workspace of **every monitor**, e.g. `2 │ 5`. The focused monitor is in bold.
  It updates instantly because komorebi pushes events to it.
- Its menu can **switch komorebi config profiles** and **restart komorebi and skhd**.
- Optional LaunchAgents start **komorebi, skhd and the indicator at login**.

It's plain Swift and AppKit with no dependencies. It uses almost no CPU while idle and needs no
permissions of its own.

## Requirements

- macOS 14 or later on Apple silicon (developed on macOS 27).
- [komorebi for Mac](https://komorebi-for-mac.lgug2z.com) with `komorebi` and `komorebic` on your
  machine, looked up in `~/.local/bin`, `/opt/homebrew/bin` and `/usr/local/bin`.
- Swift 6 toolchain: either Xcode or just the Command Line Tools (`xcode-select --install`).
- Optional: [skhd](https://github.com/koekeishiya/skhd) (`brew install koekeishiya/formulae/skhd`).

## Setup

### 1. Build and install the app

```sh
git clone git@github.com:zepocas/komorebi-indicator.git
cd komorebi-indicator
make test      # optional: run the unit tests
make run       # builds KomorebiIndicator.app, installs it to /Applications and opens it
```

The workspace number should now appear in the menubar. The app must live in `/Applications`.
On macOS 27, menubar managers like Thaw can drop items from apps in `~/Applications`
(see [Troubleshooting](#troubleshooting)).

With only this step, the icon and profile list work. Restarting komorebi or skhd from the menu,
and switching profiles while komorebi runs, need step 2.

### 2. Start everything at login (recommended)

```sh
make agents
```

This installs three LaunchAgents into `~/Library/LaunchAgents` and loads them:

| Agent | Runs | Behaviour |
|---|---|---|
| `com.zepocas.komorebi` | `komorebi --config <config dir>/active.json` | restarts after a crash; stays stopped after `komorebic stop` |
| `com.zepocas.skhd` | `skhd -c <skhdrc>` | always kept running |
| `com.zepocas.komorebi-indicator` | the app | restarts after a crash; stays quit after *Quit* |

This stops any komorebi or skhd you started by hand, then starts them under launchd.

### 3. Grant permissions

komorebi and skhd now run as their own processes instead of under your terminal. So macOS checks
*their* permissions, not your terminal's. In **System Settings → Privacy & Security**, allow:

- **Accessibility:** `komorebi` (e.g. `~/.local/bin/komorebi`) and `skhd` (e.g. `/opt/homebrew/bin/skhd`)
- **Screen Recording:** `komorebi`

Then use **Restart komorebi** / **Restart skhd** from the indicator menu. If you upgrade skhd with
Homebrew, its real path changes and you may need to grant it again.

### 4. Menubar managers (Thaw, Ice, Bartender)

New items can land in the hidden section. Drag **Komorebi Indicator** into the visible section,
using the manager's layout settings or ⌘-drag in the menubar.

## Usage

**The label**
- One segment per monitor, in komorebi's monitor order.
- Each segment is the workspace `name` from your config, or its number if it has no name.
- A dimmed icon means komorebi isn't running. The indicator reconnects on its own when komorebi comes back.
- macOS shows the same item on every display's menubar, so the label always lists all monitors.

**The menu**

| Item | What it does |
|---|---|
| komorebi / skhd status | Whether each is running, with its PID |
| **Profile ▸** | Switches the komorebi config (see below) |
| **Restart komorebi** | `komorebic stop` (restores hidden windows), then starts the launchd agent again. Shows **Start komorebi** when it isn't running |
| **Restart skhd** | Restarts the skhd agent |
| **Open Config Folder** | Opens your komorebi config directory |

### Profiles

A profile is any `komorebi*.json` in your komorebi config directory (`$KOMOREBI_CONFIG_HOME`, or
`~/.config/komorebi` by default). `komorebi.bar*.json` files are ignored. The menu names them like this:

| File | Shown as |
|---|---|
| `komorebi.json` | default |
| `komorebi.work.json` | work |
| `komorebi.laptop.json` | laptop |

The chosen profile is stored as a symlink, `active.json → komorebi.<profile>.json`. The app creates
it on first launch, pointing at `komorebi.json`. The komorebi agent always starts `active.json`, so
your choice survives restarts and reboots. When you pick a profile, the app moves the link and
restarts komorebi.

## Configuration

- **Config directory:** `$KOMOREBI_CONFIG_HOME` if set, otherwise `~/.config/komorebi`. Set it
  before running `make agents`; the agents get the value written into them.
- **skhd config:** `<config dir>/skhdrc` if it exists, otherwise `~/.config/skhd/skhdrc`.
- **Agent names:** `com.zepocas.*`. To use your own prefix, rename them in `launchd/*.plist.in`,
  `scripts/install-agents.sh` and `ServiceController.swift`.
- After changing any of the above, run `make agents` again.

## Troubleshooting

**The icon doesn't show, but the app is running.**
Check that it's installed in `/Applications`, not `~/Applications`. Then quit and reopen your
menubar manager. On macOS 27, Thaw can remove other apps' items
([thaw-app/Thaw#1135](https://github.com/thaw-app/Thaw/issues/1135)). Quitting Thaw briefly tells
you whether it's the cause.

**"The com.zepocas.komorebi LaunchAgent isn't loaded".**
Restart and profile switching go through launchd. Run `make agents`.

**komorebi doesn't come back after a restart.**
Check `~/Library/Logs/komorebi.log`. The message `failed to request screen capability` means
komorebi is missing Screen Recording or Accessibility (see step 3).

**skhd exits right after starting.**
It's missing Accessibility access. Check `~/Library/Logs/skhd.log`.

**Checking the agents.**
```sh
launchctl print gui/$(id -u)/com.zepocas.komorebi | grep -E 'state|pid|last exit'
```

## Uninstall

```sh
make uninstall        # unloads the agents and removes /Applications/KomorebiIndicator.app
```

After this, start komorebi and skhd by hand again (`komorebic start`, `skhd -c …`). You can
delete `<config dir>/active.json` if you don't need it.

## How it works

- **Live updates:** the app listens on `komorebi-indicator.sock` in
  `~/Library/Application Support/komorebi/` and runs `komorebic subscribe-socket` once. komorebi
  then opens one connection per event and writes a single `{event, state}` JSON document. The app
  redraws only when the label text changes, because komorebi sends a steady stream of window
  move and resize events.
- **Reconnecting:** every 2 s the app checks for the `komorebi` process, which is cheap. A new PID
  means a fresh komorebi that has forgotten the subscription, so the app subscribes again and
  loads `komorebic state` straight away.
- **Why restarts go through launchd:** if the app launched komorebi or skhd itself, macOS would
  treat the app as their "responsible process" and check *the app's* Accessibility and Screen
  Recording permissions. Run by launchd, they use their own permissions, so the indicator needs none.

### komorebi-for-mac quirks this works around

- `komorebic replace-configuration` crashes komorebi (`macos_api.rs:204`) and leaves it ignoring
  commands. That's why switching profile restarts komorebi, and why restart falls back to SIGTERM.
- `komorebic start --config <path>` passes a broken flag to komorebi, so the agent runs `komorebi`
  directly.
- `komorebic reload-configuration` doesn't exist. Use the menu's restart instead.

## Development

```
Sources/IndicatorCore/        decoding, label formatting, profile discovery (unit tested)
Sources/KomorebiIndicator/    AppKit app: socket subscriber, process watcher, menu, launchd control
Tests/IndicatorCoreTests/     Swift Testing suite and a JSON fixture
launchd/                      LaunchAgent templates (@PLACEHOLDERS@ filled in by install-agents.sh)
scripts/                      bundle.sh (builds the .app), install-agents.sh
```

| Command | Does |
|---|---|
| `make build` | debug build |
| `make test` | unit tests |
| `make install` | release build, installed to `/Applications` |
| `make run` | install and open |
| `make agents` / `make uninstall-agents` | install / remove the LaunchAgents |
| `make uninstall` | remove the agents and the app |
| `make clean` | delete build output |

When the agents are loaded, `make install` is enough to update: launchd relaunches the new build.

## License

[MIT](LICENSE)
