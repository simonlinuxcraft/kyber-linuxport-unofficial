#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 simonlinuxcraft
#
# build-appimage.sh - Bundle the Flutter Linux release build into a
# self-contained AppImage for the Kyber Linux Port.
#
# Prerequisites:
#   - flutter build linux --release  (run beforehand)
#   - tools/linuxdeploy-x86_64.AppImage
#   - tools/linuxdeploy-plugin-gtk.sh
#   - tools/appimagetool-x86_64.AppImage
#
# Output:
#   tools/KyberLinuxPort-x86_64.AppImage
#   tools/<AUR pkgver>.tar.xz (AUR source, e.g. 7.0.0_beta10.tar.xz)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$REPO_ROOT/tools"
LAUNCHER_BUNDLE="$REPO_ROOT/Kyber/Launcher/build/linux/x64/release/bundle"
APPDIR="$TOOLS/KyberLinuxPort.AppDir"
OUTPUT="$TOOLS/KyberLinuxPort-x86_64.AppImage"

SOURCE_URL="https://github.com/simonlinuxcraft/kyber-linuxport-unofficial"

if [ ! -x "$LAUNCHER_BUNDLE/kyber_launcher" ]; then
  echo "ERROR: $LAUNCHER_BUNDLE/kyber_launcher not found." >&2
  echo "Run 'flutter build linux --release' from Kyber/Launcher first." >&2
  exit 1
fi

# The port builds against the master channel, so an unnoticed `flutter upgrade`
# can swap engine defaults underneath us. That is how Impeller became the
# renderer in 6.4.12. Warn only, never block.
FLUTTER_PIN_FILE="$TOOLS/flutter-revision"
if [ -r "$FLUTTER_PIN_FILE" ] && command -v flutter >/dev/null 2>&1; then
  flutter_root="$(dirname "$(dirname "$(readlink -f "$(command -v flutter)")")")"
  pinned="$(tr -d '[:space:]' < "$FLUTTER_PIN_FILE")"
  current="$(git -C "$flutter_root" rev-parse HEAD 2>/dev/null || true)"
  if [ -n "$current" ] && [ "$current" != "$pinned" ]; then
    echo "WARNING: Flutter SDK is at $current" >&2
    echo "         tools/flutter-revision pins $pinned" >&2
    echo "         Engine defaults may differ from the tested build. To match it:" >&2
    echo "         git -C $flutter_root checkout $pinned" >&2
  fi
fi

echo "==> Cleaning previous AppDir"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share/applications" \
  "$APPDIR/usr/share/doc/kyber-linux"

echo "==> Copying Flutter bundle into AppDir/usr/"
cp -a "$LAUNCHER_BUNDLE/." "$APPDIR/usr/bin/"

echo "==> Copying licenses + GPL §6 source-availability marker"
cp "$REPO_ROOT/Kyber/LICENSE" "$APPDIR/usr/share/doc/kyber-linux/LICENSE"
cp "$REPO_ROOT/Kyber/NOTICE.md" "$APPDIR/usr/share/doc/kyber-linux/NOTICE.md"
cp "$REPO_ROOT/CHANGELOG.md" "$APPDIR/usr/share/doc/kyber-linux/CHANGELOG.md"
cat > "$APPDIR/usr/share/doc/kyber-linux/source-url.txt" <<EOF
Kyber Linux Port - Corresponding Source (GPLv3 §6(d))

The full corresponding source code for this AppImage is available at:

  $SOURCE_URL

The exact commit / tag matching this AppImage is identified in the
release page of that repository, alongside this binary.

For the wine-helper.exe binary embedded in this AppImage, see
https://github.com/simonlinuxcraft/kyber/blob/ver/beta10/CLI/cli_payload/README.md
which carries the GPLv3 §6(b) written offer.
EOF

echo "==> Generating .desktop file"
cat > "$APPDIR/usr/share/applications/kyber-linux.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Version=1.0
Name=Kyber (Linux Port)
GenericName=Star Wars Battlefront II Mod Launcher
Comment=Unofficial Linux port of the Kyber mod launcher
Exec=kyber_launcher
Icon=kyber-linux
Terminal=false
Categories=Game;
StartupWMClass=kyber-linux
Keywords=BF2;Battlefront;Kyber;StarWars;
Actions=open-logs;

[Desktop Action open-logs]
Name=Open Logs Folder
Exec=sh -c "xdg-open \\"\\$HOME/.local/share/kyber/launcher\\""
EOF

echo "==> Placing Kyber Linux Port icon (rendered from SVG)"
# The port has its own icon (Tux in the Kyber hexagon) so it is not mixed up
# with the Windows launcher. Multiple raster sizes plus the SVG go
# into the AppDir so desktop environments can pick the cleanest one.
LOGO_SVG="$REPO_ROOT/assets/kyber-linux-port-icon.svg"
if [ ! -f "$LOGO_SVG" ]; then
  echo "ERROR: Icon SVG not found at $LOGO_SVG" >&2
  exit 1
fi
if ! command -v rsvg-convert >/dev/null; then
  echo "ERROR: rsvg-convert (librsvg2-bin) is required to render the icon." >&2
  exit 1
