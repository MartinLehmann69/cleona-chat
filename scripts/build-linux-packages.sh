#!/bin/bash
# build-linux-packages.sh — Baut AppImage, .deb und .rpm aus dem Flutter-Linux-Bundle
#
# Voraussetzungen:
#   - Flutter-Build bereits erstellt: flutter build linux --release
#   - appimagetool: https://github.com/AppImage/appimagetool
#   - dpkg-deb (apt install dpkg)
#   - rpmbuild (apt install rpm)
#
# Nutzung:
#   ./scripts/build-linux-packages.sh [VERSION]
#   Beispiel: ./scripts/build-linux-packages.sh 3.2.0

set -euo pipefail

VERSION="${1:-0.0.0}"
APP_NAME="cleona-chat"
DISPLAY_NAME="Cleona Chat"
DESCRIPTION="Decentralized post-quantum encrypted P2P messenger"
MAINTAINER="Martin Lehmann"
HOMEPAGE="https://github.com/MartinLehmann69/cleona-chat"

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_DIR="$SRC_DIR/build/linux/x64/release/bundle"
OUTPUT_DIR="$SRC_DIR/build/packages"
ICON_PATH="$SRC_DIR/assets/icon/cleona_icon.png"

# Pruefen ob Flutter-Bundle existiert
if [ ! -d "$BUNDLE_DIR" ]; then
  echo "FEHLER: Flutter-Bundle nicht gefunden: $BUNDLE_DIR"
  echo "Zuerst ausfuehren: flutter build linux --release"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "=== Cleona Chat Linux Package Builder ==="
echo "Version: $VERSION"
echo "Bundle:  $BUNDLE_DIR"
echo "Output:  $OUTPUT_DIR"
echo ""

# --- Desktop-Entry (gemeinsam genutzt) ---
create_desktop_entry() {
  local target="$1"
  cat > "$target" << EOF
[Desktop Entry]
Type=Application
Name=$DISPLAY_NAME
Comment=$DESCRIPTION
Exec=cleona-chat
Icon=cleona-chat
Categories=Network;InstantMessaging;Chat;
Keywords=messenger;chat;p2p;encrypted;quantum;
Terminal=false
StartupWMClass=cleona
MimeType=x-scheme-handler/cleona;
EOF
}

# ============================================================
# 1. AppImage
# ============================================================
echo "[1/3] AppImage erstellen..."

APPDIR="$OUTPUT_DIR/AppDir"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/lib/cleona" "$APPDIR/usr/share/applications" "$APPDIR/usr/share/icons/hicolor/256x256/apps"

