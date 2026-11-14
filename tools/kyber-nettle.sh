#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 simonlinuxcraft
#
# kyber-nettle.sh - AppRun hook that adds the bundled nettle 3 on hosts that
# only ship nettle 4 (Arch, CachyOS, SteamOS 3.9+, Tumbleweed), see the nettle
# comment in build-appimage.sh. Only the 64-bit entries count, a lib32 nettle 3
# does not help the launcher.
_kyber_ldc="$( { ldconfig -p || /sbin/ldconfig -p; } 2>/dev/null )"
case "$_kyber_ldc" in *'libnettle.so.8 (libc6,x86-64'*) ;; *'libnettle.so.9 (libc6,x86-64'*)
    export LD_LIBRARY_PATH="$this_dir/usr/lib/nettle3${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ;;
esac
unset _kyber_ldc