fi
if ! command -v convert >/dev/null; then
  echo "ERROR: ImageMagick (convert) is required to pad icons to square." >&2
  exit 1
fi
for size in 16 24 32 48 64 96 128 192 256 512; do
  mkdir -p "$APPDIR/usr/share/icons/hicolor/${size}x${size}/apps"
  # --keep-aspect-ratio keeps a non-square SVG from being stretched, then
  # ImageMagick pads the result with transparency back up to a square that
  # linuxdeploy will accept.
  rsvg-convert -w "$size" -h "$size" --keep-aspect-ratio "$LOGO_SVG" \
    | convert - -background none -gravity center -extent "${size}x${size}" \
        "$APPDIR/usr/share/icons/hicolor/${size}x${size}/apps/kyber-linux.png"
done
mkdir -p "$APPDIR/usr/share/icons/hicolor/scalable/apps"
cp "$LOGO_SVG" "$APPDIR/usr/share/icons/hicolor/scalable/apps/kyber-linux.svg"
# linuxdeploy and appimagetool expect the desktop-icon at the AppDir root.
# The 256 raster works as the canonical .DirIcon.
cp "$APPDIR/usr/share/icons/hicolor/256x256/apps/kyber-linux.png" \
  "$APPDIR/kyber-linux.png"

echo "==> Running linuxdeploy with GTK plugin"
cd "$TOOLS"
export NO_STRIP=1
export DEPLOY_GTK_VERSION=3
./linuxdeploy-x86_64.AppImage --appdir "$APPDIR" \
  --executable "$APPDIR/usr/bin/kyber_launcher" \
  --desktop-file "$APPDIR/usr/share/applications/kyber-linux.desktop" \
  --icon-file "$APPDIR/kyber-linux.png" \
  --plugin gtk

# linuxdeploy-plugin-gtk copies the whole girepository-1.0 typelib dir from the
# build host. If libwebkit2gtk-4.1-dev is installed there, the WebKit/JSC
# typelibs come along even though nothing loads them (webkit was dropped from
# this build). Strip them so no webkit artifact ships in the AppImage.
rm -f "$APPDIR"/usr/lib/girepository-1.0/WebKit*.typelib \
      "$APPDIR"/usr/lib/girepository-1.0/JavaScriptCore*.typelib 2>/dev/null || true

# linuxdeploy bundles the gnutls TLS cluster (libgnutls/libnettle/libhogweed),
# pulled in transitively by ffmpeg/media_kit (libavformat -> librtmp/libsrt) and
# by cups/ldap. The bundled hogweed/nettle is older than what rolling distros
# ship. On SteamOS a system component loads the newer system libgnutls.so.30,
# which then binds against our older bundled libhogweed already in the namespace
# and aborts at startup with:
#   undefined symbol: nettle_rsa_oaep_sha384_decrypt, version HOGWEED_6
# Drop these three so the whole chain comes from the system, self-consistent.
#
# The price is that the host must provide the SONAMEs the bundled consumers were
# linked against: libnettle.so.8 (libarchive, librtmp, libsrt-gnutls),
# libhogweed.so.6 (librtmp) and libgnutls.so.30 (libavformat, libcups, libldap).
# The glibc baseline says nothing about those, the nettle SONAME is versioned
# independently of glibc. Debian, Ubuntu, Fedora and SteamOS up to 3.8 ship
# nettle 3.x and have them.
#
# The whole chain hangs off libmpv (the first-start intro video); nothing else
# bundled pulls libarchive or the ffmpeg cluster in.
#
# Do not "fix" this by bundling the libraries into usr/lib again. That brings
# the SteamOS HOGWEED_6 abort back.
rm -f "$APPDIR"/usr/lib/libgnutls.so.* \
      "$APPDIR"/usr/lib/libhogweed.so.* \
      "$APPDIR"/usr/lib/libnettle.so.* 2>/dev/null || true

# Rolling Arch, CachyOS and SteamOS 3.9+ moved to nettle 4.0, which installs
# libnettle.so.9/libhogweed.so.7 only, so the launcher dies there with
# "libnettle.so.8: cannot open shared object file". Ship the build host's nettle
# 3 (the version the consumers were linked against) outside the RUNPATH, in
# usr/lib/nettle3. tools/kyber-nettle.sh puts it on LD_LIBRARY_PATH only
# when the host has libnettle.so.9 and no libnettle.so.8. Then no system library
# uses the .so.8/.so.6 SONAMEs, so nothing can bind against our copy.
mkdir -p "$APPDIR/usr/lib/nettle3"
for _nl in libnettle.so.8 libhogweed.so.6; do
  _src="$(ldconfig -p 2>/dev/null | awk -v n="$_nl" '$1==n && /x86-64/ && !f{print $NF; f=1}' || true)"
  [ -n "$_src" ] && [ -f "$_src" ] && cp -L "$_src" "$APPDIR/usr/lib/nettle3/$_nl"
  [ -f "$APPDIR/usr/lib/nettle3/$_nl" ] || { echo "ERROR: $_nl not found on the build host" >&2; exit 1; }
done

