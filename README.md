<h1 align="center">
  <img src="assets/kyber-banner.png" alt="Kyber Linux Port - Unofficial Linux Port" width="800">
</h1>

<p align="center">
  <a href="https://github.com/simonlinuxcraft/kyber-linuxport-unofficial/releases/latest"><img src="https://img.shields.io/github/v/release/simonlinuxcraft/kyber-linuxport-unofficial?label=release&color=f8b133" alt="Latest release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPLv3-blue" alt="GPLv3"></a>
  <img src="https://img.shields.io/badge/glibc-2.39%2B-lightgrey" alt="Requires glibc 2.39 or newer">
</p>

<p align="center">
  <a href="https://github.com/simonlinuxcraft/kyber-linuxport-unofficial/releases/latest"><b>Download the AppImage</b></a>
  &nbsp;·&nbsp;
  <a href="#install">Install</a>
  &nbsp;·&nbsp;
  <a href="#distro-support">Distro support</a>
  &nbsp;·&nbsp;
  <a href="#steam-deck--steamos">Steam Deck</a>
  &nbsp;·&nbsp;
  <a href="CHANGELOG.md">Changelog</a>
</p>

Unofficial Linux build of the [Kyber](https://kyber.gg) mod launcher for
Star Wars: Battlefront II (2017). The upstream launcher is Windows only,
so this just packages the existing source from
[ArmchairDevelopers/Kyber](https://github.com/ArmchairDevelopers/Kyber)
and [ArmchairDevelopers/Maxima](https://github.com/ArmchairDevelopers/Maxima)
into an AppImage that runs on Linux.

This is a community fork. Not endorsed by the Kyber team, ArmchairDevelopers,
EA, Lucasfilm, or Disney. If you're on Windows, use the
[official launcher](https://kyber.gg). Bugs in this Linux build go here,
not to upstream Kyber.

> [!IMPORTANT]
> The build needs **glibc 2.39 or newer**. Ubuntu 22.04, Debian 12 and
> SteamOS 3.6 cannot run it. See [Install](#install) for the supported
> systems and the Distrobox workaround.

<p align="center">
  <img src="assets/screenshot-home.jpg" alt="Server browser" width="900">
</p>

<p align="center">
  <img src="assets/screenshot-ingame.jpg" alt="Battlefront II running on Linux at 152 FPS through Proton and DXVK, joined to a Kyber server" width="900">
</p>

<details>
<summary>More screenshots</summary>

<p align="center">
  <img src="assets/screenshot-mods.jpg" alt="Mod browser" width="900">
  <img src="assets/screenshot-settings.jpg" alt="Mods, Proton and renderer settings" width="900">
</p>

</details>

## Latest release

v0.1.0-beta.6.4.14 is the current build, and the in-app updater offers it.

- Joining a server while the game is already running asks for a game restart
  instead of getting you kicked with "failed to authenticate".
- Slow first launches no longer lose their join token.
- The mod update check finds mods in the current Nexus download format and
  highlights mods with an update. With Nexus Premium the update replaces the
  old version.

If you are still on 6.4.10 or older, update by hand once: the broken updater
shipped in every build before 6.4.11, so those versions cannot fetch the fix
themselves. After that the in-app updater works.

Older releases are listed in [`CHANGELOG.md`](CHANGELOG.md).

## Heads up

> [!WARNING]
> This is a beta and a one-person port, so expect rough edges. The inject
> works on the common setups now, but voice chat is not fully proven yet,
> Nexus mod downloads can still fail, and some distro or GPU combinations
> do not work at all (a VM without GPU passthrough will not run BF2, for
> example).

It assumes a healthy system underneath. A working Steam-Proton or
Lutris install of BF2, a real GPU with proper Vulkan drivers, and a
normal desktop audio stack. The launcher cannot fix a broken Proton
prefix or missing graphics drivers. A well set up system is the
baseline here, not something the AppImage brings along.

## Dependencies

The AppImage bundles most of its libraries but still needs the system
GTK stack plus FUSE. A missing one of these is the most common reason a
fresh install misbehaves, so pull them in up front.

Debian, Ubuntu, Mint:

```bash
sudo apt install libgtk-3-0 libfuse2 librsvg2-2 libnotify4 gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav zenity gamemode
```

Arch, CachyOS:

```bash
sudo pacman -S --needed gtk3 fuse2 librsvg libnotify gst-plugins-bad gst-plugins-ugly gst-libav zenity gamemode nettle3
```

Fedora: the equivalent gtk3, fuse, librsvg2, libnotify and gstreamer1
plugin packages.

| Package | What it does | Needed |
| --- | --- | --- |
| gtk3, librsvg, libnotify, fuse2 | The launcher window itself | Required, will not start without them |
| gstreamer plugins (bad, ugly, libav) | Plays the EA login splash video | Optional, silent without them |
| zenity | First-start dialog that offers the desktop entry | Recommended, preinstalled on most distros |
| gamemode | Keeps the CPU governor on performance | Optional, smoother frames |
| nettle3 | Provides libnettle.so.8 | Rolling Arch/CachyOS only, see below |

webkit2gtk is no longer needed: the in-app webview is unused on Linux, so
it was dropped to fix startup on systems without a system webkit such as
the Steam Deck. libmpv is bundled inside the AppImage, you do not install
it yourself. nettle3 matters because rolling Arch and CachyOS now ship
nettle 4.0 (libnettle.so.9); without the libnettle.so.8 that nettle3
provides the launcher will not start, and it shows a dialog telling you so.

## Install

You need BF2 already installed via Steam-Proton (or Lutris). The launcher
doesn't bootstrap Wine itself.

```bash
mkdir -p ~/Applications
mv ~/Downloads/KyberLinuxPort-x86_64.AppImage ~/Applications/
chmod +x ~/Applications/KyberLinuxPort-x86_64.AppImage
~/Applications/KyberLinuxPort-x86_64.AppImage
```

On first start a small zenity dialog asks if you want a desktop entry.
Say yes if you want the launcher in your app menu. Most distros have
zenity preinstalled. If the dialog doesn't show up, install it via your
package manager.

Tested on Ubuntu 24.04 with an Nvidia RTX 3060. Other distros should work
since the AppImage bundles its own runtime, but I haven't verified every
one personally. The build needs glibc 2.39 or newer, so older releases
(Ubuntu 22.04, Debian 12, SteamOS 3.6) cannot run it; use 24.04+, Fedora,
SteamOS 3.7+ or Bazzite. To keep an old host as-is, run the AppImage inside
an Ubuntu 24.04 Distrobox container (glibc 2.39); see
[`docs/running-in-distrobox.md`](docs/running-in-distrobox.md).

On Arch or CachyOS you can install from the AUR instead:

```bash
yay -S kyber-launcher-unofficial-appimage   # or: paru -S kyber-launcher-unofficial-appimage
```

The AUR package is a native binary build (contributed by Yilmaz4), not the
AppImage, and pulls in its own dependencies. The manual pacman step above is
only needed if you run the downloaded AppImage directly. The package keeps the
`-appimage` name for now and will be renamed to `kyber-launcher-bin` at beta 10.
It is built separately from the AppImage release and can trail it by a version,
so check `pkgver` if you need the newest build.

## Distro support

No guarantees. This is what reports and testing actually showed, not a
compatibility promise.

| Distro | Status |
| --- | --- |
| Ubuntu 24.04+ | Runs. Every release is tested here |
| Fedora, Nobara | Runs. Community-tested, no open reports |
| Arch, CachyOS | Runs once `nettle3` is installed, see [Dependencies](#dependencies) |
| Bazzite | Runs without extra packages; one report of AMD instability during play |
| Steam Deck, SteamOS 3.7+ | Launcher runs; the first game start can stall while umu fetches its runtime |
| SteamOS 3.6, Ubuntu 22.04, Debian 12 | Does not run, glibc too old. The launcher says so instead of crashing |

A few notes on the entries that changed:

- **Arch and CachyOS** are the only systems that need a manual step. Rolling
  Arch ships `libnettle.so.9`, the build needs `libnettle.so.8`. Without
  `nettle3` the launcher does not start, and it will tell you so.
- **Bazzite** no longer needs a FUSE2 layer. The AppImage carries the type-2
  runtime, which speaks FUSE3, falls back to FUSE2 and extracts itself when
  neither is there. The remaining question mark is a report of GPU instability
  on AMD during play. One cause on our side, a process scan that ran forty
  times a second, is fixed in this release; whether that settles it is unknown.
- **Steam Deck** was measured on SteamOS 3.7.7: glibc 2.41, the launcher starts.
  A Deck that has never run a Proton game has no Steam runtime to reuse, so the
  first game start pulls one down and can take a long time.

**Test rig:** Ubuntu 24.04, Ryzen 7 5800X, RTX 3060, 32 GB DDR4, BF2 through
Steam-Proton with GE-Proton. DX12 does not work on it, DX11 gives 60 to 80 FPS
on Ultra.

> [!TIP]
> If BF2 runs rough, the [FPS Booster](https://www.nexusmods.com/starwarsbattlefront22017/mods/12086)
> mod on Nexus is worth adding to your collection.

## Steam Deck / SteamOS

Use Desktop Mode. The AppImage runs on SteamOS like on any other distro;
the webkit dependency was dropped, so it starts without extra packages.

The catch is the EA login. The launcher opens EA sign-in in your browser,
and on the Deck that is usually a Flatpak browser, which does not hand the
`qrc://` callback back to the launcher, so the automatic login never
completes. To finish login manually:

1. Press "Login with EA" and sign in in the browser that opens.
2. After signing in, the browser tries to open a `qrc://...` link and
   shows an error or blank page. Copy that link (or just the `code=...`
   value from it).
3. Back in the launcher, paste it into the field under "Browser did not
   return to the launcher?" on the login screen and submit.

On a detected Steam Deck that paste field is shown expanded by default.

Alternative: run the launcher inside a Distrobox container that has a
normal (non-Flatpak) browser, where the callback can work automatically.

## Advanced (optional)

### Custom Proton path

The default flow downloads GE-Proton10-34 into
`~/.local/share/maxima/wine/proton/` and runs BF2 from there. That version
is pinned, so a new GE release neither changes what you run nor triggers a
re-download. It is the only tested-stable path and the recommended default
for most users.

Advanced users can override the Proton build used for BF2. Settings ->
Mod Configuration -> "Custom Proton Path (Experimental)" opens a dialog
that browses for or scans the standard Steam compatibility-tools folders.
Verified to work in testing: GE-Proton 10.x family, Proton-EM Latest,
proton-cachyos 11.x. Newer builds with Wine 10 + DXVK 2.x can give
noticeably smoother frame times than the bundled default, at the cost of
losing the tested-stable safety net.

> [!TIP]
> To get those builds onto your system, [ProtonPlus](https://flathub.org/en/apps/com.vysp3r.ProtonPlus)
> is the easiest route. It downloads GE-Proton, Proton-EM and others into the
> folders the scan already looks at, so they show up in the dialog right after.

Equivalent power-user env var:

```bash
KYBER_PROTON_PATH="$HOME/.steam/steam/compatibilitytools.d/Proton-EM Latest" \
  ~/Applications/KyberLinuxPort-x86_64.AppImage
```

Resolution order is env var first, then a sidecar file at
`~/.local/share/maxima/custom_proton_path` (written by the UI), then the
auto-managed default.

Implementation: when a custom path is active, the launcher transparently
swaps `~/.local/share/maxima/wine/proton` for a symlink to the chosen
build (originals are moved aside to `proton.maxima-backup`). The Wine
prefix itself stays the shared BF2 Steam compat-prefix, so save games and
EA App login survive switching between default and custom. "Reset to
default" in the dialog restores the symlink instantly without re-download.

Switching Proton also clears BF2's vkd3d-proton.cache automatically, so
the first match after a switch will recompile shaders for one or two
minutes and then settle smooth. A manual Clear shader cache button is
in the dialog for cases where the auto-purge cannot find your BF2
install (Custom Game Path setups).

Close BF2 fully before switching Proton. The dialog detects a stale
wineserver from a previous BF2 session and offers a one-click "Kill
wineserver and retry" action, but cleanly exited beats forced-kill.

### Native Wayland

The launcher runs on X11 (XWayland) by default. On a Wayland session you can
switch to the native backend under Settings -> Mods / Proton / Wayland
("Native Wayland"). It applies after a restart. The toggle only appears on a
Wayland session; on X11 there is no Wayland display to use, so it is hidden.

If the native backend glitches or crashes, turn the toggle back off (or remove
`~/.config/kyber-linuxport/backend`) and it falls back to X11. The manual
override still works too:

```bash
GDK_BACKEND=wayland ~/Applications/KyberLinuxPort-x86_64.AppImage
```

## Build

Flutter (master channel), Rust stable, GTK 3 dev packages, patchelf,
librsvg dev tooling.

```bash
git clone --recurse-submodules https://github.com/simonlinuxcraft/kyber-linuxport-unofficial.git
cd kyber-linuxport-unofficial/Kyber/Launcher
flutter build linux --release
cd ../..
tools/build-appimage.sh
```

Output ends up in `tools/KyberLinuxPort-x86_64.AppImage`. First build
takes a few minutes (cargo fetch, Rust compile, Flutter bundle).
Subsequent builds are usually around 30 seconds. AppImage packaging
itself adds about a minute.

The master channel moves fast and engine defaults change with it, so the
tested SDK revision is recorded in `tools/flutter-revision`. The build
script warns when your checkout differs; to match it exactly:

```bash
git -C "$(dirname "$(dirname "$(readlink -f "$(command -v flutter)")")")" checkout "$(cat tools/flutter-revision)"
```

## License

GPLv3, see [`LICENSE`](LICENSE). This is a derivative work of the
upstream Kyber and Maxima codebases, both GPLv3. Linux-port changes are
GPLv3-only.

For binary distributions, the corresponding source is this repo at the
release tag. The AppImage embeds a `source-url.txt` pointing back here.
The bundled `wine-helper.exe` from ACowAdonis has its own source offer
in `Kyber/CLI/cli_payload/README.md`.

See [`NOTICE.md`](NOTICE.md) for the full list of third-party components
shipped in the AppImage.

## Contributing

Small one-person project. If you hit a Linux-specific bug, open an issue
here. Don't report Linux-specific bugs to the upstream Kyber team, they
didn't write this part. If you're not sure whether something is
Linux-specific, file it here anyway and I'll redirect if it turns out to
be upstream.
