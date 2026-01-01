#!/bin/bash
# Install Cleona: desktop icon + daemon autostart with tray icon
set -e

APP_DIR="$HOME/cleona-app"
DESKTOP_DIR="$HOME/.local/share/applications"
AUTOSTART_DIR="$HOME/.config/autostart"
ICON_SOURCE="$APP_DIR/data/flutter_assets/assets/app_icon.png"

if [ ! -f "$APP_DIR/cleona" ]; then
  echo "Error: $APP_DIR/cleona not found. Deploy the app first."
  exit 1
fi

chmod +x "$APP_DIR/cleona"

# S367: the daemon lives in the bundle under `bin/`. `dart build cli` embeds
# the path of its store library as `../lib/libsqlite3.so` RELATIVE TO THE
# BINARY; from the bundle root that pointed one level too high,
# and the daemon ended with exit 0 when opening the store. The
# root path remains as a fallback for bundles in the old layout.
DAEMON_BIN=""
for _cand in "$APP_DIR/bin/cleona-daemon" "$APP_DIR/cleona-daemon"; do
  if [ -f "$_cand" ]; then DAEMON_BIN="$_cand"; break; fi
done
[ -n "$DAEMON_BIN" ] && chmod +x "$DAEMON_BIN"

# Is there a set-up profile at all?
#
# S368: here stood a `json.load` on `$HOME/.cleona/last_profile.json`,
# from which `--profile`, `--port` and `--name` came for the autostart. The
# file has been encrypted since S368 (`last_profile.json.enc`,
# device-wide key from the master seed) — a shell script can
# no longer read it, and should not: it carries the
# display name next to the network identifier.
#
# THE THREE VALUES WERE NO LONGER NEEDED ANYWAY. `--profile` is explicitly
# listed in the daemon as "Legacy: single-identity profile dir"
# (`service_daemon.dart:_parseArgs`), `--name` likewise, and `--port`
# overrides a port that the daemon otherwise takes from the identity.
# Today's contract is ONE daemon per machine via `--base-dir`,
# with all identities active at the same time. Exactly that is now in the
# autostart file.
PROFILE_MARK="$HOME/.cleona/identities.json.enc"

# Desktop entry (opens GUI window)
mkdir -p "$DESKTOP_DIR"
cat > "$DESKTOP_DIR/cleona.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Cleona Chat
Comment=Dezentraler P2P Messenger mit Post-Quantum-Verschluesselung
Exec=$APP_DIR/cleona
Icon=$ICON_SOURCE
Terminal=false
Categories=Network;Chat;InstantMessaging;
Keywords=chat;messenger;p2p;encryption;
StartupNotify=true
StartupWMClass=chat.cleona.cleona
EOF
chmod +x "$DESKTOP_DIR/cleona.desktop"

# Install icon into hicolor theme so DEs resolve it by name ("cleona")
ICON_THEME_DIR="$HOME/.local/share/icons/hicolor"
for SIZE in 48 128 256; do
  mkdir -p "$ICON_THEME_DIR/${SIZE}x${SIZE}/apps"
done
ICON_SRC_DIR="$APP_DIR/data/flutter_assets/assets"
[ -f "$ICON_SRC_DIR/icon_48.png" ] && cp "$ICON_SRC_DIR/icon_48.png" "$ICON_THEME_DIR/48x48/apps/cleona.png"
[ -f "$ICON_SRC_DIR/icon_128.png" ] && cp "$ICON_SRC_DIR/icon_128.png" "$ICON_THEME_DIR/128x128/apps/cleona.png"
[ -f "$ICON_SRC_DIR/app_icon.png" ] && cp "$ICON_SRC_DIR/app_icon.png" "$ICON_THEME_DIR/256x256/apps/cleona.png"
gtk-update-icon-cache "$ICON_THEME_DIR" 2>/dev/null || true

for DIR in "$HOME/Desktop" "$HOME/Schreibtisch"; do
  if [ -d "$DIR" ]; then
    cp "$DESKTOP_DIR/cleona.desktop" "$DIR/"
    chmod +x "$DIR/cleona.desktop"
    gio set "$DIR/cleona.desktop" metadata::trusted true 2>/dev/null || true
  fi
done

# Autostart: daemon with tray icon (runs at login, no GUI window)
# Three intentions at the same place, all three needed (S370):
#   * `$DAEMON_BIN`  — the daemon has lived in `bin/` since the bundle rework
#   * `--profile` is dropped — the daemon accepted the switch and discarded it
#   * `$PROFILE_MARK` — `last_profile.json` is now encrypted;
#     a shell script can no longer read it, so the marker
#     `identities.json.enc` carries the question "is there a profile at all?"
# `$PORT`/`$NAME` no longer exist — checking on them would mean checking on
# a condition that is always false.
if [ -n "$DAEMON_BIN" ] && [ -f "$PROFILE_MARK" ]; then
  mkdir -p "$AUTOSTART_DIR"
  # S370: here it said `--name` stays. It does NOT stay — its value came
  # from `last_profile.json`, and that is now encrypted. The
  # daemon takes display name and port from the identity.
  cat > "$AUTOSTART_DIR/cleona-daemon.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Cleona Daemon
Comment=Cleona Chat Daemon mit Tray Icon
Exec=$DAEMON_BIN --base-dir $HOME/.cleona
Icon=$ICON_SOURCE
Terminal=false
X-GNOME-Autostart-enabled=true
Hidden=false
NoDisplay=true
EOF
  chmod +x "$AUTOSTART_DIR/cleona-daemon.desktop"
  echo "Autostart: Daemon + Tray Icon bei Login"
else
  echo "NOTE: no autostart created (set up the app first, then run install-desktop.sh again)"
fi

echo "Installed: $DESKTOP_DIR/cleona.desktop"
echo ""
echo "Flow:"
echo "  Login -> daemon starts automatically, tray icon appears"
echo "  Click on tray 'Anzeigen' or app icon -> GUI window opens"
echo "  Close GUI window -> daemon + tray keep running"
