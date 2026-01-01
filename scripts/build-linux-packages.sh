#!/bin/bash
# build-linux-packages.sh — builds AppImage, .deb and .rpm from the Flutter Linux bundle
#
# Prerequisites:
#   - Flutter build already created: flutter build linux --release
#   - appimagetool: https://github.com/AppImage/appimagetool
#   - dpkg-deb (apt install dpkg)
#   - rpmbuild (apt install rpm)
#
# Usage:
#   ./scripts/build-linux-packages.sh [VERSION]
#   Example: ./scripts/build-linux-packages.sh 3.2.0
#   ./scripts/build-linux-packages.sh --print-lab-packages
#     prints the packages a lab node gets (scripts/vm/vm-deploy.sh): the
#     Depends and Recommends of the .deb that are not derived from the
#     bundle, one entry per line as `<depends|recommends> <a> [| <b> …]` —
#     the alternatives stay, the lab resolves them like apt does (an
#     installed one satisfies the entry, else the first with an install
#     candidate); nothing is built
#
# ── RE-CHECKED FOR THE BUNDLE REWORK (S367) ──────────────────────────
#
# Since S367 the daemon lives in `bundle/bin/`, its store library in
# `bundle/lib/`. This script needs to know NOTHING of that, and that
# is measured, not assumed:
#
#   * All three formats copy the bundle with `cp -r "$BUNDLE_DIR"/*`
#     — `bin/` and `lib/` come along as subdirectories.
#   * The three wrappers below set `LD_LIBRARY_PATH` to `<app>/lib`
#     and start the GUI (`<app>/cleona`). Both remain correct: the
#     bundle root is unchanged the directory of the GUI, and
#     `<app>/bin/../lib` is exactly the same `lib`.
#   * There is no daemon call here (checked: `grep -n daemon`
#     finds no line in this file). The GUI starts the daemon
#     via `_findDaemonBinary()`, and that looks in `bin/` first.
#
# Whoever adds an autostart here in the future uses
# `<app>/bin/cleona-daemon` — not `<app>/cleona-daemon`.

set -euo pipefail

# ── RUNTIME DEPENDENCIES (S410, owner decision E6) ───────────────────────
#
# "The installation must make sure that all needed packages are installed."
# Until S410 the .deb declared `libgtk-3-0, libsodium23` and the .rpm
# nothing: on Ubuntu 26.04 without pulseaudio-utils a click on the
# microphone did nothing (gui-33a 33b.02: `parecord=missing`,
# S410-RCA-C2-CHAT-EINGABE.md C2-9), and libcleona_voice.so's own libraries
# (libpipewire-0.3, libwebrtc_audio_processing) were never declared.
#
# TWO KINDS OF DEPENDENCY, TWO SOURCES:
#   * Libraries an ELF file of the bundle links against (NEEDED): derived
#     from the bundle at build time (derive_elf_depends below) — not
#     written down, because a hand-kept list drifts the moment a native
#     library gains or loses a dependency (libcleona_voice.so linked
#     libpipewire-0.3 and the system's libwebrtc_audio_processing until S410;
#     since S410 webrtc ships statically inside the bundle's
#     libcleona_voice_apm.so and only libpipewire-0.3 remains, measured
#     29.10.2026 with readelf -d — S410-VOICE-BAU.md).
#     The release is built on Ubuntu; the names are those of that
#     generation and later.
#   * Programs the app starts (Process.start/run) and libraries it opens by
#     name (DynamicLibrary.open): invisible to readelf, so they are listed
#     here, each with the place in the code that needs it. Measured
#     29.10.2026 over lib/, bin/, mycelium/lib and the Linux parts of the
#     plugins in pubspec.lock (record_linux 1.3.0, file_picker 8.3.7).
#     The lab (scripts/vm/vm-deploy.sh) installs from THIS list
#     (--print-lab-packages), so it cannot drift from the package.
#
# DEPENDS = the app does not work without it (a core function fails or a
# key is stored worse). RECOMMENDS = one optional function needs it
# (installed by default by apt and dnf; with --no-install-recommends only
# that function is missing). SUGGESTS = rarely used.
#
# Not listed, although the app uses them: Essential packages of Debian
# (coreutils: cp, chmod, df; tar; bash; debianutils: which; util-linux:
# setsid, dmesg) — Debian policy 3.5: a package does not declare them.
#
# AppImage and the tar.gz (also the payload of the in-app update) cannot
# declare anything. There the app itself has to say what is missing when a
# function needs it (C2-9 (a): the voice message names `parecord` /
# pulseaudio-utils instead of doing nothing); an update keeps the packages
# the first installation brought.
#
# FINDING I-6 (S410, owner decision C 29.10.2026) — how the three libraries
# the app opens by name get onto the machine; the names the loaders open
# stand in lib/core/platform/linux_native_libraries.dart:
#   * libsodium, libzstd: from the SYSTEM. The loaders open the runtime
#     sonames (`libsodium.so.26` / `libsodium.so.23`, `libzstd.so.1`) that
#     the packages below ship — no -dev package needed. libsodium 1.0.19+
#     carries soname 26 (Debian forky/sid `libsodium26`, Fedora 43+), 1.0.18
#     soname 23 (Debian bookworm/trixie, Ubuntu 22.04-26.04 `libsodium23`);
#     sources in linux_native_libraries.dart.
#   * liboqs: packaged by no distribution — every bundle carries it
#     (linux/liboqs, installed by linux/CMakeLists.txt as
#     bundle/lib/liboqs.so; release-build.sh refuses a bundle without it).
#   * The AppImage carries libsodium and libzstd too (AppImage convention:
#     everything inside), copied from the build host below.
#   * libwhisper (lib/core/archive/whisper_ffi.dart, transcription) — not
#     packaged, not bundled (open, not part of I-6).