# Bundle libjack. media_kit's libmpv/libavdevice were built with JACK output
# support, so they hard-NEED libjack.so.0, but JACK is not installed by default
# on any consumer distro (the dev box had it, which masked the gap). linuxdeploy
# leaves it out via its excludelist, so a fresh Ubuntu/Fedora/Arch fails to start
# with "libjack.so.0: cannot open shared object file". Pull it in plus its libdb
# dep, RUNPATH=$ORIGIN so the bundled libjack finds the bundled libdb beside it.
echo "==> Bundling libjack (+libdb) for hosts without JACK"
for _jl in libjack.so.0 libdb-5.3.so; do
  _src="$(ldconfig -p 2>/dev/null | awk -v n="$_jl" '$1==n && !f{print $NF; f=1}')"
  [ -n "$_src" ] && [ -f "$_src" ] && cp -L "$_src" "$APPDIR/usr/lib/$_jl"
done
[ -f "$APPDIR/usr/lib/libjack.so.0" ] && patchelf --set-rpath '$ORIGIN' "$APPDIR/usr/lib/libjack.so.0" 2>/dev/null || true

# Drop the AVIF gdk-pixbuf loader. It hard-NEEDs libavif plus a large AV1 codec
# stack (dav1d/aom/rav1e/SvtAv1/gav1/abseil) that linuxdeploy did not bundle, so
# on a system without libavif the loader cannot load. The launcher's UI uses no
# AVIF images, so remove the loader instead of bundling ~25 extra libraries. The
# AppRun hook regenerates loaders.cache at runtime, so it simply won't be listed.
rm -f "$APPDIR"/usr/lib/libpixbufloader-avif.so \
      "$APPDIR"/usr/lib/gdk-pixbuf-2.0/*/loaders/libpixbufloader-avif.so 2>/dev/null || true
# With the AVIF loader gone, libavif itself is orphaned (nothing else bundled
# NEEDs it). Drop it too. Verified: no bundled .so has libavif in its NEEDED.
rm -f "$APPDIR"/usr/lib/libavif.so.* 2>/dev/null || true

echo "==> Patching GTK AppRun hook with runtime loaders.cache regen"
# linuxdeploy regenerates apprun-hooks/linuxdeploy-plugin-gtk.sh on every
# run, dropping any manual edits. The default hook ships a loaders.cache
# with relative module names ("libpixbufloader-svg.so"), which fails to
# resolve at runtime - GTK then aborts when it tries to render a fallback
# image-missing.svg from a system icon theme (e.g. Papirus on Mint).
# Append a runtime regen block guarded by a sentinel so it survives
# rebuilds (linuxdeploy's freshly-written hook lacks the sentinel, so the
# block gets re-appended each time).
GTK_HOOK="$APPDIR/apprun-hooks/linuxdeploy-plugin-gtk.sh"
if [ -f "$GTK_HOOK" ] && ! grep -q "KYBER_PIXBUF_LOADERS_RUNTIME" "$GTK_HOOK"; then
cat >> "$GTK_HOOK" <<'HOOKEOF'

# KYBER_PIXBUF_LOADERS_RUNTIME - regenerate loaders.cache with absolute
# paths into a writable tmpdir; the AppDir's bundled cache has relative
# module names which GdkPixbuf cannot resolve at runtime.
_kyber_gdk_query="$APPDIR/usr/lib/gdk-pixbuf-2.0/gdk-pixbuf-query-loaders"
_kyber_gdk_loader_dir="$APPDIR/usr/lib/gdk-pixbuf-2.0/2.10.0/loaders"
if [ -x "$_kyber_gdk_query" ] && [ -d "$_kyber_gdk_loader_dir" ]; then
    _kyber_gdk_cache_dir="$(mktemp -d)"
    GDK_PIXBUF_MODULEDIR="$_kyber_gdk_loader_dir" "$_kyber_gdk_query" \
        > "$_kyber_gdk_cache_dir/loaders.cache" 2>/dev/null || true
    export GDK_PIXBUF_MODULE_FILE="$_kyber_gdk_cache_dir/loaders.cache"
    unset _kyber_gdk_cache_dir
fi
unset _kyber_gdk_query _kyber_gdk_loader_dir
HOOKEOF
fi

# Native Wayland opt-in: linuxdeploy-plugin-gtk hardcodes GDK_BACKEND=x11
# (forces XWayland) because the Flutter-GTK Wayland backend can crash. Soften it
# to a fallback so users can `export GDK_BACKEND=wayland` for smoother native
# Wayland; x11 stays the default. Only the regenerated AppDir copy is patched,
# the linuxdeploy template is untouched. Idempotent (the patched line no longer
# matches the pattern).
if [ -f "$GTK_HOOK" ]; then
  sed -i 's/^export GDK_BACKEND=x11.*/export GDK_BACKEND="${GDK_BACKEND:-x11}"/' "$GTK_HOOK"
fi

