#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 simonlinuxcraft
#
# kyber-self-install.sh - desktop integration for the AppImage: a copy in
# ~/Applications, the menu entry, icons and the qrc:// handler for the EA login.
#
# The launcher asks once and runs this file with KYBER_SELF_INSTALL=yes or no.
# AppRun sources it on every start without that variable; then it only
# refreshes an existing install when the AppImage changed. Nothing happens
# without $APPIMAGE or with $KYBER_NO_AUTO_INSTALL (packages, CI).
#
# Sourced under `set -e`, so every error has to stay inside the function.
_kyber_self_install_main() {
    [ -z "${APPIMAGE:-}" ] && return 0
    [ -n "${KYBER_NO_AUTO_INSTALL:-}" ] && return 0
    [ ! -f "$APPIMAGE" ] && return 0

    local current_id
    current_id="$(stat -c '%s-%Y' "$APPIMAGE" 2>/dev/null)" || return 0
    [ -z "$current_id" ] && return 0

    local state_dir="$HOME/.local/share/kyber-linuxport"
    local marker="$state_dir/.installed-version"
    local declined_marker="$state_dir/.declined-version"

    if [ -f "$marker" ]; then
        [ "$(cat "$marker" 2>/dev/null)" = "$current_id" ] && return 0
        _kyber_self_install_run "$current_id" 1
        return 0
    fi

    case "${KYBER_SELF_INSTALL:-}" in
        yes) _kyber_self_install_run "$current_id" 0 ;;
        no) mkdir -p "$state_dir" && echo "$current_id" > "$declined_marker" ;;
    esac
}

