#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 simonlinuxcraft
#
# uninstall-appimage.sh - Reverses install-appimage.sh.
# Keeps the Wine prefix (~/.local/share/maxima/) and game data intact.

set -euo pipefail

APPS_DIR="$HOME/Applications"
APPIMAGE="$APPS_DIR/KyberLinuxPort-x86_64.AppImage"
EXTRACT_DIR="$APPS_DIR/KyberLinuxPort.extracted"
DESKTOP_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"

echo "==> Removing AppImage and extracted copy"
rm -f "$APPIMAGE"
rm -rf "$EXTRACT_DIR"

echo "==> Removing .desktop entries (current and legacy names)"
rm -f \
  "$DESKTOP_DIR/kyber-linuxport.desktop" \
  "$DESKTOP_DIR/kyber-linuxport-qrc.desktop" \
  "$DESKTOP_DIR/kyber-linuxport-nxm.desktop" \
  "$DESKTOP_DIR/kyber-bf2-linuxport.desktop" \
  "$DESKTOP_DIR/kyber-bf2-linuxport-qrc.desktop" \
  "$DESKTOP_DIR/kyber-bf2-linuxport-nxm.desktop" \
  "$DESKTOP_DIR/kyber-bf2-nxm.desktop"

# The launcher writes its own nxm/kl handler on every start.
echo "==> Removing the launcher's nxm/kl handler script"
rm -f "$HOME/.local/share/kyber/bin/nxm_handler.sh"
rmdir "$HOME/.local/share/kyber/bin" 2>/dev/null || true

echo "==> Removing icons (all sizes, current and legacy names)"
for size in 16 24 32 48 64 96 128 192 256 512; do
  rm -f "$HOME/.local/share/icons/hicolor/${size}x${size}/apps/kyber-linux.png"
  rm -f "$HOME/.local/share/icons/hicolor/${size}x${size}/apps/kyber-bf2.png"
done
rm -f "$HOME/.local/share/icons/hicolor/scalable/apps/kyber-linux.svg"
rm -f "$HOME/.local/share/icons/hicolor/scalable/apps/kyber-bf2.svg"

echo "==> Refreshing desktop database"
update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
gtk-update-icon-cache -t -f "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

echo
echo "==> Done. Wine prefix at ~/.local/share/maxima/ kept (game data)."