echo "==> Bundling SVG pixbuf loader (linuxdeploy-plugin-gtk skips it)"
# linuxdeploy-plugin-gtk pulls in PNG/JPEG/etc pixbuf loaders but not the
# SVG one because librsvg is an extra dep chain. GTK falls back to
# image-missing.svg from the system icon theme on missing assets, which
# crashes the launcher with "Unable to load image-loading module:
# libpixbufloader-svg.so". Bundle the loader, its deps, and the query-loaders
# binary (needed to regenerate loaders.cache at runtime with the correct
# absolute FUSE mount path - loaders.cache paths must be absolute).
SYS_LOADERS=/usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0/2.10.0/loaders
GDK_QUERY_LOADERS=/usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0/gdk-pixbuf-query-loaders
APPDIR_LOADERS="$APPDIR/usr/lib/gdk-pixbuf-2.0/2.10.0/loaders"

if [ ! -f "$SYS_LOADERS/libpixbufloader-svg.so" ]; then
  echo "ERROR: $SYS_LOADERS/libpixbufloader-svg.so not found." >&2
  echo "Install librsvg2-common, or update the path after a gdk-pixbuf ABI bump." >&2
  exit 1
fi

if [ ! -f "$APPDIR_LOADERS/libpixbufloader-svg.so" ]; then
  cp "$SYS_LOADERS/libpixbufloader-svg.so" "$APPDIR_LOADERS/"
  for lib in librsvg-2.so.2 libxml2.so.2 libpangocairo-1.0.so.0 libpango-1.0.so.0 libpangoft2-1.0.so.0; do
    src="/lib/x86_64-linux-gnu/$lib"
    [ ! -f "$src" ] && src="/usr/lib/x86_64-linux-gnu/$lib"
    [ ! -e "$APPDIR/usr/lib/$lib" ] && [ -f "$src" ] && cp -L "$src" "$APPDIR/usr/lib/" || true
  done
fi

# The SVG loader's RUNPATH is $ORIGIN (its own loaders/ dir), but its NEEDED
# librsvg-2.so.2 sits three levels up in usr/lib. With only $ORIGIN, the loader
# resolves librsvg from the system; on a minimal distro without system librsvg
# it silently fails and GTK aborts on the first image-missing.svg fallback. Add
# usr/lib to the loader's RUNPATH so the bundled librsvg is found there too.
if [ -f "$APPDIR_LOADERS/libpixbufloader-svg.so" ]; then
  patchelf --set-rpath '$ORIGIN:$ORIGIN/../../../' \
    "$APPDIR_LOADERS/libpixbufloader-svg.so" 2>/dev/null || true
fi

# linuxdeploy plus the manual copy above can leave librsvg as several identical
# real files (librsvg-2.so, librsvg-2.so.2, librsvg-2.so.<ver>). Collapse the
# aliases to symlinks onto the SONAME file (librsvg-2.so.2, the name consumers
# NEED) to drop the duplicate inodes. Keep the SONAME file as the real one.
if [ -f "$APPDIR/usr/lib/librsvg-2.so.2" ] && [ ! -L "$APPDIR/usr/lib/librsvg-2.so.2" ]; then
  for _rsvg_alias in "$APPDIR"/usr/lib/librsvg-2.so "$APPDIR"/usr/lib/librsvg-2.so.2.*; do
    [ -f "$_rsvg_alias" ] && [ ! -L "$_rsvg_alias" ] && \
      ln -sf librsvg-2.so.2 "$_rsvg_alias"
  done
fi

# Bundle gdk-pixbuf-query-loaders so the AppRun hook can regenerate
# loaders.cache at startup with the real $APPDIR (= FUSE mount point).
# GDK-Pixbuf requires absolute paths in loaders.cache - relative paths
# silently fail because the library prefixes them with the process cwd,
# not with the FUSE mount root. The FUSE mount path is only known at
# runtime, so the cache must be written then, not at build time.
mkdir -p "$APPDIR/usr/lib/gdk-pixbuf-2.0"
[ ! -f "$APPDIR/usr/lib/gdk-pixbuf-2.0/gdk-pixbuf-query-loaders" ] && \
  cp "$GDK_QUERY_LOADERS" "$APPDIR/usr/lib/gdk-pixbuf-2.0/gdk-pixbuf-query-loaders"

echo "==> Bundling Kyber self-install AppRun hook"
# kyber-self-install.sh keeps the desktop integration of the AppImage current.
# It runs BEFORE the GTK hook, so the host tools it calls do not pick up the
# bundled GTK.
cp "$TOOLS/kyber-self-install.sh" "$APPDIR/apprun-hooks/kyber-self-install.sh"
chmod +x "$APPDIR/apprun-hooks/kyber-self-install.sh"

echo "==> Bundling Kyber backend-pref AppRun hook"
# kyber-backend-pref.sh applies the in-app "Native Wayland" toggle. Runs BEFORE
# the GTK hook so its GDK_BACKEND="${GDK_BACKEND:-x11}" keeps whatever we export.
cp "$TOOLS/kyber-backend-pref.sh" "$APPDIR/apprun-hooks/kyber-backend-pref.sh"
chmod +x "$APPDIR/apprun-hooks/kyber-backend-pref.sh"

