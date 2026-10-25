#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 simonlinuxcraft
#
# kyber-cachyos-hint.sh - AppRun hook that shows a one-shot zenity dialog on
# Arch-based systems if the optional GStreamer plugins for BF2 are missing.
#
# Sourced by AppRun before linuxdeploy-plugin-gtk.sh, so zenity uses the
# system GTK, not the bundled one.
#
# Stays out of the way on Ubuntu/Debian/Fedora (returns early when
# pacman is missing), and remembers what it already asked about via a
# marker file in ~/.local/share/kyber-linuxport/.
#
# Also adds the bundled nettle 3 on nettle-4.0-only hosts (Arch, CachyOS,
# SteamOS 3.9+), on any distro, see the nettle comment in build-appimage.sh.

_kyber_ldc="$( { ldconfig -p || /sbin/ldconfig -p; } 2>/dev/null )"
case "$_kyber_ldc" in *libnettle.so.8*) ;; *libnettle.so.9*)
    export LD_LIBRARY_PATH="$this_dir/usr/lib/nettle3${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ;;
esac
unset _kyber_ldc

_kyber_cachyos_hint_main() {
    [ -n "${KYBER_NO_CACHYOS_HINT:-}" ] && return 0
    [ ! -r /etc/os-release ] && return 0

    # Read ID/ID_LIKE without leaking them into the launcher env.
    local id id_like
    id="$(. /etc/os-release 2>/dev/null && printf '%s' "${ID:-}")"
    id_like="$(. /etc/os-release 2>/dev/null && printf '%s' "${ID_LIKE:-}")"

    # SteamOS is Arch-based (ID=steamos, ID_LIKE=arch) but has a read-only,
    # immutable root where "sudo pacman -S" is not actionable: it needs
    # steamos-readonly disable, the pacman keyring is not initialised, and any
    # package installed that way is wiped on the next SteamOS image update.
    # Showing the pacman hint there is misleading, so skip it. Steam Deck gets
    # its own guidance from kyber-steamdeck-hint.sh.
    [ "$id" = "steamos" ] && return 0

    # CachyOS/Manjaro/EndeavourOS report ID_LIKE=arch, vanilla Arch
    # reports ID=arch. Anything else is not our concern here.
    local is_arch=0
    [ "$id" = "arch" ] && is_arch=1
    [ "$id" = "cachyos" ] && is_arch=1
    [ "$id" = "manjaro" ] && is_arch=1
    [ "$id" = "endeavouros" ] && is_arch=1
    case " $id_like " in *' arch '*) is_arch=1 ;; esac
    [ "$is_arch" = 0 ] && return 0

    command -v pacman >/dev/null 2>&1 || return 0

    # winegstreamer pulls bad/ugly/libav for the Origin login splash.
    # vulkan-tools ships vulkaninfo, which users run when sending bug
    # reports.
    local pkg missing=()
    for pkg in gst-plugins-bad gst-plugins-ugly gst-libav vulkan-tools; do
        pacman -Qq "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
    done

    [ "${#missing[@]}" -eq 0 ] && return 0

    local state_dir="$HOME/.local/share/kyber-linuxport"
    local marker="$state_dir/.cachyos-hint-shown"
    # Marker stores the exact set we last prompted about. If the user
    # changes their package set (install one, remove another) we ask again.
    local current_set
    current_set="$(printf '%s\n' "${missing[@]}" | sort | tr '\n' ' ' | sed 's/ $//')"
    if [ -f "$marker" ] && [ "$(cat "$marker" 2>/dev/null)" = "$current_set" ]; then
        return 0
    fi

    # Need a graphical dialog. Headless setups skip silently, the launcher
    # still starts.
    command -v zenity >/dev/null 2>&1 || command -v kdialog >/dev/null 2>&1 || return 0

    local install_cmd="sudo pacman -S --needed ${current_set}"
    local title="Kyber (Linux Port)"
    local body
    body="$(printf 'Some optional Arch packages are missing:\n\n%s\n\nThe launcher still works without them, but BF2 may show a static logo instead of the Origin login splash. vulkan-tools is only needed if you want to send bug reports with vulkaninfo output.\n\nTo install, run in a terminal:\n\n%s' "$current_set" "$install_cmd")"

    if command -v zenity >/dev/null 2>&1; then
        LC_ALL=C.UTF-8 LANGUAGE=en zenity --info --no-wrap --title="$title" --text="$body" 2>/dev/null || true
    else
        LC_ALL=C.UTF-8 LANGUAGE=en kdialog --title "$title" --msgbox "$body" 2>/dev/null || true
    fi

    mkdir -p "$state_dir"
    printf '%s' "$current_set" > "$marker"
    return 0
}

_kyber_cachyos_hint_main || true
unset -f _kyber_cachyos_hint_main
