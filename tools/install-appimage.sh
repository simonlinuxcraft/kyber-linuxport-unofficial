#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 simonlinuxcraft
#
# install-appimage.sh - User-level installer for the Kyber Linux Port AppImage.
#
# What this does (all under $HOME, no sudo):
#   - Removes leftover .desktop files / icons from previous source-build
#     and old .deb installs.
#   - Copies tools/KyberLinuxPort-x86_64.AppImage to ~/Applications/.
#   - Extracts a static copy of the AppImage to ~/Applications/KyberLinuxPort.extracted/
#     so the qrc:// handler can point at a stable file path
#     (FUSE mountpoints are random per run and not suitable for handlers).
#   - Writes two .desktop files into ~/.local/share/applications/:
#       * kyber-linuxport.desktop      - main launcher
#       * kyber-linuxport-qrc.desktop  - qrc:// handler (EA login redirect)
#     The launcher writes its own nxm:// and kl:// handler on every start.
#   - Installs the icon, refreshes desktop database + icon cache.
#   - Wine prefix at ~/.local/share/maxima/wine/ is left untouched.
#
# Re-run safe (idempotent). To uninstall, run uninstall-appimage.sh.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$REPO_ROOT/tools"
APPIMAGE_SRC="$TOOLS/KyberLinuxPort-x86_64.AppImage"

APPS_DIR="$HOME/Applications"
APPIMAGE_DST="$APPS_DIR/KyberLinuxPort-x86_64.AppImage"
EXTRACT_DIR="$APPS_DIR/KyberLinuxPort.extracted"

DESKTOP_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"

if [ ! -x "$APPIMAGE_SRC" ]; then
  echo "ERROR: $APPIMAGE_SRC not found." >&2
  echo "Run tools/build-appimage.sh first." >&2
  exit 1
fi

echo "==> Removing leftover desktop entries from previous installs"
# Includes old kyber-bf2-* names retained for cleanup of older installs;
# new installs only emit kyber-linuxport-* entries.
rm -f \
  "$DESKTOP_DIR/kyber.desktop" \
  "$DESKTOP_DIR/kyber-bf2.desktop" \
  "$DESKTOP_DIR/kyber-linuxport-nxm.desktop" \
  "$DESKTOP_DIR/kyber-bf2-linuxport.desktop" \
  "$DESKTOP_DIR/kyber-bf2-linuxport-qrc.desktop" \
  "$DESKTOP_DIR/kyber-bf2-linuxport-nxm.desktop" \
  "$DESKTOP_DIR/kyber-nxm-handler.desktop" \
  "$DESKTOP_DIR/maxima-qrc.desktop" \
  "$HOME/Schreibtisch/Kyber.desktop" \
  "$HOME/Desktop/Kyber.desktop"

echo "==> Removing old icons (system-wide ones from .deb stay)"
for size in 16x16 24x24 32x32 48x48 64x64 96x96 128x128 192x192 256x256 512x512 scalable; do
  rm -f "$HOME/.local/share/icons/hicolor/$size/apps/kyber-bf2."{png,svg} 2>/dev/null || true
  rm -f "$HOME/.local/share/icons/hicolor/$size/apps/kyber-linux."{png,svg} 2>/dev/null || true
done

echo "==> Removing old user payload (cli/locale/module), keeping mods/ and launcher/"
# ~/.local/share/kyber/  - cli/, locale/, module/ get wiped for a clean
# install. mods/ and launcher/ are deliberately kept so an update does not
# drop the user's downloaded mods, plugins, mod collections or settings.
# Keep ~/.local/share/maxima/  - that's the live Wine prefix with game data.
kyber_data="$HOME/.local/share/kyber"
if [ -d "$kyber_data" ]; then
  find "$kyber_data" -mindepth 1 -maxdepth 1 ! -name mods ! -name launcher -exec rm -rf {} +
fi

echo "==> Installing AppImage to $APPS_DIR"
mkdir -p "$APPS_DIR"
cp "$APPIMAGE_SRC" "$APPIMAGE_DST"
chmod +x "$APPIMAGE_DST"