echo "==> Bundling xdg-user-dir fallback"
# path_provider asks xdg-user-dir for the documents folder, and the launcher
# stops before its first window without an answer. Minimal window-manager
# setups do not always ship xdg-user-dirs; AppRun appends this copy to PATH
# only when the host has none.
mkdir -p "$APPDIR/usr/lib/kyber-fallback-bin"
cat > "$APPDIR/usr/lib/kyber-fallback-bin/xdg-user-dir" <<'EOF'
#!/bin/sh
# Same answer as xdg-user-dirs: the configured folder, else $HOME
# ($HOME/Desktop for DESKTOP).
case "$1" in ''|*[!A-Z_]*) echo "$HOME"; exit 0 ;; esac
dirs="${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
[ -f "$dirs" ] && . "$dirs"
fallback=$HOME
[ "$1" = DESKTOP ] && fallback=$HOME/Desktop
eval "echo \"\${XDG_${1}_DIR:-\$fallback}\""
EOF
chmod +x "$APPDIR/usr/lib/kyber-fallback-bin/xdg-user-dir"

echo "==> Bundling Kyber nettle AppRun hook"
# kyber-nettle.sh puts usr/lib/nettle3 on LD_LIBRARY_PATH when the host only
# has nettle 4.
cp "$TOOLS/kyber-nettle.sh" "$APPDIR/apprun-hooks/kyber-nettle.sh"
chmod +x "$APPDIR/apprun-hooks/kyber-nettle.sh"

echo "==> Bundling Kyber Vulkan pre-check AppRun hook"
# kyber-vulkan-precheck.sh warns when Vulkan only exposes a software
# renderer (Mesa llvmpipe / lavapipe / swrast). BF2 crashes on those
# with CreateTexture2D E_INVALIDARG after ~25 s, so it is worth catching
# before the game launches. Skips silently when vulkaninfo is missing
# or when a real GPU is reported.
cp "$TOOLS/kyber-vulkan-precheck.sh" "$APPDIR/apprun-hooks/kyber-vulkan-precheck.sh"
chmod +x "$APPDIR/apprun-hooks/kyber-vulkan-precheck.sh"

echo "==> Bundling Kyber glibc pre-check AppRun hook"
# kyber-glibc-precheck.sh aborts the launch with a clear message when the host
# glibc is older than 2.39 (SteamOS 3.6, Ubuntu 22.04), instead of the bundled
# binary crashing windowless with "GLIBC_2.39 not found".
cp "$TOOLS/kyber-glibc-precheck.sh" "$APPDIR/apprun-hooks/kyber-glibc-precheck.sh"
chmod +x "$APPDIR/apprun-hooks/kyber-glibc-precheck.sh"

echo "==> Bundling kyber-playmode recovery script"
# Recovery script for users whose inject keeps failing. AppRun catches
# --playmode and runs this directly via Steam, no launcher in between.
cp "$TOOLS/kyber-playmode.sh" "$APPDIR/usr/bin/kyber-playmode"
chmod +x "$APPDIR/usr/bin/kyber-playmode"

# linuxdeploy rewrites AppRun on every run, so these patches go in each build.
# Each block is marked with a sentinel and inserted once, in front of the GTK
# hook line unless another anchor is given (see tools/apprun-inject.py).
APPRUN="$APPDIR/AppRun"
GTK_HOOK_LINE='source "$this_dir"/apprun-hooks/"linuxdeploy-plugin-gtk.sh"'
apprun_inject() {  # SENTINEL [after] NEEDLE... <<'EOF'
  local sentinel=$1 mode=before
  shift
  if [ "$1" = "after" ]; then mode=after; shift; fi
  [ -f "$APPRUN" ] || return 0
  python3 "$TOOLS/apprun-inject.py" "$APPRUN" "$sentinel" "$mode" "$@"
}

# Before the GTK hook, so the host tools the hook calls use the system GTK.
apprun_inject KYBER_SELF_INSTALL_HOOK "$GTK_HOOK_LINE" <<'EOF'
# KYBER_SELF_INSTALL_HOOK
if [ -f "$this_dir"/apprun-hooks/kyber-self-install.sh ]; then
    source "$this_dir"/apprun-hooks/kyber-self-install.sh || true
fi
EOF

# Native Wayland toggle: source the backend-pref hook BEFORE the GTK hook so the
# exported GDK_BACKEND survives the GTK hook's ${GDK_BACKEND:-x11}.
apprun_inject KYBER_BACKEND_PREF "$GTK_HOOK_LINE" <<'EOF'
# KYBER_BACKEND_PREF
if [ -f "$this_dir"/apprun-hooks/kyber-backend-pref.sh ]; then
    source "$this_dir"/apprun-hooks/kyber-backend-pref.sh || true
fi
EOF

# Snapshot the host XDG_DATA_DIRS before the GTK hook overwrites it, so
# Maxima's browser-open (login.rs open_login_url) can restore the unpolluted
# value when it spawns xdg-open for the EA sign-in. Without this the code falls
# back to sanitising the live, hook-polluted value.
apprun_inject KYBER_ORIG_XDG_DATA_DIRS "$GTK_HOOK_LINE" <<'EOF'
# KYBER_ORIG_XDG_DATA_DIRS - host XDG_DATA_DIRS before the GTK hook edits it
export KYBER_ORIG_XDG_DATA_DIRS="${XDG_DATA_DIRS:-}"
EOF

