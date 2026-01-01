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
[ -f "$APP_DIR/cleona-daemon" ] && chmod +x "$APP_DIR/cleona-daemon"

# Read last profile for daemon autostart args
PROFILE_DIR=""
PORT=""
NAME=""
LAST_PROFILE="$HOME/.cleona/last_profile.json"
if [ -f "$LAST_PROFILE" ]; then
  PROFILE_DIR=$(python3 -c "import json; print(json.load(open('$LAST_PROFILE'))['profileDir'])" 2>/dev/null || true)
  PORT=$(python3 -c "import json; print(json.load(open('$LAST_PROFILE'))['port'])" 2>/dev/null || true)
  NAME=$(python3 -c "import json; print(json.load(open('$LAST_PROFILE'))['displayName'])" 2>/dev/null || true)
fi

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
StartupWMClass=cleona
EOF
chmod +x "$DESKTOP_DIR/cleona.desktop"

for DIR in "$HOME/Desktop" "$HOME/Schreibtisch"; do
  if [ -d "$DIR" ]; then
    cp "$DESKTOP_DIR/cleona.desktop" "$DIR/"
    chmod +x "$DIR/cleona.desktop"
    gio set "$DIR/cleona.desktop" metadata::trusted true 2>/dev/null || true
  fi
done

# Autostart: daemon with tray icon (runs at login, no GUI window)
if [ -f "$APP_DIR/cleona-daemon" ] && [ -n "$PROFILE_DIR" ] && [ -n "$PORT" ]; then
  mkdir -p "$AUTOSTART_DIR"
  cat > "$AUTOSTART_DIR/cleona-daemon.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Cleona Daemon
Comment=Cleona Chat Daemon mit Tray Icon
Exec=$APP_DIR/cleona-daemon --profile $PROFILE_DIR --port $PORT --name ${NAME:-Cleona}
Icon=$ICON_SOURCE
Terminal=false
X-GNOME-Autostart-enabled=true
Hidden=false
NoDisplay=true
EOF
  chmod +x "$AUTOSTART_DIR/cleona-daemon.desktop"
  echo "Autostart: Daemon + Tray Icon bei Login"
else
  echo "HINWEIS: Kein Autostart erstellt (erst App einrichten, dann install-desktop.sh nochmal ausfuehren)"
fi

echo "Installiert: $DESKTOP_DIR/cleona.desktop"
echo ""
echo "Ablauf:"
echo "  Login -> Daemon startet automatisch, Tray Icon erscheint"
echo "  Klick auf Tray 'Anzeigen' oder App-Icon -> GUI-Fenster oeffnet sich"
echo "  GUI-Fenster schliessen -> Daemon + Tray laufen weiter"