echo "==> Extracting static copy for URL handlers"
rm -rf "$EXTRACT_DIR"
cd "$APPS_DIR"
"$APPIMAGE_DST" --appimage-extract >/dev/null
mv squashfs-root "$EXTRACT_DIR"

# Sanity: confirm the bundled handler binaries are where we expect.
# Both live under usr/bin/cli/ in the Flutter bundle layout (cli/ is the
# subdir copied from build/linux/x64/release/bundle/cli/).
NXM_BIN="$EXTRACT_DIR/usr/bin/cli/bin/nxm_handler.sh"
QRC_BIN="$EXTRACT_DIR/usr/bin/cli/maxima-bootstrap"
[ ! -x "$NXM_BIN" ] && echo "WARN: nxm handler not bundled at $NXM_BIN" >&2
[ ! -x "$QRC_BIN" ] && echo "WARN: maxima-bootstrap not bundled at $QRC_BIN" >&2

echo "==> Installing Kyber icon (all sizes from extracted AppDir)"
for size in 16 24 32 48 64 96 128 192 256 512; do
  src="$EXTRACT_DIR/usr/share/icons/hicolor/${size}x${size}/apps/kyber-linux.png"
  [ -f "$src" ] || continue
  dst="$HOME/.local/share/icons/hicolor/${size}x${size}/apps"
  mkdir -p "$dst"
  cp "$src" "$dst/kyber-linux.png"
done
SVG_SRC="$EXTRACT_DIR/usr/share/icons/hicolor/scalable/apps/kyber-linux.svg"
if [ -f "$SVG_SRC" ]; then
  mkdir -p "$HOME/.local/share/icons/hicolor/scalable/apps"
  cp "$SVG_SRC" "$HOME/.local/share/icons/hicolor/scalable/apps/kyber-linux.svg"
fi

echo "==> Writing main launcher .desktop"
mkdir -p "$DESKTOP_DIR"
# Use the absolute icon path (not just the icon name): on systems with
# Papirus or other custom themes the bare 'kyber-linux' name often gets
# resolved against the active theme first, which doesn't carry our icon
# and falls back to a generic placeholder.
ICON_ABS="$HOME/.local/share/icons/hicolor/256x256/apps/kyber-linux.png"
cat > "$DESKTOP_DIR/kyber-linuxport.desktop" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=Kyber (Linux Port)
GenericName=Star Wars Battlefront II Mod Launcher
Comment=Unofficial Linux port of the Kyber mod launcher
Exec=env -u GIO_MODULE_DIR __GL_MaxFramesAllowed=1 $APPIMAGE_DST
Icon=$ICON_ABS
Terminal=false
Categories=Game;
StartupWMClass=kyber-linux
Keywords=BF2;Battlefront;Kyber;StarWars;
EOF

echo "==> Writing qrc:// handler .desktop (EA OAuth redirect)"
cat > "$DESKTOP_DIR/kyber-linuxport-qrc.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Kyber QRC Handler
Comment=Receives qrc:// OAuth redirects for the Kyber EA login flow.
Exec=$QRC_BIN %u
NoDisplay=true
Terminal=false
StartupNotify=false
MimeType=x-scheme-handler/qrc;
EOF

echo "==> Refreshing desktop and icon caches"
update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
gtk-update-icon-cache -t -f "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
xdg-mime default kyber-linuxport-qrc.desktop x-scheme-handler/qrc 2>/dev/null || true

echo
echo "==> Done"
echo
echo "Launcher:    $APPIMAGE_DST"
echo "Extracted:   $EXTRACT_DIR (used by the qrc handler; do not delete)"
echo "Menu entry:  $DESKTOP_DIR/kyber-linuxport.desktop"
echo
echo "If you also want to drop the old .deb residue (legacy package 'rc' state),"
echo "run manually:  sudo dpkg --purge kyber-bf2-linux  # legacy name only"