# --playmode shortcut: skip everything launcher-side, drop straight
# into kyber-playmode.
apprun_inject KYBER_PLAYMODE_BRANCH '# KYBER_SELF_INSTALL_HOOK' <<'EOF'
# KYBER_PLAYMODE_BRANCH
if [ "${1:-}" = "--playmode" ]; then
    shift
    exec "$this_dir"/usr/bin/kyber-playmode "$@"
fi
EOF

# Export __GL_MaxFramesAllowed=1 in AppRun. NVIDIA-only render-ahead cap,
# ignored by Mesa. Already carried by the installed .desktop entry, but
# adding it here makes the direct launch from tools/ behave the same.
apprun_inject KYBER_GL_MAXFRAMES '# KYBER_SELF_INSTALL_HOOK' <<'EOF'
# KYBER_GL_MAXFRAMES
export __GL_MaxFramesAllowed="${__GL_MaxFramesAllowed:-1}"
EOF

# Mark this as a packaged build so the launcher skips its in-app qrc://
# registration (Maxima set_up_registry). The self-install hook already
# registers the qrc:// handler at a stable ~/Applications path; without this
# flag the launcher overwrites it on every start with a handler pointing at
# the ephemeral FUSE mount, which goes stale on the next launch and breaks the
# EA login callback. Honors an existing MAXIMA_PACKAGED for dev overrides.
apprun_inject KYBER_MAXIMA_PACKAGED '# KYBER_SELF_INSTALL_HOOK' <<'EOF'
# KYBER_MAXIMA_PACKAGED
export MAXIMA_PACKAGED="${MAXIMA_PACKAGED:-1}"
EOF

# media_kit resolves libmpv by bare name, trying libmpv.so first. On a host with
# an unversioned libmpv.so (the libmpv-dev symlink) that pulls the system libmpv
# as a second image alongside the bundled libmpv.so.2, and mpv's option lookup
# then crosses between the two and aborts on the first-start intro video. media_kit
# honors LIBMPV_LIBRARY_PATH before the bare-name search, so pin it to the bundled
# lib in the live mount. Set unconditionally; a wrong user value brings the crash back.
apprun_inject KYBER_LIBMPV_PATH '# KYBER_SELF_INSTALL_HOOK' <<'EOF'
# KYBER_LIBMPV_PATH
export LIBMPV_LIBRARY_PATH="$this_dir/usr/lib/libmpv.so.2"
EOF

# AppImage launcher self-update endpoint (manifest JSON published as a release
# asset). Gated to "loose" AppImage installs: AUR/repo-owned binaries (pacman
# -Qo hit) and the extracted /opt AUR install ($APPIMAGE empty -> Dart skips)
# get no updater. Explicit env wins (even empty), so the PKGBUILD can force off.
apprun_inject KYBER_UPDATE_URL '# KYBER_SELF_INSTALL_HOOK' <<'EOF'
# KYBER_UPDATE_URL - only self-update "loose" AppImage installs. AUR/repo
# binaries are owned by pacman and update via the package; the in-app
# container updater must stay out of their way. Discriminator is per binary
# (pacman ownership), not per distro. ${VAR+x} honours an explicit env (even
# empty), letting the PKGBUILD force the updater off deterministically.
if [ -n "${KYBER_UPDATE_URL+x}" ]; then
    : # explicit override (incl. empty=off) - honour as-is
elif [ -n "${APPIMAGE:-}" ] && command -v pacman >/dev/null 2>&1 && pacman -Qo "$APPIMAGE" >/dev/null 2>&1; then
    : # AUR/repo-owned binary -> leave unset -> updater stays off
else
    export KYBER_UPDATE_URL="https://github.com/simonlinuxcraft/kyber-linuxport-unofficial/releases/latest/download/latest.json"
fi
EOF

# Quiet GTK input-method warnings (IBus / GTK modules missing) that look like
# errors on minimal/immutable systems (Steam Deck etc.) but are harmless. Only
# fallback-set with ${:-}, so a host with a real ibus/fcitx setup keeps it.
apprun_inject KYBER_GTK_IM_QUIET '# KYBER_SELF_INSTALL_HOOK' <<'EOF'
# KYBER_GTK_IM_QUIET
export GTK_IM_MODULE="${GTK_IM_MODULE:-}"
export GTK_MODULES="${GTK_MODULES:-}"
EOF

apprun_inject KYBER_XDG_USER_DIR '# KYBER_SELF_INSTALL_HOOK' <<'EOF'
# KYBER_XDG_USER_DIR
command -v xdg-user-dir >/dev/null 2>&1 || export PATH="$PATH:$this_dir/usr/lib/kyber-fallback-bin"
EOF

apprun_inject KYBER_NETTLE '# KYBER_SELF_INSTALL_HOOK' <<'EOF'
# KYBER_NETTLE
if [ -f "$this_dir"/apprun-hooks/kyber-nettle.sh ]; then
    source "$this_dir"/apprun-hooks/kyber-nettle.sh || true
fi
EOF

# Vulkan pre-check hook. Runs right before the GTK plugin loads. Silent on
# systems with a real GPU.
apprun_inject KYBER_VULKAN_PRECHECK "$GTK_HOOK_LINE" <<'EOF'
# KYBER_VULKAN_PRECHECK
if [ -f "$this_dir"/apprun-hooks/kyber-vulkan-precheck.sh ]; then
    source "$this_dir"/apprun-hooks/kyber-vulkan-precheck.sh || true