_kyber_self_install_run() {
    local current_id="$1"
    local is_update="$2"

    local apps_dir="$HOME/Applications"
    local appimage_dst="$apps_dir/KyberLinuxPort-x86_64.AppImage"
    local extract_dir="$apps_dir/KyberLinuxPort.extracted"
    local desktop_dir="$HOME/.local/share/applications"
    local state_dir="$HOME/.local/share/kyber-linuxport"
    local marker="$state_dir/.installed-version"
    local declined_marker="$state_dir/.declined-version"

    mkdir -p "$apps_dir" "$desktop_dir" "$state_dir"

    # 1. Copy AppImage to ~/Applications/ if it isn't there yet.
    # Realpath-compare to handle the case where it's already at the target.
    # cp -p keeps the mtime, otherwise current_id (which is size-mtime of
    # the source) would mismatch the marker after copy and every restart
    # would look like a new update.
    local src_real dst_real
    src_real="$(readlink -f "$APPIMAGE" 2>/dev/null || echo "$APPIMAGE")"
    dst_real="$(readlink -f "$appimage_dst" 2>/dev/null || echo "$appimage_dst")"
    if [ "$src_real" != "$dst_real" ]; then
        cp -p "$APPIMAGE" "$appimage_dst" || return 1
        chmod +x "$appimage_dst" || true
    fi

    # 2. Re-extract for stable URL-handler paths. FUSE mount paths change
    # every run, so qrc:// and nxm:// .desktop files cannot point at $APPDIR.
    # KYBER_NO_AUTO_INSTALL=1 stops the extracted-and-run fallback on
    # FUSE3-only distros from triggering this hook recursively.
    #
    # Extract takes a few seconds on a 220 MB AppImage, so we keep a
    # marker file inside the extract dir. Same size+mtime as the
    # AppImage we'd extract? Then there's nothing to do. Without the
    # marker the same file launched from a path with a different mtime
    # would trigger a pointless re-extract.
    local extract_marker="$extract_dir/.kyber-extract-id"
    local dst_id
    dst_id="$(stat -c '%s-%Y' "$appimage_dst" 2>/dev/null)"
    if [ -n "$dst_id" ] \
       && [ -f "$extract_marker" ] \
       && [ "$(cat "$extract_marker" 2>/dev/null)" = "$dst_id" ]; then
        : # already up to date
    else
        # The extract takes a few seconds before the launcher shows up.
        [ "$is_update" = 1 ] && notify-send -i system-software-update \
            "Kyber (Linux Port)" "Applying update, one moment..." 2>/dev/null

        rm -rf "$extract_dir"
        (
            cd "$apps_dir" && KYBER_NO_AUTO_INSTALL=1 "$appimage_dst" --appimage-extract >/dev/null 2>&1
        ) || return 1
        mv "$apps_dir/squashfs-root" "$extract_dir" || return 1
        [ -n "$dst_id" ] && echo "$dst_id" > "$extract_marker"

        [ "$is_update" = 1 ] && notify-send -i emblem-default \
            "Kyber (Linux Port)" "Update applied" 2>/dev/null
    fi

    # 3. Install icons from the extracted AppDir.
    local size src dst
    for size in 16 24 32 48 64 96 128 192 256 512; do
        src="$extract_dir/usr/share/icons/hicolor/${size}x${size}/apps/kyber-linux.png"
        [ -f "$src" ] || continue
        dst="$HOME/.local/share/icons/hicolor/${size}x${size}/apps"
        mkdir -p "$dst"
        cp "$src" "$dst/kyber-linux.png"
    done
    if [ -f "$extract_dir/usr/share/icons/hicolor/scalable/apps/kyber-linux.svg" ]; then
        mkdir -p "$HOME/.local/share/icons/hicolor/scalable/apps"
        cp "$extract_dir/usr/share/icons/hicolor/scalable/apps/kyber-linux.svg" \
            "$HOME/.local/share/icons/hicolor/scalable/apps/kyber-linux.svg"
    fi

    # 4. Clean leftover .desktop files from previous installs (legacy names).
    rm -f \
        "$desktop_dir/kyber.desktop" \
        "$desktop_dir/kyber-bf2.desktop" \
        "$desktop_dir/kyber-linuxport-nxm.desktop" \
        "$desktop_dir/kyber-bf2-linuxport.desktop" \
        "$desktop_dir/kyber-bf2-linuxport-qrc.desktop" \
        "$desktop_dir/kyber-bf2-linuxport-nxm.desktop" \
        "$desktop_dir/kyber-nxm-handler.desktop" \
        "$desktop_dir/maxima-qrc.desktop"

    # 5. Write the main and qrc .desktop entries. The launcher writes its own
    # nxm/kl handler on every start, a second one here showed up twice in the
    # browser's "Open with" dialog.
    # Absolute icon path avoids Papirus/custom-theme fallthrough to a
    # generic placeholder when the bare icon name isn't carried by the theme.
    local icon_abs="$HOME/.local/share/icons/hicolor/256x256/apps/kyber-linux.png"
    local qrc_bin="$extract_dir/usr/bin/cli/maxima-bootstrap"

    cat > "$desktop_dir/kyber-linuxport.desktop" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=Kyber (Linux Port)
GenericName=Star Wars Battlefront II Mod Launcher
Comment=Unofficial Linux port of the Kyber mod launcher
Exec=env -u GIO_MODULE_DIR __GL_MaxFramesAllowed=1 $appimage_dst
Icon=$icon_abs
Terminal=false
Categories=Game;
StartupWMClass=kyber-linux
Keywords=BF2;Battlefront;Kyber;StarWars;
EOF
    cat >> "$desktop_dir/kyber-linuxport.desktop" <<'EOF'
Actions=open-logs;

[Desktop Action open-logs]
Name=Open Logs Folder
Exec=sh -c "xdg-open \\"\\$HOME/.local/share/kyber/launcher\\""
EOF

    cat > "$desktop_dir/kyber-linuxport-qrc.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Kyber QRC Handler
Comment=Receives qrc:// OAuth redirects for the Kyber EA login flow.
Exec=$qrc_bin %u
NoDisplay=true
Terminal=false
StartupNotify=false
MimeType=x-scheme-handler/qrc;
EOF

    # 6. Refresh caches and register MIME handlers.
    update-desktop-database "$desktop_dir" 2>/dev/null || true
    gtk-update-icon-cache -t -f "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
    # KDE Plasma menu cache, fail-soft, detached so we never block.
    (kbuildsycoca6 --noincremental || kbuildsycoca5 --noincremental) </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null || true
    xdg-mime default kyber-linuxport-qrc.desktop x-scheme-handler/qrc 2>/dev/null || true

    # 7. Persist marker, drop any stale "declined" marker.
    echo "$current_id" > "$marker"
    rm -f "$declined_marker"

    return 0
}

# Run, swallowing any errors so a broken self-install never blocks the app.
_kyber_self_install_main || true
unset -f _kyber_self_install_main _kyber_self_install_run
