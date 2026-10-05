# Running the Kyber Linux Port in Distrobox (old-glibc hosts)

The launcher hard-requires **glibc ≥ 2.39** (`kyber-glibc-precheck.sh`). On
Linux Mint 21.x, Ubuntu 22.04, Debian 12, SteamOS 3.6 and similar, it aborts with
an "unsupported system" dialog before the first frame. Running it inside an
**Ubuntu 24.04 Distrobox container (glibc 2.39)** clears the gate while still
using the host GPU and the host's Steam-Proton BF2 install.

> Verified end-to-end on Linux Mint 21.3 (glibc 2.35) + NVIDIA proprietary
> driver + podman 3.4.4 (rootless) + distrobox 1.7.2.1, launcher
> `v0.1.0-beta.6.4.9`. Reaches a live Kyber private server.

There's an automated `setup-distrobox-kyber.sh` alongside this doc; the steps
below are what it does, so you can do them by hand or understand/trust it.

## 0. Host prerequisites (need root)

```bash
sudo apt install -y podman uidmap
```

`uidmap` is required for rootless podman subuid/subgid mapping. Confirm
`grep "^$USER:" /etc/subuid` returns a line (re-login if you just installed it).

## 1. Distrobox 1.7.2.1 - *not* 2.0

Distrobox **2.0+** invokes `podman ... --userns keep-id:size=65536`; the `:size=`
syntax needs **podman ≥ 4.3**, and Ubuntu 22.04's podman 3.4.4 rejects it with
`unrecognized namespace mode keep-id:size=65536`. Use the last 1.x release, which
emits plain `--userns keep-id`:

```bash
curl -fsSL -o /tmp/d.tgz https://github.com/89luca89/distrobox/archive/refs/tags/1.7.2.1.tar.gz
tar -xzf /tmp/d.tgz -C /tmp
/tmp/distrobox-1.7.2.1/install --prefix ~/.local
```

(The upstream `install` one-liner pulls the 2.0 binary even with `--version`, so
fetch the tagged tarball directly.)

## 2. Create the container

```bash
distrobox create --name kyber --image docker.io/library/ubuntu:24.04 --nvidia --yes
distrobox enter kyber -- true     # triggers one-time init
```

`--nvidia` mounts the host driver libs; `nvidia-smi` inside should report your GPU.

## 3. Runtime dependencies

AppImage needs the **FUSE2 `fusermount`** binary (the `fuse` package - `libfuse2t64`
alone is *not* enough). The launcher is a **Flutter** app and pulls in the usual
GTK/Chromium/Electron shared libs, plus `libsecret`, `pipewire`, `libusb`, etc.

```bash
distrobox enter kyber -- sudo apt-get install -y \
  fuse libfuse2t64 zenity xdg-utils \
  libsecret-1-0 libnss3 libnspr4 libgbm1 libdrm2 libxshmfence1 libxkbcommon0 libxkbcommon-x11-0 libepoxy0 \
  libgtk-3-0t64 libasound2t64 libcups2t64 libatk1.0-0t64 libatk-bridge2.0-0t64 \
  libxcomposite1 libxdamage1 libxrandr2 libxfixes3 libxext6 libpango-1.0-0 libcairo2 libnotify4 \
  libpipewire-0.3-0 libxss1 libvulkan1 libgl1 libegl1 libwayland-client0 libwayland-egl1 libwayland-cursor0 \
  libsm6 libice6 libdbus-1-3 fonts-liberation libxtst6 \
  libusb-1.0-0 libatspi2.0-0t64 libpulse0 libgles2 libayatana-appindicator3-1 libxcb-dri3-0 libxcb-dri2-0
```

> **Do not** install Mesa software-GL or set `LIBGL_ALWAYS_SOFTWARE=1`. The Flutter
> UI renders fine on the passed-through NVIDIA GL; llvmpipe over X11 here fails with
> `Failed to create OpenGL context: No available configurations for the given RGBA
> pixel format`, leaving a blank window.

## 4. A real Firefox (for the EA/Nexus OAuth callback)

Ubuntu's apt `firefox` is a **snap transitional** package; it drags in `snapd` +
`apparmor`, which can't configure inside a container and break dpkg. Use Mozilla's
official `.deb` repo instead:

```bash
distrobox enter kyber -- bash -lc '
  sudo install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://packages.mozilla.org/apt/repo-signing-key.gpg | sudo tee /etc/apt/keyrings/packages.mozilla.org.asc >/dev/null
  echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" | sudo tee /etc/apt/sources.list.d/mozilla.list >/dev/null
  printf "Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n" | sudo tee /etc/apt/preferences.d/mozilla >/dev/null
  sudo apt-get update -qq && sudo apt-get install -y firefox
  xdg-settings set default-web-browser firefox.desktop
'
```

## 5. AppImage + launch wrapper

```bash
mkdir -p ~/Applications
# download KyberLinuxPort-x86_64.AppImage from the latest release into ~/Applications
chmod +x ~/Applications/KyberLinuxPort-x86_64.AppImage
```

Launch it **inside the container** with three env vars:

```bash
distrobox enter kyber -- bash -lc \
  'cd ~/Applications && exec env KYBER_NO_AUTO_INSTALL=1 __GL_MaxFramesAllowed=1 BROWSER=/usr/bin/firefox ./KyberLinuxPort-x86_64.AppImage'
```

- `KYBER_NO_AUTO_INSTALL=1` - stops the self-install hook from rewriting the URL
  handlers (next section) back to host paths on every launch.
- `__GL_MaxFramesAllowed=1` - the NVIDIA render-ahead hint the port already uses
  in its own desktop entry.
- `BROWSER=/usr/bin/firefox` - use the in-container Firefox for OAuth.

## 6. Route the qrc://, nxm:// and kl:// handlers **into** the container

Kyber's self-install and the launcher itself register host-side `.desktop`
handlers for its OAuth callback (`qrc://`), Nexus mod links (`nxm://`) and Kyber
links (`kl://`, Discord linking and website links). On an old-glibc host those
run **on the host** (glibc gate) or in the wrong namespace and never reach the
running in-container launcher - so EA login "never returns" and mod downloads
don't fire. With `KYBER_NO_AUTO_INSTALL=1` the launcher leaves these handlers
alone. Re-point them into the container:

```ini
# ~/.local/share/applications/kyber-linuxport-qrc.desktop
Exec=~/.local/bin/distrobox enter kyber -- ~/Applications/KyberLinuxPort.extracted/usr/bin/cli/maxima-bootstrap %u
MimeType=x-scheme-handler/qrc;
```
```ini
# ~/.local/share/applications/kyber-linuxport-nxm.desktop
Exec=~/.local/bin/distrobox enter kyber -- ~/Applications/KyberLinuxPort.extracted/usr/bin/cli/bin/nxm_handler.sh %u
MimeType=x-scheme-handler/nxm;x-scheme-handler/kl;
```
```bash
xdg-mime default kyber-linuxport-qrc.desktop x-scheme-handler/qrc
xdg-mime default kyber-linuxport-nxm.desktop x-scheme-handler/nxm x-scheme-handler/kl
update-desktop-database ~/.local/share/applications
```

(`KyberLinuxPort.extracted/` is created by the launcher's self-install on first run.)

## Known rough edges

- **Intermittent Flutter UI crash** (`FlutterEngineRemoveView … implicit view cannot
  be removed`): the window can vanish while the process lingers. Relaunching clears it.
  Network namespace, GPU, and the gRPC link are *not* the cause.
- **"Kicked by Kyber" on join** was, in our testing, **transient stale state** - a
  leftover `wineserver` attached to the prefix plus a stale `vkd3d-proton.cache` from
  repeated launches (cf. upstream issue #6). Fully quit and relaunch; if needed:
  `rm -f ~/.local/share/maxima/custom_proton_path` and the game's `vkd3d-proton.cache`.
  After a clean restart the join handshake succeeds and the gRPC link stays up.
- **Network**: Distrobox shares the host network namespace and umu/pressure-vessel
  does not unshare it, so the injected `Kyber.dll`'s `127.0.0.1:$KYBER_LAUNCHER_PORT`
  gRPC connection to the launcher works across the boundary - verified with `ss`.