# .deb: Debian/Ubuntu package names; "a | b" = either.
LINUX_DEB_DEPENDS=(
  # crypto/sodium_ffi.dart _openLibsodium (dlopen libsodium.so.26 or
  # libsodium.so.23, platform/linux_native_libraries.dart) — I-6.
  # libsodium23 first: it is the one Ubuntu 22.04-26.04 and Debian
  # bookworm/trixie have; apt (and the lab, --print-lab-packages) takes
  # libsodium26 where only that exists.
  "libsodium23 | libsodium26"
  # codec/compression.dart _openLib (dlopen libzstd.so.1) — I-6
  "libzstd1"
  # platform/libsecret_ffi.dart: dlopen libsecret-1.so.0 (store a key)
  "libsecret-1-0"
  # crypto/keyring_service.dart: secret-tool (probe, lookup, delete); without
  # it the keys fall back to the file variant
  "libsecret-tools"
  # tray/native_tray.dart: dlopen libayatana-appindicator3.so.1, then
  # libappindicator3.so.1
  "libayatana-appindicator3-1 | libappindicator3-1"
  # record_linux 1.3.0 (voice messages): parecord, pactl;
  # service/notification_sound_service.dart: paplay (pw-play preferred)
  "pulseaudio-utils"
  # record_linux 1.3.0: ffmpeg (encodes the recording);
  # archive/voice_transcription_service.dart: ffmpeg;
  # ui/screens/chat_screen.dart: ffprobe, ffplay (voice message playback)
  "ffmpeg"
  # file_picker 8.3.7 (attachments, calendar import, save as): zenity,
  # kdialog or qarma
  "zenity | kdialog | qarma"
  # ui/screens/chat_screen.dart _launchIncognito: xdg-open
  "xdg-utils"
  # update/binary_update_manager.dart: rsync (apply an update, roll back)
  "rsync"
  # service_daemon.dart, main.dart, update/gui_update_start.dart: ps, pkill, kill
  "procps"
  # util/uplink_state.dart, service_daemon.dart (ip monitor),
  # archive/archive_network.dart: ip
  "iproute2"
)
LINUX_DEB_RECOMMENDS=(
  # util/uplink_state.dart, archive/archive_network.dart: nmcli (metered
  # network, Wi-Fi name for the archive); without it: unmetered, no SSID
  "network-manager"
  # link_io/upnp_igd.dart _hopsOutTool: tracepath (first hops)
  "iputils-tracepath"
  # media/clipboard_helper.dart, chat_screen.dart: wl-paste/wl-copy or xclip
  # (images through the clipboard)
  "wl-clipboard | xclip"
  # archive/archive_transport.dart: smbclient (SMB), ssh/sftp (SFTP), curl
  # (FTP/WebDAV) — the protocol the user chooses for the archive
  "smbclient"
  "openssh-client"
  "curl"
  # archive/archive_network.dart readCurrentSsid: iwgetid, only when nmcli
  # gives no Wi-Fi name. Ubuntu 26.04 has no wireless-tools any more and no
  # other package ships iwgetid (measured 29.10.2026 on the lab nodes:
  # `apt-cache policy wireless-tools` -> candidate (none), no reverse
  # provides); there the name comes from nmcli (network-manager above). It
  # stays a Recommends for the releases that have it: apt skips a Recommends
  # without a candidate and installs the rest (S410-LABOR-SKRIPTE.md). `iw`
  # is NOT an alternative here — it is another program, the code does not
  # call it.
  "wireless-tools"
)
LINUX_DEB_SUGGESTS=(
  # ui/screens/identity_detail_screen.dart: fswebcam (profile photo from
  # the webcam)
  "fswebcam"
)
# .rpm: by file and by soname, neutral across Fedora/openSUSE package names.
# rpmbuild derives the NEEDED libraries itself (AutoReq); these are the rest,
# the same entries as above.
LINUX_RPM_REQUIRES=(
  "(libsodium.so.26()(64bit) or libsodium.so.23()(64bit))"
  "libzstd.so.1()(64bit)"
  "libsecret-1.so.0()(64bit)"
  "/usr/bin/secret-tool"
  "(libayatana-appindicator3.so.1()(64bit) or libappindicator3.so.1()(64bit))"
  "/usr/bin/parecord"
  "/usr/bin/pactl"
  "(/usr/bin/paplay or /usr/bin/pw-play)"
  "/usr/bin/ffmpeg"
  "/usr/bin/ffprobe"
  "/usr/bin/ffplay"
  "(/usr/bin/zenity or /usr/bin/kdialog or /usr/bin/qarma)"
  "/usr/bin/xdg-open"
  "/usr/bin/rsync"
  "/usr/bin/ps"
  "/usr/bin/pkill"
  "/usr/bin/setsid"
  "(/usr/sbin/ip or /usr/bin/ip)"
)
LINUX_RPM_RECOMMENDS=(
  "/usr/bin/nmcli"
  "(/usr/bin/tracepath or /usr/sbin/tracepath)"
  "(/usr/bin/wl-paste or /usr/bin/xclip)"
  "/usr/bin/smbclient"
  "/usr/bin/sftp"
  "/usr/bin/curl"
)

