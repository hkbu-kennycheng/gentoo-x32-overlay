# gentoo-x32-overlay

A consolidated Gentoo Linux overlay (EAPI 8) that extends the main Gentoo
repository with custom ebuilds, an overlay profile, and patches for **X32 ABI**
support. X32 is an ABI (ILP32 on x86-64) that allows programs to run with
32-bit pointers while taking advantage of 64-bit CPU features.

This repository merges the former three-repository layout
(`x32-overlay`, `etc-portage-x32`, `gentoo-x32-docker`) into a single
repository (Option A consolidation). The `etc-portage-x32` content
(package.mask, package.use, patches) lives under `profiles/x32/` with full
commit history preserved via `git subtree`.

## Layout

```
dev-lang/rust-bin/          Rust binary ebuilds with abi_x86_x32 USE flag
dev-python/cryptography/    cryptography wheel builds for the x32 target
dev-util/maturin/           maturin ebuild with x32 support
gnome-base/librsvg/         librsvg with x32 cross-compilation
media-libs/svt-av1/         SVT-AV1 with x32 fixes
eclass/x32-rust.eclass      x32 Rust helpers (env export, ring vendor patches)
profiles/x32/               x32 profile: package.mask, package.use, patches, profile.bashrc
.devcontainer/              Dev container (stage4:x32-systemd) with the overlay mounted
```

## Usage

Add the overlay to a Gentoo x32 system (or container):

```bash
mkdir -p /etc/portage/repos.conf
cat > /etc/portage/repos.conf/x32-overlay.conf <<EOF
[x32-overlay]
location = /var/db/repos/x32-overlay
EOF
```

Wire up the profile configuration:

```bash
ln -sfn /var/db/repos/x32-overlay/profiles/x32/patches /etc/portage/patches
mkdir -p /etc/portage/package.mask /etc/portage/package.use
ln -sfn /var/db/repos/x32-overlay/profiles/x32/package.mask /etc/portage/package.mask/x32-overlay
ln -sfn /var/db/repos/x32-overlay/profiles/x32/package.use /etc/portage/package.use/x32-overlay
```

`profiles/x32/profile.bashrc` is applied automatically to every emerge when the
repository is synced by a Portage version supporting `profile-bashrcs`
(>= 3.0.50). It also creates the `/etc/portage/patches` symlink on the fly when
missing.

## Development

See `CLAUDE.md` for the development workflow, x32 ebuild patterns, and
container-based testing instructions. A devcontainer is provided in
`.devcontainer/` (`compose.yaml` + `Containerfile.dev`) based on
`docker.io/kennycheng/gentoo-stage4:x32-systemd`.
