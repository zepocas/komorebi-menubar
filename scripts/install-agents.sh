#!/usr/bin/env bash
# Installs (or with --uninstall removes) LaunchAgents that start komorebi, skhd and the
# menubar app at login. Rendered from launchd/*.plist.in into ~/Library/LaunchAgents.
set -euo pipefail
cd "$(dirname "$0")/.."

AGENTS=(com.zepocas.komorebi com.zepocas.skhd com.zepocas.komorebi-menubar)
AGENT_DIR="$HOME/Library/LaunchAgents"
DOMAIN="gui/$(id -u)"

if [[ "${1:-}" == "--uninstall" ]]; then
    for label in "${AGENTS[@]}"; do
        launchctl bootout "$DOMAIN/$label" 2>/dev/null && echo "Unloaded $label" || true
        rm -f "$AGENT_DIR/$label.plist"
    done
    echo "Removed. Start komorebi/skhd by hand again (komorebic start, skhd -c ...)."
    exit 0
fi

CONFIG_DIR="${KOMOREBI_CONFIG_HOME:-$HOME/.config/komorebi}"
CONFIG_DIR="${CONFIG_DIR%/}"
SEARCH_PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
KOMOREBI="$(PATH="$SEARCH_PATH" command -v komorebi)"
SKHD="$(PATH="$SEARCH_PATH" command -v skhd)"
SKHD_CONFIG="$CONFIG_DIR/skhdrc"
[[ -f "$SKHD_CONFIG" ]] || SKHD_CONFIG="$HOME/.config/skhd/skhdrc"
APP="/Applications/KomorebiMenubar.app"

[[ -e "$CONFIG_DIR/active.json" ]] || ln -s komorebi.json "$CONFIG_DIR/active.json"
[[ -d "$APP" ]] || { echo "Missing $APP. Run 'make install' first." >&2; exit 1; }

# Stop copies started by hand so the launchd ones don't collide with them.
if pgrep -x komorebi >/dev/null; then
    echo "Stopping running komorebi..."
    PATH="$SEARCH_PATH" komorebic stop || true
    for _ in {1..25}; do pgrep -x komorebi >/dev/null || break; sleep 0.2; done
fi
pkill -x skhd 2>/dev/null && echo "Stopped running skhd" || true
pkill -x KomorebiMenubar 2>/dev/null || true

mkdir -p "$AGENT_DIR" "$HOME/Library/Logs"
for label in "${AGENTS[@]}"; do
    target="$AGENT_DIR/$label.plist"
    sed -e "s|@HOME@|$HOME|g" \
        -e "s|@CONFIG_DIR@|$CONFIG_DIR|g" \
        -e "s|@PATH@|$SEARCH_PATH|g" \
        -e "s|@KOMOREBI@|$KOMOREBI|g" \
        -e "s|@SKHD@|$SKHD|g" \
        -e "s|@SKHD_CONFIG@|$SKHD_CONFIG|g" \
        -e "s|@APP@|$APP|g" \
        "launchd/$label.plist.in" > "$target"
    plutil -lint -s "$target"
    launchctl bootout "$DOMAIN/$label" 2>/dev/null || true
    launchctl bootstrap "$DOMAIN" "$target"
    echo "Loaded $label"
done

cat <<MSG

Done. komorebi, skhd and the menubar app now start at login.
They now run as their own processes (not under your terminal), so macOS may ask for permissions.
In System Settings → Privacy & Security:
  • Accessibility:     $KOMOREBI and $SKHD
  • Screen Recording:  $KOMOREBI
If one doesn't come up, check ~/Library/Logs/{komorebi,skhd}.log, grant the permission, then
use "Restart" from the Komorebi Menubar menu.
MSG
