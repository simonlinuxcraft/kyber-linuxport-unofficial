#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 simonlinuxcraft
#
# kyber-self-install.sh - AppRun hook that registers desktop integration on
# first start and refreshes it when the AppImage version changes.
#
# Sourced by AppRun BEFORE linuxdeploy-plugin-gtk.sh, so dialog tools
# (zenity/kdialog) load against the system GTK and not the bundled one.
#
# This hook is a no-op when:
#   - $APPIMAGE is unset (e.g. running --appimage-extract-and-run)
#   - $KYBER_NO_AUTO_INSTALL is set (CI / packaging contexts)
#   - the marker file already matches the current AppImage's size+mtime
#
# Behaviour matrix:
#   first start, no marker        → ask user (zenity), install on confirm
#   marker present, ID matches    → no-op (fast path)
#   marker present, ID differs    → silent re-install (force update)
#   user declines first dialog    → write "declined" marker, don't ask again
#                                    until version changes

# Defensive: this hook is sourced under `set -e`. Any unexpected error must
# not break the launcher. Wrap everything in a function and trap.
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

    # Fast path: already installed for this exact AppImage.
    if [ -f "$marker" ] && [ "$(cat "$marker" 2>/dev/null)" = "$current_id" ]; then
        return 0
    fi

    # User previously declined for this exact AppImage - don't pester.
    if [ -f "$declined_marker" ] && [ "$(cat "$declined_marker" 2>/dev/null)" = "$current_id" ]; then
        return 0
    fi

    local is_update=0
    [ -f "$marker" ] && is_update=1

    # Confirm dialog - only on first install, not on version updates
    # (updates are silent, the user already opted in once).
    if [ "$is_update" = 0 ]; then
        local prompt_title="Kyber (Linux Port)"
        local prompt_text="Register Kyber as an application?\n\nAdds Kyber to the application menu, installs the icon, and registers the qrc:// and nxm:// URL handlers for EA login and Nexus Mods.\n\nThe AppImage will be copied to ~/Applications/.\n\nCan be uninstalled at any time."
        local user_choice=1

        # Force English locale for the dialog so Yes/No buttons match the
        # English prompt text on non-English systems (German testers were
        # seeing "Ja/Nein" while the body was already English-only).
        if command -v zenity >/dev/null 2>&1; then
            LC_ALL=C.UTF-8 LANGUAGE=en zenity --question --no-wrap --title="$prompt_title" --text="$prompt_text" 2>/dev/null && user_choice=0
        elif command -v kdialog >/dev/null 2>&1; then
            LC_ALL=C.UTF-8 LANGUAGE=en kdialog --title "$prompt_title" --yesno "$(printf '%b' "$prompt_text")" 2>/dev/null && user_choice=0
        else
            # Headless / minimal systems without zenity or kdialog: auto-install
            # with an stderr notice. Mint/GNOME/KDE installs practically always
            # ship one of the two.
            echo "kyber-self-install: no zenity/kdialog found, installing automatically" >&2
            user_choice=0
        fi

        if [ "$user_choice" != 0 ]; then
            mkdir -p "$state_dir"
            echo "$current_id" > "$declined_marker"
            return 0
        fi
    fi

    _kyber_self_install_run "$current_id" "$is_update" || return 0
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
        # The extract is slow enough that without a heads-up the launcher
        # looks frozen for a few seconds.
        notify-send -i system-software-update \
            "Kyber (Linux Port)" \
            "Applying update, one moment..." 2>/dev/null || true

        rm -rf "$extract_dir"
        (
            cd "$apps_dir" && KYBER_NO_AUTO_INSTALL=1 "$appimage_dst" --appimage-extract >/dev/null 2>&1
        ) || return 1
        mv "$apps_dir/squashfs-root" "$extract_dir" || return 1
        [ -n "$dst_id" ] && echo "$dst_id" > "$extract_marker"

        notify-send -i emblem-default \
            "Kyber (Linux Port)" \
            "Update applied" 2>/dev/null || true
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

    # 8. First install gets a passive notification. Updates stay silent
    # here - the user already saw "Applying update / Update applied"
    # earlier in this run.
    if [ "$is_update" = 0 ] && command -v notify-send >/dev/null 2>&1; then
        notify-send --icon="$icon_abs" \
            "Kyber (Linux Port)" \
            "Added to your applications." 2>/dev/null || true
    fi

    return 0
}

# Run, swallowing any errors so a broken self-install never blocks the app.
_kyber_self_install_main || true
unset -f _kyber_self_install_main _kyber_self_install_run
