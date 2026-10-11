# NOTICE - Kyber Linux Port (top-level)

This top-level repository is the **build / packaging layer** for the
Kyber Linux Port AppImage. The full third-party / vendored-component
notice for the launcher and CLI itself lives in the `Kyber/` submodule:

→ See [`Kyber/NOTICE.md`](Kyber/NOTICE.md) for the per-file notice
covering vendored fonts, ACowAdonis cli_payload binaries, Cargo-patched
crates, modifications relative to upstream Kyber, and the GPLv3 §6(b)
written-offer for `wine-helper.exe`.

The two Maxima submodules each carry their own `CHANGES.md` documenting
the Linux-port modifications relative to upstream
[ArmchairDevelopers/Maxima](https://github.com/ArmchairDevelopers/Maxima):

- `Kyber/ThirdParty/Maxima/CHANGES.md` (launcher tree)
- `Kyber/CLI/ThirdParty/Maxima/CHANGES.md` (CLI tree)

## Top-level files

The files at this top-level (**not** inside `Kyber/`) are first-party
GPL-3.0-only work by simonlinuxcraft:

| Path | Purpose | License |
|---|---|---|
| `tools/build-appimage.sh` | Pipelines the Flutter release bundle into an AppImage | GPL-3.0-only |
| `tools/install-appimage.sh` | Manual desktop-integration installer (fallback for headless setups) | GPL-3.0-only |
| `tools/uninstall-appimage.sh` | Counterpart to install-appimage.sh | GPL-3.0-only |
| `tools/kyber-self-install.sh` | AppRun hook bundled into the AppImage; handles first-start desktop integration | GPL-3.0-only |
| `CHANGELOG.md` | Per-release patch list | (no separate license; GPL-3.0-only as part of aggregate) |
| `README.md`, `NOTICE.md` | This documentation | (same) |

## Build-time tools (vendored, not redistributed in the AppImage)

The `tools/` directory carries two helper AppImages used **only at
build time** to assemble the final Kyber AppImage. They are not
redistributed inside the produced AppImage:

| Path | Project | License | Source |
|---|---|---|---|
| `tools/linuxdeploy-x86_64.AppImage` | linuxdeploy | MIT | <https://github.com/linuxdeploy/linuxdeploy> |
| `tools/linuxdeploy-plugin-gtk.sh` | linuxdeploy-plugin-gtk | MIT | <https://github.com/linuxdeploy/linuxdeploy-plugin-gtk> |
| `tools/appimagetool-x86_64.AppImage` | AppImageKit | MIT | <https://github.com/AppImage/appimagetool> |

See [`THIRD_PARTY_TOOLS.md`](THIRD_PARTY_TOOLS.md) for the full
attribution and download URLs.

## Logo and trademarks

The Linux port logo and launcher icon (`assets/kyber-linux-port-*.svg`)
contain Tux, drawn by Larry Ewing (lewing@isc.tamu.edu) with The GIMP.

Linux is the registered trademark of Linus Torvalds in the U.S. and other
countries.

## Aggregation license

The aggregate work conveyed via this repository (and any AppImage
built from it) is distributed under **GPL-3.0-only**. Vendored files
that originate under `GPL-3.0-or-later` (e.g. ACowAdonis' cli_payload
scripts) retain their original headers; conveying the aggregate as
`GPL-3.0-only` is a permitted choice within an `or-later` upstream
grant.

Per GPLv3 §5(a), modifications to upstream files are documented in
`Kyber/NOTICE.md` and `CHANGELOG.md`.