fi
EOF

# glibc gate. Right after the `this_dir=` line so it runs first, before any
# other hook or the app binary, and can abort a too-old host with a message.
# Falls back to just-before-GTK if linuxdeploy changes that line.
apprun_inject KYBER_GLIBC_GATE after 'this_dir="$(readlink -f "$(dirname "$0")")"' <<'EOF'
# KYBER_GLIBC_GATE - abort early on glibc < 2.39 with a clear message
if [ -f "$this_dir"/apprun-hooks/kyber-glibc-precheck.sh ]; then
    source "$this_dir"/apprun-hooks/kyber-glibc-precheck.sh || true
fi
EOF
if ! grep -q KYBER_GLIBC_GATE "$APPRUN"; then
  apprun_inject KYBER_GLIBC_GATE "$GTK_HOOK_LINE" <<'EOF'
# KYBER_GLIBC_GATE - abort early on glibc < 2.39 with a clear message
if [ -f "$this_dir"/apprun-hooks/kyber-glibc-precheck.sh ]; then
    source "$this_dir"/apprun-hooks/kyber-glibc-precheck.sh || true
fi
EOF
fi

echo "==> Restoring Flutter RUNPATH"
# linuxdeploy rewrites the launcher's RUNPATH from '$ORIGIN/lib' (Flutter's
# default, pointing at bundle-local plugin libs) to '$ORIGIN/../lib' so it
# can pull in centralised system deps. That breaks dynamically-loaded
# plugin libs (rhttp, media_kit, etc.) which the Dart side opens by bare
# filename via DynamicLibrary.open. Restore the Flutter convention; the
# system deps linuxdeploy added in usr/lib/ are still found because GTK's
# linker glue brings them in via NEEDED entries on the GTK libs themselves.
patchelf --set-rpath '$ORIGIN/lib' "$APPDIR/usr/bin/kyber_launcher"

# libsentry.so is loaded from usr/bin/lib via the launcher's RUNPATH but has
# no RUNPATH of its own; its NEEDED libcurl.so.4 is bundled only in usr/lib.
# Without this it resolves libcurl from the system and silently fails to load
# on minimal/immutable distros that lack it (Sentry stops, launcher keeps
# running). Point its RUNPATH at usr/lib (two dirs up from usr/bin/lib).
if [ -f "$APPDIR/usr/bin/lib/libsentry.so" ]; then
  patchelf --set-rpath '$ORIGIN/../../lib' "$APPDIR/usr/bin/lib/libsentry.so"
fi

# crashpad_handler ships with a RUNPATH of empty entries, which the loader reads
# as the working directory, so it would load a libcurl.so.4 lying there. Drop it
# and let it use the system libcurl: the bundled one only knows Debian's CA path
# and fails TLS on openSUSE.
if [ -f "$APPDIR/usr/bin/lib/crashpad_handler" ]; then
  patchelf --remove-rpath "$APPDIR/usr/bin/lib/crashpad_handler"
fi

# media_kit's video plugin NEEDs libmpv.so.2, which linuxdeploy bundled only
# into usr/lib (it pulls in the whole ffmpeg/libass cluster). Flutter leaves a
# build-machine-absolute RUNPATH on this plugin (.../flutter/ephemeral) which
# does not exist on the target, and DT_RUNPATH does not propagate to transitive
# deps, so the plugin can only find libmpv via its own RUNPATH. Without this the
# launcher dies at startup on hosts without system libmpv (SteamOS) with
# "libmpv.so.2: cannot open shared object file".
#
# Scope this to the media_kit video plugin ONLY. Do NOT loop over every plugin:
# linuxdeploy also copied duplicate Flutter engine/plugin libs (libflutter_-
# linux_gtk.so, libsentry.so, ...) into usr/lib, and adding usr/lib to an
# unrelated plugin's RUNPATH makes it pull a second copy of those, which double-
# loads the engine and segfaults at startup (crashpad then fires). $ORIGIN comes
# first so the shared Flutter/GTK libs still resolve from usr/bin/lib (the same
# instances the main binary loaded); only the unique libmpv comes from usr/lib.
_mkvp="$APPDIR/usr/bin/lib/libmedia_kit_video_plugin.so"
if [ -f "$_mkvp" ]; then
  patchelf --set-rpath '$ORIGIN:$ORIGIN/../../lib' "$_mkvp"
fi

echo "==> Checking symbol versions against the release floor"
# Bundled system libs inherit the build host's glibc and libstdc++. A build on a
# newer distro passes the AppRun gate (kyber-glibc-precheck.sh) and then fails
# to load, so refuse to package it.
_versions="$(find "$APPDIR" -type f \( -name '*.so*' -o -perm -u+x \) -print0 \
  | xargs -0 objdump -T 2>/dev/null | grep -o -E 'GLIBC(XX)?_[0-9.]+' || true)"
