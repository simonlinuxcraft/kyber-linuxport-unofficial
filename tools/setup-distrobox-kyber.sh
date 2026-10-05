#!/usr/bin/env bash
#
# setup-distrobox-kyber.sh
# ------------------------
# One-shot setup for running the Kyber (Linux Port) AppImage inside a Distrobox
# container, for hosts whose glibc is older than 2.38 (Linux Mint 21.x,
# Ubuntu 22.04, Debian 12, SteamOS 3.6, ...). The launcher hard-gates glibc < 2.38,
# so it cannot run on the host directly; an Ubuntu 24.04 container (glibc 2.39)
# clears the gate while still using the host GPU and the host's Steam-Proton
# BF2 install.
#
# Tested end-to-end on: Linux Mint 21.3 (glibc 2.35), NVIDIA proprietary driver,
# podman 3.4.4 (rootless), distrobox 1.7.2.1, Kyber Linux port v0.1.0-beta.6.4.9.
#
# Prerequisites you must do yourself (need root):
#     sudo apt install -y podman uidmap
#
# Everything else here is rootless / per-user.
#
# Usage:
#     ./setup-distrobox-kyber.sh
#     ./setup-distrobox-kyber.sh --recreate     # destroy & rebuild the container
#
set -euo pipefail

CONTAINER=kyber
IMAGE=docker.io/library/ubuntu:24.04
DISTROBOX_VERSION=1.7.2.1          # 2.0+ uses `--userns keep-id:size=` which podman < 4.3 rejects
APPDIR="$HOME/Applications"
APPIMAGE="$APPDIR/KyberLinuxPort-x86_64.AppImage"
RELEASE_REPO=simonlinuxcraft/kyber-linuxport-unofficial
LOCALBIN="$HOME/.local/bin"
DESKTOPDIR="$HOME/.local/share/applications"

log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

command -v podman >/dev/null || die "podman not found. Run: sudo apt install -y podman uidmap"
grep -q "^$USER:" /etc/subuid || die "no subuid mapping for $USER. Run: sudo apt install -y uidmap (and re-login)"

[ "${1:-}" = "--recreate" ] && { log "Removing existing container"; podman rm -f "$CONTAINER" 2>/dev/null || true; }

# ---------------------------------------------------------------------------
# 1. distrobox 1.7.2.1 (shell version) into ~/.local
#    The upstream `install` script always pulls the 2.0 binary even with
#    --version, so fetch the tagged tarball and run its own installer.
# ---------------------------------------------------------------------------
if ! "$LOCALBIN/distrobox-create" --version 2>/dev/null | grep -q "$DISTROBOX_VERSION"; then
  log "Installing distrobox $DISTROBOX_VERSION (podman 3.4.x compatible)"
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/d.tgz" \
    "https://github.com/89luca89/distrobox/archive/refs/tags/${DISTROBOX_VERSION}.tar.gz"
  tar -xzf "$tmp/d.tgz" -C "$tmp"
  rm -f "$LOCALBIN"/distrobox "$LOCALBIN"/distrobox-* 2>/dev/null || true
  "$tmp/distrobox-${DISTROBOX_VERSION}/install" --prefix "$HOME/.local" >/dev/null
  rm -rf "$tmp"
fi
export PATH="$LOCALBIN:$PATH"

# ---------------------------------------------------------------------------
# 2. Create + initialise the container (Ubuntu 24.04 + NVIDIA passthrough)
# ---------------------------------------------------------------------------
if ! podman container exists "$CONTAINER" 2>/dev/null; then
  log "Creating container '$CONTAINER' ($IMAGE, --nvidia)"
  distrobox create --name "$CONTAINER" --image "$IMAGE" --nvidia --yes
fi
log "Initialising container (first enter)"
distrobox enter "$CONTAINER" -- true

# ---------------------------------------------------------------------------
# 3. Install runtime dependencies inside the container
# ---------------------------------------------------------------------------
# NOTE: do NOT install Mesa software-GL drivers and do NOT force
# LIBGL_ALWAYS_SOFTWARE=1 - the Flutter UI renders correctly on the passed-through
# NVIDIA GL, and llvmpipe actually FAILS here ("No available configurations for the
# given RGBA pixel format").
DEPS="\
fuse libfuse2t64 zenity xdg-utils \
libsecret-1-0 libnss3 libnspr4 libgbm1 libdrm2 libxshmfence1 libxkbcommon0 libxkbcommon-x11-0 libepoxy0 \
libgtk-3-0t64 libasound2t64 libcups2t64 libatk1.0-0t64 libatk-bridge2.0-0t64 \
libxcomposite1 libxdamage1 libxrandr2 libxfixes3 libxext6 libpango-1.0-0 libcairo2 libnotify4 \
libpipewire-0.3-0 libxss1 libvulkan1 libgl1 libegl1 libwayland-client0 libwayland-egl1 libwayland-cursor0 \
libsm6 libice6 libdbus-1-3 fonts-liberation libxtst6 \
libusb-1.0-0 libatspi2.0-0t64 libpulse0 libgles2 libayatana-appindicator3-1 libxcb-dri3-0 libxcb-dri2-0"

log "Installing runtime libraries (FUSE, GTK/Flutter/Electron deps, xdg-utils)"
distrobox enter "$CONTAINER" -- bash -lc "sudo apt-get update -qq && sudo apt-get install -y -qq $DEPS"

