# Komorebi Menubar v0.2 plan

Decisions from the design review on 2026-09-28. Each phase ends with a check.

## Decisions

| Area | Decision |
|---|---|
| Audience | Public, for komorebi-for-Mac users who find the repo. Apple silicon only, because komorebi ships only an `aarch64` build. |
| Naming | `io.github.zepocas.*` for the bundle ID, agent labels and status item autosave name. Old `com.zepocas.*` agents are removed automatically. |
| Visibility | The repo goes public right after the rename. |
| Distribution | Homebrew cask from `zepocas/homebrew-tap`. It installs the prebuilt app into `/Applications`, which avoids the macOS 27 + Thaw bug for apps outside it. `git clone && make install` keeps working. |
| CI | GitHub Actions runs `make test` + `make bundle` on push and PR. Free for public repos. |
| Releases | Pushing a `v*` tag makes CI build, zip and publish a GitHub Release. `scripts/bump-cask.sh` updates the tap locally. The git tag sets the app version. |
| Services | komorebi and skhd only. Kanata is out of scope: no menu line; it lives in a personal startup script. |
| Setup | Moves into the app. Menu: Start at Login ▸ komorebi / skhd. `make agents` calls `KomorebiMenubar --install-agents …`. By default it sets up komorebi and the app itself. |
| Existing jobs | Replaced by ours after a confirmation dialog. Their plists are backed up to `~/Library/Application Support/KomorebiMenubar/replaced/`. `homebrew.mxcl.*` jobs are stopped with `brew services stop`. |
| Unmanaged services | Shown greyed out ("skhd — not managed"), with a tooltip pointing to Start at Login. |
| Workspace switcher | One submenu per monitor, titled by device name. Checkmark on each monitor's focused workspace. Click runs `focus-monitor-workspace`. |
| Layout | Top-level Layout ▸ with all 9 layouts komorebi accepts, for the focused workspace, the current one checked. |
| Paused | `⏸` at the end of the label for global pause (`is_paused`). `⏸` right after a monitor's segment when that workspace has tiling off (`tile: false`). Menu toggles: Pause tiling, Tile this workspace. |
| Logs | Logs ▸ komorebi / skhd / Komorebi Menubar, each opening in Console.app. |
| skhd bindings | The broken `alt+ctrl/shift - o` bindings (`reload-configuration`) are removed from the personal skhdrc. |

## Phases

> **Order changed (2026-09-28):** phase 4 (release flow) moves ahead of phases 2 and 3, which are
> on hold until releases run smoothly. The first Homebrew release is the existing `v0.1` tag.

### 0 · Housekeeping
- Rename `com.zepocas.*` to `io.github.zepocas.*` everywhere, and add cleanup of the legacy agents.
- Remove the two `o` bindings from `~/.config/komorebi/skhdrc`, then restart skhd.
- **Check:** agents run under the new labels, and no `com.zepocas.*` job is left in `launchctl list`.

### 1 · CI and going public
- Add `.github/workflows/ci.yml` (macOS runner: `make test`, `make bundle`).
- Push, then `gh repo edit --visibility public`, after a final confirmation.
- **Check:** the CI run is green on GitHub.

### 2 · Features
- Extend the decoded state with: monitor `device` name, workspace `layout`, workspace `tile`, `is_paused`, and the full workspace list. Add fixture tests.
- Add the monitor submenus, the Layout submenu, the paused markers and toggles, the Logs submenu, and greyed unmanaged services.
- **Check:** unit tests for label markers and layout decoding; manual checks for switching, layout change and pause, verified through the state.

### 3 · Setup inside the app

> **Partly done (2026-09-29):** `LaunchAgents.swift` generates the plists and the menu has
> Start at Login ▸ Komorebi Menubar / komorebi / skhd, each separate; the scripts and templates are
> gone. Plain plists, not `SMAppService`, which pins ad-hoc signed apps to one build. Foreign skhd
> jobs are detected and reported, not yet replaced; no `--install-agents` flags.

- A Swift `LaunchAgentInstaller` generates the plists, replacing `launchd/*.plist.in` and `scripts/install-agents.sh`.
- Foreign-job handling: detect, confirm, back up, and use `brew services stop` for brew jobs.
- Add the `--install-agents` / `--uninstall-agents` flags and the Start at Login menu. The Makefile delegates to the app. Update the README.
- **Check:** with a fake `com.koekeishiya.skhd` job: confirmation dialog, backup, replacement, then uninstall.

### 4 · Release
- `bundle.sh` stamps the version from the tag. Add `.github/workflows/release.yml` (build, `ditto` zip, GitHub Release).
- Create `zepocas/homebrew-tap` with the cask: `arm64`, macOS ≥ 14, quarantine removed after install, `uninstall quit` plus our agent labels, and a `zap` stanza.
- Add `scripts/bump-cask.sh` and the brew install instructions to the README. Tag `v0.2.0`.
- **Check:** `brew install --cask zepocas/tap/komorebi-menubar` installs into `/Applications`, the item stays visible with Thaw running, and Start at Login works.

## Out of scope
Kanata, notarization, Intel Macs, and a live profile swap via `replace-configuration` (it panics komorebi in the current build).