_max() { printf '%s\n' "$_versions" | grep "^$1_" | sed "s/^$1_//" | sort -V | tail -1; }
_newer() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" != "$2" ]; }
if _newer "$(_max GLIBC)" 2.39 || _newer "$(_max GLIBCXX)" 3.4.32; then
  echo "ERROR: bundle needs GLIBC_$(_max GLIBC) / GLIBCXX_$(_max GLIBCXX)," \
    "the release floor is 2.39 / 3.4.32. Build on Ubuntu 24.04." >&2
  exit 1
fi

echo "==> Building AppImage"
# AppImage runtime selection.
#
# We embed the modern type-2 runtime from AppImage/type2-runtime instead
# of letting `appimagetool` use its default runtime. The default is FUSE2-
# only and silently fails to start on FUSE3-only distros (Bazzite,
# Fedora Silverblue, Kinoite - all immutable Fedora-based, where libfuse2
# cannot be installed). The type-2 runtime is statically PIE-linked,
# probes FUSE3 first, falls back to FUSE2, and auto-degrades to
# `--appimage-extract-and-run` when neither is available.
#
# Net effect: a single AppImage that boots out-of-the-box on Ubuntu,
# Fedora (regular + atomic / Silverblue / Bazzite), Arch and derivatives.
#
# When the runtime file is missing we fall back to the bundled default
# so the build does not silently regress on a fresh checkout.
RUNTIME_FILE="$TOOLS/type2-runtime-x86_64"
RUNTIME_ARGS=()
if [[ -f "$RUNTIME_FILE" ]]; then
    echo "    Using type-2 runtime from $RUNTIME_FILE"
    RUNTIME_ARGS+=( --runtime-file "$RUNTIME_FILE" )
else
    echo "    WARNING: $RUNTIME_FILE missing - falling back to default FUSE2 runtime."
    echo "    Built AppImage will NOT start on Bazzite / Silverblue / Fedora atomic."
    echo "    Download via: gh release download continuous --repo AppImage/type2-runtime --pattern 'runtime-x86_64' --output tools/type2-runtime-x86_64"
fi
# AppStream data for software centers and AppImage managers. The release
# line follows the launcher version.
PORT_VERSION="$(grep -oP "kLinuxPortVersion\s*=\s*'\K[^']+" \
  "$REPO_ROOT/Kyber/Launcher/lib/features/settings/screens/settings_list.dart")"
METAINFO="$APPDIR/usr/share/metainfo/io.github.simonlinuxcraft.kyber_linuxport.metainfo.xml"
mkdir -p "${METAINFO%/*}"
cat > "$METAINFO" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>io.github.simonlinuxcraft.kyber_linuxport</id>
  <metadata_license>CC0-1.0</metadata_license>
  <project_license>GPL-3.0-only</project_license>
  <name>Kyber (Linux Port)</name>
  <summary>Unofficial Linux port of the Kyber mod launcher</summary>
  <description>
    <p>Kyber is the mod launcher and server browser for Star Wars Battlefront II (2017). This port runs it on Linux and starts the game through Proton.</p>
    <p>It is not made or endorsed by the Kyber team.</p>
  </description>
  <developer id="io.github.simonlinuxcraft">
    <name>simonlinuxcraft</name>
  </developer>
  <launchable type="desktop-id">kyber-linux.desktop</launchable>
  <url type="homepage">$SOURCE_URL</url>
  <url type="bugtracker">$SOURCE_URL/issues</url>
  <categories>
    <category>Game</category>
  </categories>
  <releases>
    <release version="$PORT_VERSION" date="$(date -u +%F)"/>
  </releases>
</component>
EOF

ARCH=x86_64 ./appimagetool-x86_64.AppImage --no-appstream "${RUNTIME_ARGS[@]}" "$APPDIR" "$OUTPUT"

# Update manifest for the AppImage self-updater (KYBER_UPDATE_URL). Upload this
# next to the AppImage as a release asset named latest.json. The launcher reads
# version (Linux-port scheme from kLinuxPortVersion), download_url (stable
# releases/latest redirect), and sha256 to verify the download.
echo "==> Writing update manifest (latest.json)"
OUTPUT_SHA="$(sha256sum "$OUTPUT" | cut -d' ' -f1)"
cat > "$TOOLS/latest.json" <<EOF
{
  "version": "$PORT_VERSION",
  "download_url": "$SOURCE_URL/releases/latest/download/KyberLinuxPort-x86_64.AppImage",
  "sha256": "$OUTPUT_SHA"
}
EOF
echo "    latest.json: version=$PORT_VERSION sha256=$OUTPUT_SHA"

# AUR source. The package has no AppRun, so the menu entry and icons must ship here.
echo "==> Writing AUR archive"
AUR_TARXZ="$TOOLS/${PORT_VERSION//-/_}.tar.xz"
tar -C "$APPDIR" --owner=0 --group=0 --numeric-owner --exclude=.sentry-native \
  --transform 's,^usr/bin,opt/kyber,' -I 'xz -9e -T0' -cf "$AUR_TARXZ" \
  usr/bin usr/share/applications usr/share/icons usr/share/metainfo \
  usr/share/doc/kyber-linux

echo
echo "==> Done"
echo "AppImage: $OUTPUT"
ls -lh "$OUTPUT"
echo "Manifest: $TOOLS/latest.json"
echo "AUR:      $AUR_TARXZ"