# "a", "b | c" -> "a, b | c" (one Depends line).
deb_join() {
  local out="" e
  for e in "$@"; do
    out="${out:+$out, }$e"
  done
  printf '%s' "$out"
}

# The lab list: `<class> <entry>` per line, the entry as in the .deb with its
# alternatives. Until S410 only the first alternative was printed and the
# class was dropped — the lab could neither fall back to "b" nor tell a
# missing Depends (a defect) from a missing Recommends (one function less);
# one name without a candidate (wireless-tools on Ubuntu 26.04) kept the
# whole list from being installed (S410-LABOR-DEPLOY.md F-1).
if [ "${1:-}" = "--print-lab-packages" ]; then
  for e in "${LINUX_DEB_DEPENDS[@]}"; do printf 'depends %s\n' "$e"; done
  for e in "${LINUX_DEB_RECOMMENDS[@]}"; do printf 'recommends %s\n' "$e"; done
  exit 0
fi

VERSION="${1:-0.0.0}"
APP_NAME="cleona-chat"
DISPLAY_NAME="Cleona Chat"
DESCRIPTION="Decentralized post-quantum encrypted P2P messenger"
MAINTAINER="Martin Lehmann"
HOMEPAGE="https://github.com/MartinLehmann69/cleona-chat"

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_DIR="$SRC_DIR/build/linux/x64/release/bundle"
OUTPUT_DIR="$SRC_DIR/build/packages"
ICON_PATH="$SRC_DIR/assets/app_icon.png"