# Real Firefox from Mozilla's APT repo. Ubuntu's `firefox` is a snap stub that
# drags in snapd/apparmor (which can't configure in a container) - avoid it.
log "Installing Firefox (.deb from Mozilla, NOT the snap) for the Nexus/EA OAuth callback"
distrobox enter "$CONTAINER" -- bash -lc '
  set -e
  sudo install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://packages.mozilla.org/apt/repo-signing-key.gpg | sudo tee /etc/apt/keyrings/packages.mozilla.org.asc >/dev/null
  echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" | sudo tee /etc/apt/sources.list.d/mozilla.list >/dev/null
  printf "Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n" | sudo tee /etc/apt/preferences.d/mozilla >/dev/null
  sudo apt-get update -qq
  sudo apt-get purge -y -qq snapd 2>/dev/null || true
  sudo apt-get install -y -qq firefox
  sudo apt-get purge -y -qq apparmor 2>/dev/null || true   # leftover, inert in a container
  sudo dpkg --configure -a || true
  xdg-settings set default-web-browser firefox.desktop || true
'

# ---------------------------------------------------------------------------
# 4. Download the Kyber AppImage (verified against the release manifest)
# ---------------------------------------------------------------------------
log "Fetching the latest Kyber Linux port AppImage"
mkdir -p "$APPDIR"
api="https://api.github.com/repos/$RELEASE_REPO/releases/latest"
url="$(curl -fsSL "$api" | grep -oE '"browser_download_url": *"[^"]*KyberLinuxPort-x86_64\.AppImage"' | cut -d'"' -f4)"
sha="$(curl -fsSL "$(echo "$url" | sed 's#/KyberLinuxPort-x86_64.AppImage#/latest.json#')" | grep -oE '"sha256": *"[0-9a-f]+"' | cut -d'"' -f4)"
[ -n "$url" ] || die "could not resolve AppImage download URL"
curl -fL --progress-bar -o "$APPIMAGE" "$url"
if [ -n "$sha" ]; then
  echo "$sha  $APPIMAGE" | sha256sum -c - || die "sha256 mismatch on the AppImage"
  log "AppImage sha256 verified"
fi
chmod +x "$APPIMAGE"

# ---------------------------------------------------------------------------
# 5. Launch wrapper
# ---------------------------------------------------------------------------
log "Writing launch wrapper: $LOCALBIN/kyber-box"
mkdir -p "$LOCALBIN"
cat > "$LOCALBIN/kyber-box" <<EOF
#!/usr/bin/env bash
# Launch the Kyber (Linux Port) AppImage inside the '$CONTAINER' distrobox.
#   KYBER_NO_AUTO_INSTALL=1  keeps the container-routing .desktop handlers below
#                            (otherwise Kyber's self-install rewrites them to host
#                            paths, which then hit the glibc gate / wrong namespace)
#   __GL_MaxFramesAllowed=1  NVIDIA render-ahead hint the port itself uses
#   BROWSER=/usr/bin/firefox forces the in-container Firefox for the OAuth callback
exec "$LOCALBIN/distrobox" enter $CONTAINER -- bash -lc \\
  'cd ~/Applications && exec env KYBER_NO_AUTO_INSTALL=1 __GL_MaxFramesAllowed=1 BROWSER=/usr/bin/firefox ./KyberLinuxPort-x86_64.AppImage'
EOF
chmod +x "$LOCALBIN/kyber-box"

# ---------------------------------------------------------------------------
# 6. URL-scheme handlers (qrc:// EA-login callback, nxm:// Nexus mods, kl:// Kyber
#    website and Discord linking) MUST route
#    back into the container. Kyber's self-install registers them to host paths,
#    which run on the host (glibc gate) or in the wrong namespace and never reach
#    the running launcher. Re-point them into the container.
# ---------------------------------------------------------------------------
log "Registering container-routing qrc://, nxm:// and kl:// handlers"
mkdir -p "$DESKTOPDIR"
EXT="$APPDIR/KyberLinuxPort.extracted"   # created by the launcher's self-install on first run
cat > "$DESKTOPDIR/kyber-linuxport-qrc.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Kyber QRC Handler
Comment=Routes qrc:// OAuth redirects (EA login) into the $CONTAINER container.
Exec=$LOCALBIN/distrobox enter $CONTAINER -- $EXT/usr/bin/cli/maxima-bootstrap %u
NoDisplay=true
Terminal=false
MimeType=x-scheme-handler/qrc;
EOF
cat > "$DESKTOPDIR/kyber-linuxport-nxm.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Kyber NXM Handler
Comment=Routes nxm:// and kl:// links into the $CONTAINER container.
Exec=$LOCALBIN/distrobox enter $CONTAINER -- $EXT/usr/bin/cli/bin/nxm_handler.sh %u
NoDisplay=true
Terminal=false
MimeType=x-scheme-handler/nxm;x-scheme-handler/kl;
EOF
xdg-mime default kyber-linuxport-qrc.desktop x-scheme-handler/qrc 2>/dev/null || true
xdg-mime default kyber-linuxport-nxm.desktop x-scheme-handler/nxm x-scheme-handler/kl 2>/dev/null || true
update-desktop-database "$DESKTOPDIR" 2>/dev/null || true

log "Done."
cat <<EOF

  Launch Kyber with:   kyber-box        (or add a .desktop entry pointing at it)

  Notes:
   * First launch runs the launcher's self-install; if a login browser is needed
     it opens the in-container Firefox so the qrc:// callback returns.
   * If you ever get 'kicked by Kyber' on join, fully quit and relaunch - that
     clears any stale wineserver/vkd3d state from a previous run.
EOF