# Bundle kopieren
cp -r "$BUNDLE_DIR"/* "$APPDIR/usr/lib/cleona/"

# Wrapper-Script
cat > "$APPDIR/usr/bin/cleona-chat" << 'WRAPPER'
#!/bin/bash
SELF_DIR="$(dirname "$(readlink -f "$0")")"
APP_DIR="$SELF_DIR/../lib/cleona"
export LD_LIBRARY_PATH="$APP_DIR/lib:${LD_LIBRARY_PATH:-}"
exec "$APP_DIR/cleona" "$@"
WRAPPER
chmod +x "$APPDIR/usr/bin/cleona-chat"

# Desktop-Entry + Icon
create_desktop_entry "$APPDIR/usr/share/applications/cleona-chat.desktop"
if [ -f "$ICON_PATH" ]; then
  cp "$ICON_PATH" "$APPDIR/usr/share/icons/hicolor/256x256/apps/cleona-chat.png"
fi

# AppRun
cat > "$APPDIR/AppRun" << 'APPRUN'
#!/bin/bash
SELF_DIR="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$SELF_DIR/usr/lib/cleona/lib:${LD_LIBRARY_PATH:-}"
exec "$SELF_DIR/usr/lib/cleona/cleona" "$@"
APPRUN
chmod +x "$APPDIR/AppRun"

# Desktop + Icon im Root (AppImage-Konvention)
cp "$APPDIR/usr/share/applications/cleona-chat.desktop" "$APPDIR/"
if [ -f "$ICON_PATH" ]; then
  cp "$ICON_PATH" "$APPDIR/cleona-chat.png"
fi

# AppImage bauen
APPIMAGE_OUTPUT="$OUTPUT_DIR/${APP_NAME}-${VERSION}-x86_64.AppImage"
if command -v appimagetool &> /dev/null; then
  ARCH=x86_64 appimagetool "$APPDIR" "$APPIMAGE_OUTPUT" 2>/dev/null
  echo "  OK: $APPIMAGE_OUTPUT"
else
  echo "  WARNUNG: appimagetool nicht installiert — AppDir vorbereitet aber nicht gepackt"
  echo "  Installieren: https://github.com/AppImage/appimagetool/releases"
fi

# ============================================================
# 2. Debian-Paket (.deb)
# ============================================================
echo ""
echo "[2/3] Debian-Paket (.deb) erstellen..."

DEB_DIR="$OUTPUT_DIR/deb-build"
rm -rf "$DEB_DIR"
mkdir -p "$DEB_DIR/DEBIAN"
mkdir -p "$DEB_DIR/opt/cleona"
mkdir -p "$DEB_DIR/usr/bin"
mkdir -p "$DEB_DIR/usr/share/applications"
mkdir -p "$DEB_DIR/usr/share/icons/hicolor/256x256/apps"

# Bundle kopieren
cp -r "$BUNDLE_DIR"/* "$DEB_DIR/opt/cleona/"

# Wrapper-Script
cat > "$DEB_DIR/usr/bin/cleona-chat" << 'WRAPPER'
#!/bin/bash
export LD_LIBRARY_PATH="/opt/cleona/lib:${LD_LIBRARY_PATH:-}"
exec /opt/cleona/cleona "$@"
WRAPPER
chmod +x "$DEB_DIR/usr/bin/cleona-chat"

# Desktop-Entry
create_desktop_entry "$DEB_DIR/usr/share/applications/cleona-chat.desktop"

# Icon
if [ -f "$ICON_PATH" ]; then
  cp "$ICON_PATH" "$DEB_DIR/usr/share/icons/hicolor/256x256/apps/cleona-chat.png"
fi

# Control-Datei
INSTALLED_SIZE=$(du -sk "$DEB_DIR/opt/cleona" | cut -f1)
cat > "$DEB_DIR/DEBIAN/control" << EOF
Package: $APP_NAME
Version: $VERSION
Section: net
Priority: optional
Architecture: amd64
Installed-Size: $INSTALLED_SIZE
Maintainer: $MAINTAINER
Homepage: $HOMEPAGE
Description: $DISPLAY_NAME - $DESCRIPTION
 Cleona Chat is a decentralized peer-to-peer messenger with post-quantum
 encryption. It operates without central servers. Your identity is purely
 cryptographic - no phone number or email required.
Depends: libgtk-3-0, libsodium23
EOF

# Post-Install (cleona:// URI-Handler registrieren)
cat > "$DEB_DIR/DEBIAN/postinst" << 'POSTINST'
#!/bin/bash
update-desktop-database /usr/share/applications 2>/dev/null || true
gtk-update-icon-cache /usr/share/icons/hicolor 2>/dev/null || true
POSTINST
chmod +x "$DEB_DIR/DEBIAN/postinst"

# Bauen
DEB_OUTPUT="$OUTPUT_DIR/${APP_NAME}_${VERSION}_amd64.deb"
dpkg-deb --build "$DEB_DIR" "$DEB_OUTPUT" 2>/dev/null
if [ $? -eq 0 ]; then
  echo "  OK: $DEB_OUTPUT"
else
  echo "  WARNUNG: dpkg-deb nicht verfuegbar oder Fehler beim Bauen"
fi

# ============================================================
# 3. RPM-Paket (.rpm)
# ============================================================
echo ""
echo "[3/3] RPM-Paket (.rpm) erstellen..."

RPM_BUILD="$OUTPUT_DIR/rpmbuild"
rm -rf "$RPM_BUILD"
mkdir -p "$RPM_BUILD"/{SPECS,BUILD,RPMS,SOURCES,SRPMS}

# Tarball fuer rpmbuild
TAR_NAME="${APP_NAME}-${VERSION}"
TAR_DIR="$RPM_BUILD/SOURCES/$TAR_NAME"
mkdir -p "$TAR_DIR/opt/cleona"
mkdir -p "$TAR_DIR/usr/bin"
mkdir -p "$TAR_DIR/usr/share/applications"
mkdir -p "$TAR_DIR/usr/share/icons/hicolor/256x256/apps"

cp -r "$BUNDLE_DIR"/* "$TAR_DIR/opt/cleona/"

cat > "$TAR_DIR/usr/bin/cleona-chat" << 'WRAPPER'
#!/bin/bash
export LD_LIBRARY_PATH="/opt/cleona/lib:${LD_LIBRARY_PATH:-}"
exec /opt/cleona/cleona "$@"
WRAPPER
chmod +x "$TAR_DIR/usr/bin/cleona-chat"

create_desktop_entry "$TAR_DIR/usr/share/applications/cleona-chat.desktop"
if [ -f "$ICON_PATH" ]; then
  cp "$ICON_PATH" "$TAR_DIR/usr/share/icons/hicolor/256x256/apps/cleona-chat.png"
fi

(cd "$RPM_BUILD/SOURCES" && tar czf "${TAR_NAME}.tar.gz" "$TAR_NAME")

# Spec-Datei
cat > "$RPM_BUILD/SPECS/${APP_NAME}.spec" << EOF
Name:           $APP_NAME
Version:        $VERSION
Release:        1
Summary:        $DISPLAY_NAME - $DESCRIPTION
License:        Proprietary
URL:            $HOMEPAGE
Source0:        %{name}-%{version}.tar.gz

%description
Cleona Chat is a decentralized peer-to-peer messenger with post-quantum
encryption. It operates without central servers. Your identity is purely
cryptographic - no phone number or email required.

%prep
%setup -q

%install
mkdir -p %{buildroot}/opt/cleona
mkdir -p %{buildroot}/usr/bin
mkdir -p %{buildroot}/usr/share/applications
mkdir -p %{buildroot}/usr/share/icons/hicolor/256x256/apps

cp -r opt/cleona/* %{buildroot}/opt/cleona/
cp usr/bin/cleona-chat %{buildroot}/usr/bin/
cp usr/share/applications/cleona-chat.desktop %{buildroot}/usr/share/applications/
if [ -f usr/share/icons/hicolor/256x256/apps/cleona-chat.png ]; then
  cp usr/share/icons/hicolor/256x256/apps/cleona-chat.png %{buildroot}/usr/share/icons/hicolor/256x256/apps/
fi

%post
update-desktop-database /usr/share/applications 2>/dev/null || true
gtk-update-icon-cache /usr/share/icons/hicolor 2>/dev/null || true

%files
/opt/cleona/
/usr/bin/cleona-chat
/usr/share/applications/cleona-chat.desktop
/usr/share/icons/hicolor/256x256/apps/cleona-chat.png

%changelog
EOF

# Bauen
if command -v rpmbuild &> /dev/null; then
  rpmbuild --define "_topdir $RPM_BUILD" -bb "$RPM_BUILD/SPECS/${APP_NAME}.spec" 2>/dev/null
  RPM_FILE=$(find "$RPM_BUILD/RPMS" -name "*.rpm" | head -1)
  if [ -n "$RPM_FILE" ]; then
    cp "$RPM_FILE" "$OUTPUT_DIR/"
    echo "  OK: $OUTPUT_DIR/$(basename "$RPM_FILE")"
  fi
else
  echo "  WARNUNG: rpmbuild nicht installiert — Spec-Datei vorbereitet"
  echo "  Installieren: sudo apt install rpm"
fi

# ============================================================
# Zusammenfassung
# ============================================================
echo ""
echo "=== Fertig ==="
echo "Pakete in: $OUTPUT_DIR/"
ls -lh "$OUTPUT_DIR"/*.{AppImage,deb,rpm} 2>/dev/null || echo "(Einige Formate konnten nicht gebaut werden — siehe Warnungen oben)"
echo ""
echo "Naechste Schritte:"
echo "  1. Pakete testen (auf sauberer VM installieren)"
echo "  2. Signieren: echo -n 'SHA256HASH' | openssl pkeyutl -sign -inkey /home/claude/CleonaPrivat/keys/cleona_maintainer_private.pem -rawin -out sig.bin"
echo "  3. GitHub Release: gh release create v$VERSION --title 'Cleona Chat v$VERSION' $OUTPUT_DIR/*"