# Check whether the Flutter bundle exists
if [ ! -d "$BUNDLE_DIR" ]; then
  echo "ERROR: Flutter bundle not found: $BUNDLE_DIR"
  echo "Run first: flutter build linux --release"
  exit 1
fi

# The packages that provide the libraries the ELF files of the bundle link
# against, minus what the bundle carries itself — one per line. Fails (exit
# 1, the soname on stderr) if the build host cannot resolve a NEEDED soname:
# a package that declares less than its programs load is the finding of
# C2-9, not a warning.
derive_elf_depends() {
  local bundle="$1" f so path real pkg unresolved=""
  local -A own=() seen=() pkgs=()
  while IFS= read -r f; do own["$(basename "$f")"]=1; done \
    < <(find -H "$bundle" \( -type f -o -type l \) -name '*.so*')
  while IFS= read -r f; do
    [ "$(head -c 4 "$f" 2>/dev/null | od -An -c | tr -d ' ')" = '177ELF' ] || continue
    while IFS= read -r so; do
      [ -n "$so" ] || continue
      [ -n "${own[$so]:-}" ] && continue
      [ -n "${seen[$so]:-}" ] && continue
      seen["$so"]=1
      # `|| …=""`: under `set -o pipefail` an early `exit` of awk (SIGPIPE
      # for ldconfig) or a `dpkg -S` without a match would end the script.
      path=$(ldconfig -p | awk -v s="$so" '$1 == s && /x86-64/ { print $NF; exit }') || path=""
      pkg=""
      if [ -n "$path" ]; then
        real=$(readlink -f "$path" 2>/dev/null) || real="$path"
        pkg=$(dpkg -S "$real" 2>/dev/null | head -1 | cut -d: -f1) || pkg=""
        [ -n "$pkg" ] || pkg=$(dpkg -S "$path" 2>/dev/null | head -1 | cut -d: -f1) || pkg=""
      fi
      if [ -z "$pkg" ]; then
        unresolved="$unresolved $so"
        continue
      fi
      pkgs["$pkg"]=1
    done < <(readelf -d "$f" 2>/dev/null | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p')
  done < <(find -H "$bundle" -type f)
  if [ -n "$unresolved" ]; then
    echo "ERROR: no package on this build host provides:$unresolved" >&2
    return 1
  fi
  printf '%s\n' "${!pkgs[@]}" | sort
}

ELF_DEPENDS=$(derive_elf_depends "$BUNDLE_DIR") || {
  echo "ERROR: the runtime libraries of the bundle could not be mapped to packages — no package is built"
  exit 1
}
mapfile -t ELF_DEPENDS_ARR <<< "$ELF_DEPENDS"
DEB_DEPENDS_LINE=$(deb_join "${ELF_DEPENDS_ARR[@]}" "${LINUX_DEB_DEPENDS[@]}")
DEB_RECOMMENDS_LINE=$(deb_join "${LINUX_DEB_RECOMMENDS[@]}")
DEB_SUGGESTS_LINE=$(deb_join "${LINUX_DEB_SUGGESTS[@]}")
echo "Depends (.deb):    $DEB_DEPENDS_LINE"
echo "Recommends (.deb): $DEB_RECOMMENDS_LINE"
echo ""

mkdir -p "$OUTPUT_DIR"

echo "=== Cleona Chat Linux Package Builder ==="
echo "Version: $VERSION"
echo "Bundle:  $BUNDLE_DIR"
echo "Output:  $OUTPUT_DIR"
echo ""

# --- Desktop entry (shared) ---
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
StartupWMClass=chat.cleona.cleona
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

# I-6 (S410): the AppImage carries libsodium and libzstd as well — the
# AppImage convention is "everything inside", and it declares no
# dependencies. Copied from the build host under the file name the loaders
# look for in the bundle (`LinuxBundleFile.appImageOnly(...)` in
# lib/core/platform/linux_native_libraries.dart); the loaders still prefer a
# system copy (runtime soname first). A host without the runtime package
# stops the AppImage here instead of producing one without them.
#   $1 file name in the bundle, $2… runtime sonames, newest first
appimage_bundle_system_lib() {
  local dest_name="$1" soname path=""
  shift
  for soname in "$@"; do
    path=$(ldconfig -p | awk -v s="$soname" '$1 == s && /x86-64/ { print $NF; exit }') || path=""
    [ -n "$path" ] && break
  done
  if [ -z "$path" ]; then
    echo "ERROR: none of $* on this build host — the AppImage would lack $dest_name" >&2
    return 1
  fi
  cp -L "$path" "$APPDIR/usr/lib/cleona/lib/$dest_name"
  echo "  AppImage: $dest_name <- $(readlink -f "$path")"
}
appimage_bundle_system_lib libsodium.so libsodium.so.26 libsodium.so.23 || exit 1
appimage_bundle_system_lib libzstd.so libzstd.so.1 || exit 1

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

# Desktop + icon in the root (AppImage convention)
cp "$APPDIR/usr/share/applications/cleona-chat.desktop" "$APPDIR/"
if [ -f "$ICON_PATH" ]; then
  cp "$ICON_PATH" "$APPDIR/cleona-chat.png"
fi

# Build AppImage
APPIMAGE_OUTPUT="$OUTPUT_DIR/${APP_NAME}-${VERSION}-x86_64.AppImage"
if command -v appimagetool &> /dev/null; then
  ARCH=x86_64 appimagetool "$APPDIR" "$APPIMAGE_OUTPUT" 2>/dev/null
  echo "  OK: $APPIMAGE_OUTPUT"
else
  echo "  WARNING: appimagetool not installed — AppDir prepared but not packed"
  echo "  Install: https://github.com/AppImage/appimagetool/releases"
fi

# ============================================================
# 2. Debian package (.deb)
# ============================================================
echo ""
echo "[2/3] Creating Debian package (.deb)..."

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

# Control file
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
Depends: $DEB_DEPENDS_LINE
Recommends: $DEB_RECOMMENDS_LINE
Suggests: $DEB_SUGGESTS_LINE
EOF

# Post-Install (cleona:// URI-Handler registrieren)
cat > "$DEB_DIR/DEBIAN/postinst" << 'POSTINST'
#!/bin/bash
update-desktop-database /usr/share/applications 2>/dev/null || true
gtk-update-icon-cache /usr/share/icons/hicolor 2>/dev/null || true
POSTINST
chmod +x "$DEB_DIR/DEBIAN/postinst"

# OWNER AND MODES OF THE PAYLOAD (S410-I6-MESSUNG, finding 3). Without
# --root-owner-group dpkg-deb records the uid/gid of the build user, and the
# build user's umask 0002 left directories and programs group-writable
# (measured: `drwxrwxr-x claude/claude ./opt/cleona/`, installed on Ubuntu
# 24.04 as `UNKNOWN:UNKNOWN 775 /opt/cleona` — owned by whoever is uid 1002
# there, and that group could replace the program every user starts).
#   * --root-owner-group: "Set the owner and group for each entry in the
#     filesystem tree data to root with id 0 (since dpkg 1.19.0)" — dpkg-deb(1),
#     dpkg 1.22.6 on the build host.
#   * chmod: owner rw, nobody else writes; `X` keeps the execute bit exactly
#     where one was set (programs, wrapper, directories).
#     The root entry `./` is the build directory itself — it gets 0755 too
#     (measured: `drwxrwxr-x root/root ./` without it).
chmod -R u=rwX,go=rX "$DEB_DIR/opt" "$DEB_DIR/usr"
chmod 0755 "$DEB_DIR" "$DEB_DIR/DEBIAN"

# Build
DEB_OUTPUT="$OUTPUT_DIR/${APP_NAME}_${VERSION}_amd64.deb"
dpkg-deb --root-owner-group --build "$DEB_DIR" "$DEB_OUTPUT" >/dev/null

# Check of the built package, not of the build directory: every entry
# root/root, none writable for group or others (a symlink always shows
# lrwxrwxrwx; its mode is not used — symlink(7)). Otherwise no .deb.
DEB_BAD=$(dpkg-deb -c "$DEB_OUTPUT" | awk '$2 != "root/root" || ($1 !~ /^l/ && (substr($1, 6, 1) == "w" || substr($1, 9, 1) == "w"))') || {
  echo "ERROR: dpkg-deb -c cannot read $DEB_OUTPUT"; rm -f "$DEB_OUTPUT"; exit 1; }
if [ -n "$DEB_BAD" ]; then
  echo "ERROR: the .deb carries entries not owned by root/root or writable for group/others — removed:"
  printf '%s\n' "$DEB_BAD" | head -20
  rm -f "$DEB_OUTPUT"
  exit 1
fi
echo "  OK: $DEB_OUTPUT (owner root/root, no group/other write — checked with dpkg-deb -c)"

# ============================================================
# 3. RPM package (.rpm)
# ============================================================
echo ""
echo "[3/3] Creating RPM package (.rpm)..."

RPM_BUILD="$OUTPUT_DIR/rpmbuild"
rm -rf "$RPM_BUILD"
mkdir -p "$RPM_BUILD"/{SPECS,BUILD,RPMS,SOURCES,SRPMS}

# Tarball for rpmbuild
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
# Modes as for the .deb (finding 3): nobody but the owner writes. The owner
# is root through %defattr in the spec.
chmod -R u=rwX,go=rX "$TAR_DIR/opt" "$TAR_DIR/usr"

(cd "$RPM_BUILD/SOURCES" && tar czf "${TAR_NAME}.tar.gz" "$TAR_NAME")

# Runtime dependencies (S410, E6): rpmbuild derives the NEEDED libraries of
# the ELF files itself (AutoReq); programs and dlopen libraries come from
# LINUX_RPM_REQUIRES/RECOMMENDS at the top — by file and by soname, so they
# hold on Fedora and openSUSE alike.
RPM_DEPS=""
for r in "${LINUX_RPM_REQUIRES[@]}"; do RPM_DEPS="${RPM_DEPS}Requires:       $r"$'\n'; done
for r in "${LINUX_RPM_RECOMMENDS[@]}"; do RPM_DEPS="${RPM_DEPS}Recommends:     $r"$'\n'; done

# PRIVATE LIBRARIES STAY PRIVATE (S410, I-6 follow-up). rpmbuild's AutoProv
# announced every .so under /opt/cleona as a package capability — measured
# on the 4.2.99 test package: `rpm -qp --provides` listed liboqs.so.9,
# libopus.so.0, libsqlite3.so, libflutter_linux_gtk.so and eleven more. dnf
# could then satisfy a FOREIGN package's dependency with Cleona's private
# copy, and a later system liboqs would collide with it. Two filters, as the
# rpm documentation describes them ("Filtering dependencies",
# dependency_generators.md, rpm 4.18:
# https://rpm.org/user_doc/dependency_generators.html):
#   * %__provides_exclude_from — a PATH regex: no provides from anything
#     under /opt/cleona/.
#   * %__requires_exclude — a DEPENDENCY regex: AutoReq still derives what
#     the ELF files need from the system (libgtk-3.so.0, libc.so.6 …), but
#     not what the bundle itself satisfies (libflutter_linux_gtk.so,
#     libopus.so.0 …). Without it the package would require capabilities
#     nobody provides any more, and would not install.
# The private set is derived from the bundle at build time — every file
# name `lib*.so*` and every SONAME — so a new bundled library needs no edit
# here. `[.]` and `[(]` instead of backslashes: the spec parser eats single
# backslashes (same documentation).
RPM_PRIVATE_NAMES=$( { find -H "$BUNDLE_DIR" \( -type f -o -type l \) -name 'lib*.so*' -printf '%f\n'
                       find -H "$BUNDLE_DIR" -type f -name 'lib*.so*' -exec readelf -d {} \; 2>/dev/null \
                         | sed -n 's/.*(SONAME).*\[\(.*\)\]/\1/p'
                     } | sort -u | sed 's/[.]/[.]/g' | paste -sd'|' )
if [ -z "$RPM_PRIVATE_NAMES" ] || ! grep -qF 'liboqs[.]so' <<<"$RPM_PRIVATE_NAMES"; then
  echo "ERROR: cannot derive the private library names of the bundle (no liboqs.so) — no .rpm is built"
  exit 1
fi
RPM_FILTERS="%global __provides_exclude_from ^/opt/cleona/.*\$"$'\n'
RPM_FILTERS="${RPM_FILTERS}%global __requires_exclude ^(${RPM_PRIVATE_NAMES})[(]"$'\n'

# THE PAYLOAD ARRIVES BYTE-IDENTICAL (S410-I6-MESSUNG, finding 1). After
# %install rpmbuild runs %__spec_install_post = %__debug_install_post (only
# with a debug package) + %__arch_install_post + %__os_install_post, and the
# latter runs brp-strip over every ELF file of the buildroot (rpm 4.18.2 on
# the build host: /usr/lib/rpm/macros `%__spec_install_post`,
# /usr/lib/rpm/platform/x86_64-linux/macros `%__os_install_post` =
# brp-compress, brp-elfperms, brp-strip, brp-strip-static-archive,
# brp-strip-comment-note, brp-remove-la-files). `dart build cli` writes the
# Dart runtime as an ELF file with the AOT snapshot APPENDED; strip rewrites
# only the ELF sections and drops the appendix. Measured: bin/cleona-daemon
# (23 375 656 B) and bin/cleona-ipc (7 621 896 B) both became the same
# 5 884 680 B bare dartaotruntime, and on Fedora 44 the daemon ended with
# "… is not an AOT snapshot, it cannot be run with 'dartaotruntime'", exit 255.
# The payload is the finished, gate-checked bundle, so nothing runs after
# %install:
#   * debug_package %{nil} — no debuginfo package, so find-debuginfo (which
#     strips as well) does not run: in rpm's macros `%debug_package` is what
#     sets `__debug_package`, and `%__spec_install_post` runs
#     `%{?__debug_package:%{__debug_install_post}}` (same file as above).
#   * __os_install_post %{nil} — none of the brp-* steps (also the distro
#     additions on a Fedora build host, which redefine this macro).
#   * __strip /bin/true — any remaining caller of %{__strip} changes nothing.
# Checked after the build below: the payload against the bundle, file by file.
RPM_FILTERS="${RPM_FILTERS}%global debug_package %{nil}"$'\n'
RPM_FILTERS="${RPM_FILTERS}%global __os_install_post %{nil}"$'\n'
RPM_FILTERS="${RPM_FILTERS}%global __strip /bin/true"$'\n'

# Spec file
cat > "$RPM_BUILD/SPECS/${APP_NAME}.spec" << EOF
${RPM_FILTERS}
Name:           $APP_NAME
Version:        $VERSION
Release:        1
Summary:        $DISPLAY_NAME - $DESCRIPTION
License:        Proprietary
URL:            $HOMEPAGE
Source0:        %{name}-%{version}.tar.gz
${RPM_DEPS}
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
%defattr(-,root,root,-)
/opt/cleona/
/usr/bin/cleona-chat
/usr/share/applications/cleona-chat.desktop
/usr/share/icons/hicolor/256x256/apps/cleona-chat.png

%changelog
EOF

# Build
if command -v rpmbuild &> /dev/null; then
  rpmbuild --define "_topdir $RPM_BUILD" -bb "$RPM_BUILD/SPECS/${APP_NAME}.spec" 2>/dev/null
  RPM_FILE=$(find "$RPM_BUILD/RPMS" -name "*.rpm" | head -1)
  if [ -n "$RPM_FILE" ]; then
    # Check of the BUILT package, not of the spec (finding 1): unpack the
    # payload and compare every entry under opt/cleona with the bundle —
    # same names, same bytes (sha256), same symlink targets. Plus owner
    # root/root and no group/other write for every entry (rpm -qp --dump:
    # path size mtime digest mode owner group …). A finding removes the
    # package from BOTH places — release-build.sh collects *.rpm from
    # anywhere under build/packages.
    rpm_inventory() { # directory -> "path sha256" / "path -> target", sorted
      (cd "$1" && find . \( -type f -o -type l \) -print0 | sort -z |
        while IFS= read -r -d '' p; do
          if [ -L "$p" ]; then printf '%s -> %s\n' "$p" "$(readlink "$p")"
          else printf '%s %s\n' "$p" "$(sha256sum < "$p" | cut -d' ' -f1)"; fi
        done)
    }
    RPM_CHECK_DIR=$(mktemp -d)
    RPM_BAD=""
    if ! (cd "$RPM_CHECK_DIR" && rpm2cpio "$RPM_FILE" | cpio -idm --quiet); then
      RPM_BAD="the payload cannot be unpacked (rpm2cpio | cpio)"
    elif [ ! -d "$RPM_CHECK_DIR/opt/cleona" ]; then
      RPM_BAD="the payload has no opt/cleona"
    else
      RPM_DIFF=$(diff <(rpm_inventory "$BUNDLE_DIR") <(rpm_inventory "$RPM_CHECK_DIR/opt/cleona")) \
        || RPM_BAD="payload differs from the bundle (< bundle, > rpm):"$'\n'"$(printf '%s\n' "$RPM_DIFF" | head -20)"
    fi
    RPM_MODES=$(rpm -qp --dump "$RPM_FILE" 2>/dev/null | awk '
      { mode = substr($5, length($5) - 2) }
      $6 != "root" || $7 != "root" { print; next }
      $5 !~ /^0120/ && (substr(mode, 2, 1) ~ /[2367]/ || substr(mode, 3, 1) ~ /[2367]/) { print }')
    [ -z "$RPM_MODES" ] || RPM_BAD="${RPM_BAD:+$RPM_BAD$'\n'}entries not root/root or writable for group/others:"$'\n'"$(printf '%s\n' "$RPM_MODES" | head -20)"
    rm -rf "$RPM_CHECK_DIR"
    if [ -n "$RPM_BAD" ]; then
      echo "ERROR: the .rpm is not the bundle — removed:"
      printf '%s\n' "$RPM_BAD"
      rm -rf "$RPM_BUILD/RPMS"
      rm -f "$OUTPUT_DIR/$(basename "$RPM_FILE")"
      exit 1
    fi
    cp "$RPM_FILE" "$OUTPUT_DIR/"
    echo "  OK: $OUTPUT_DIR/$(basename "$RPM_FILE") (payload byte-identical with the bundle, owner root/root — checked)"
  else
    echo "ERROR: rpmbuild produced no package"
    exit 1
  fi
else
  echo "  WARNING: rpmbuild not installed — spec file prepared"
  echo "  Install: sudo apt install rpm"
fi

# ============================================================
# Zusammenfassung
# ============================================================
echo ""
echo "=== Done ==="
echo "Packages in: $OUTPUT_DIR/"
ls -lh "$OUTPUT_DIR"/*.{AppImage,deb,rpm} 2>/dev/null || echo "(Some formats could not be built — see warnings above)"
echo ""
echo "Next steps:"
echo "  1. Test packages (install on a clean VM)"
echo "  2. Signieren: echo -n 'SHA256HASH' | openssl pkeyutl -sign -inkey /home/claude/CleonaPrivat/keys/cleona_maintainer_private.pem -rawin -out sig.bin"
echo "  3. GitHub Release: gh release create v$VERSION --title 'Cleona Chat v$VERSION' $OUTPUT_DIR/*"
