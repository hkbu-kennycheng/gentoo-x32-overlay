# gentoo-x32-overlay

A consolidated Gentoo Linux overlay (EAPI 8) extending the main Gentoo repository with custom ebuilds, an overlay profile, and patches for **X32 ABI** support. X32 is an ABI (ILP32 on x86-64) that runs programs with 32-bit pointers while using 64-bit CPU registers and instructions.

This repository consolidates the former `x32-overlay`, `etc-portage-x32`, and `gentoo-x32-docker` repositories into a single tree, with `/etc/portage` configuration (`package.mask`, `package.use`, `patches`) living under `profiles/x32/`.

## Repository Layout

```text
dev-lang/rust-bin/          Rust binary ebuilds with abi_x86_x32 USE flag
dev-python/cryptography/    cryptography wheel builds for the x32 target
dev-util/maturin/           maturin ebuild with x32 support
gnome-base/librsvg/         librsvg with x32 cross-compilation
media-libs/svt-av1/         SVT-AV1 with x32 fixes
eclass/x32-rust.eclass      x32 Rust helpers (env export, ring vendor patches)
profiles/x32/               x32 profile (package.mask, package.use, patches, profile.bashrc)
.devcontainer/              Dev container (stage4:x32-systemd) with the overlay mounted
```

## Installation & Usage

1. Register the overlay in `/etc/portage/repos.conf/x32-overlay.conf`:

   ```bash
   mkdir -p /etc/portage/repos.conf
   cat > /etc/portage/repos.conf/x32-overlay.conf <<'EOF'
   [x32-overlay]
   location = /var/db/repos/x32-overlay
   EOF
   ```

2. Select the overlay profile (inherits `gentoo:default/linux/amd64/23.0/x32/systemd` and sets `ABI_X86="x32 64"`):

   ```bash
   eselect profile set x32-overlay:x32
   ```

3. Symlink the profile's patches, masks, and USE configuration into `/etc/portage`:

   ```bash
   ln -sfn /var/db/repos/x32-overlay/profiles/x32/patches /etc/portage/patches
   mkdir -p /etc/portage/package.mask /etc/portage/package.use
   ln -sfn /var/db/repos/x32-overlay/profiles/x32/package.mask /etc/portage/package.mask/x32-overlay
   ln -sfn /var/db/repos/x32-overlay/profiles/x32/package.use /etc/portage/package.use/x32-overlay
   ```

   `profiles/x32/profile.bashrc` is applied automatically on every emerge when using Portage `>= 3.0.50` (with `profile-bashrcs` support) and falls back to applying overlay patches if `/etc/portage/patches` is not symlinked.

## Verified Packages

Tested in `x32-dev-verify` (`docker.io/kennycheng/gentoo-stage4:x32-systemd`). Built binaries are genuine x32 ELF (`ELF 32-bit LSB ..., x86-64 ..., interpreter /libx32/ld-linux-x32.so.2`):

| Package | Notes |
|---|---|
| `app-misc/jq-1.8.2` | `x32.patch` auto-applied via `eapply_user` (`/etc/portage/patches` symlink) |
| `dev-lang/rust-bin-1.96.1` | Multilib std lands under `/opt/rust-bin-1.96.1/lib/rustlib`; `rustc --target x86_64-unknown-linux-gnux32` emits x32 ELF |
| `dev-util/maturin-1.14.1` | `x32-rust.eclass` patches vendored `ring-0.17.14` for ILP32; upstream `maturin-1.15.0` is masked in `profiles/x32/package.mask/maturin` |
| `dev-python/cryptography-49.0.0` | Built with per-impl wheel dirs (`${T}/wheels-${EPYTHON}`); `import cryptography` and RSA keygen verified |
| `media-libs/svt-av1-4.1.0` | Built with `COMPILE_C_ONLY=ON`; `/usr/libx32/libSvtAv1Enc.so.4.1.0` verified as x32 ELF |
| `gnome-base/librsvg-2.58.5-r1` | Uses `x32-rust.eclass`; `/usr/libx32/librsvg-2.so.2.50.0` and `/usr/bin/rsvg-convert` verified as x32 ELF |

> **Note:** On an x32-native host, `rust-bin` with `ABI_X86="x32 64"` has no standalone std tarball for the non-native x86_64 ABI; the ebuild skips it with `ewarn` while the native pass installs the full toolchain.

## Development

A reproducible dev container is provided in `.devcontainer/` (`compose.yaml` + `Containerfile.dev`) based on `docker.io/kennycheng/gentoo-stage4:x32-systemd`, pre-wired with the overlay, persistent `distfiles`/`binpkgs`/`ccache`/`gentoo` volumes, `tmpfs` on `/var/tmp/portage`, and `gentoolkit`, `pkgdev`, and `pkgcheck`.

For AI agent instructions, ebuild authoring conventions, and container testing workflows, see [`CLAUDE.md`](CLAUDE.md).
