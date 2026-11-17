# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a consolidated Gentoo Linux overlay (`x32-overlay`, EAPI 8) providing custom ebuilds, an overlay profile, and user patches for X32 ABI (ILP32 on x86-64) support. User-facing installation instructions are in `README.md`; this file documents internal architecture, ebuild conventions, and testing workflows.

```text
dev-lang/rust-bin/          # Rust compiler binary ebuilds with abi_x86_x32 USE flag
dev-python/cryptography/    # Python cryptography with Rust extensions, x32-targeted builds
gnome-base/librsvg/         # SVG rendering library with Rust components, x32 cross-compile
dev-util/maturin/           # Maturin ebuilds with x32 ABI support
media-libs/svt-av1/         # AV1 encoder with x32 fixes
eclass/x32-rust.eclass      # x32 Rust cross-compile helpers (env export + ring vendor patches)
metadata/layout.conf        # Overlay config (thin-manifests, masters = gentoo, profile-bashrcs)
profiles/                   # Overlay metadata (repo_name, eapi, profiles.desc)
profiles/x32/               # x32 profile: parent, make.defaults, package.mask/, package.use/, patches/, profile.bashrc
.devcontainer/              # Dev container (Containerfile.dev + compose.yaml) for testing
```

## Overlay Configuration & Profile Internals

- **EAPI 8** with `thin-manifests` enabled, `masters = gentoo`, and `profile-formats = portage-2 profile-bashrcs` (`metadata/layout.conf`). Manifests do not require signing for local development.
- **`profiles/profiles.desc` + `profiles/x32/parent`**: exposes `x32-overlay:x32` (`amd64 x32 stable`) inheriting `gentoo:default/linux/amd64/23.0/x32/systemd`.
- **`profiles/x32/make.defaults`**: sets `ABI_X86="x32 64"` (x32-native hosts still need 64-bit enabled for packages with `REQUIRED_USE="abi_x86_x32? ( abi_x86_64 )"`).
- **`profiles/x32/package.mask/`**: masks `>x11-themes/adwaita-icon-theme-3.32.0`, `<dev-lang/ruby-3.3.0`, and unpatched upstream `dev-util/maturin-1.15.0`.
- **`profiles/x32/package.use/`**: keyword-specific USE flags (cairo/libglvnd `X`, freetype `harfbuzz`, libaom SIMD off).
- **`profiles/x32/patches/`**: `eapply_user` layout (`patches/<category>/<pkg-version>/x32.patch`).
  - Version-agnostic symlinks (e.g. `app-misc/jq` -> `jq-1.8.2`, `dev-lang/ruby` -> `ruby-3.3.11`) keep minor `::gentoo` bumps working.
  - OpenMP dedup symlinks: `openmp-16.0.6` and `openmp-17.0.6` -> `../openmp-15.0.7-r2/x32.patch`; `openmp-20.1.8` -> `../openmp-20.1.7/x32.patch`.
- **`profiles/x32/profile.bashrc`**:
  - `pre_src_prepare` applies `${CATEGORY}/${P}` and `${CATEGORY}/${PN}` patches directly when `/etc/portage/patches` does not resolve to the overlay patch tree (`eapply_user` covers the symlinked case). Idempotent: a per-`${PF}` marker in `${T}` guards against double invocation from nested `src_prepare` chains, and `realpath` dedup handles `${PN}`-symlink-to-`${P}` collisions.
  - `post_src_prepare` initializes a transient git repo in `${S}` (`x32 baseline <PF>`) when `X32_GIT_PATCH=1` for `git diff`-based patch creation.
  - **Constraint**: `/etc/portage/patches` cannot be symlinked from `src_prepare` (runs unprivileged under `FEATURES=userpriv`); it must be wired at container/system provisioning time (see `.devcontainer/Containerfile.dev`).

## Development & Container Testing Workflow

Test changes in the x32 container (see `.devcontainer/` for the compose setup with persistent `distfiles`/`binpkgs`/`ccache`/`gentoo` volumes and 16 GB `tmpfs` on `/var/tmp/portage`):

```bash
# Run the active container
podman run -it --rm --name x32-test \
  -v $(pwd):/var/db/repos/x32-overlay:Z \
  docker.io/kennycheng/gentoo-stage4:x32-systemd bash

# Sync portage & register overlay
podman exec x32-test bash -c 'emerge-webrsync'
podman exec x32-test bash -c 'mkdir -p /etc/portage/repos.conf && printf "[x32-overlay]\nlocation = /var/db/repos/x32-overlay\n" > /etc/portage/repos.conf/x32-overlay.conf'

# Wire up profile config (patches/masks/USE)
podman exec x32-test bash -c 'ln -sfn /var/db/repos/x32-overlay/profiles/x32/patches /etc/portage/patches'
podman exec x32-test bash -c 'mkdir -p /etc/portage/package.mask /etc/portage/package.use'
podman exec x32-test bash -c 'ln -sfn /var/db/repos/x32-overlay/profiles/x32/package.mask /etc/portage/package.mask/x32-overlay'
podman exec x32-test bash -c 'ln -sfn /var/db/repos/x32-overlay/profiles/x32/package.use /etc/portage/package.use/x32-overlay'

# Generate ebuild Manifest
podman exec x32-test bash -c 'cd /var/db/repos/x32-overlay/dev-util/maturin && ebuild maturin-1.14.1.ebuild digest'

# Test emerging a package and verify x32 ELF binaries
podman exec x32-test bash -c 'emerge --oneshot maturin'
podman exec x32-test bash -c 'equery files maturin | grep -v ".pyc" | xargs file | grep -E "x86-64|x32|gnux32"'
```

### QA (`pkgcheck`)

Run `pkgcheck scan` inside the container (with `repos.conf/gentoo.conf` present). Known non-overlay findings to ignore:
- Upstream-inherited `sparc` `NonsolvableDepsInStable` and `PotentialStable` keywording.
- Tree-skew artifacts (e.g. `svt-av1` `pgo`/`tools` USE flags missing from older container `use.local.desc`).

## X32-Specific Ebuild Patterns

**USE flags:**
- Add `abi_x86_x32` to `IUSE` for packages that benefit from x32 ABI.
- Add `REQUIRED_USE="abi_x86_x32? ( abi_x86_64 )"` where x32 is an alternate ABI for amd64.

**Rust packages (`eclass/x32-rust.eclass`):**
- `x32_rust_is_x32`: detects x32 builds (`${ABI} == "x32"`).
- `x32_rust_export_env`: exports `CARGO_BUILD_TARGET=x86_64-unknown-linux-gnux32`, `RUST_TARGET`, `PKG_CONFIG_SYSROOT_DIR=/`, `cross_compiling=yes`, and `PYO3_CROSS_LIB_DIR=/usr/lib/${EPYTHON}`.
- `x32_rust_patch_ring_vendor`: patches vendored `ring-*` crates for ILP32 and updates `.cargo-checksum.json` / `Cargo.lock` (no-op when no `ring` crate is vendored).
- For `maturin` builds: use `DISTUTILS_ARGS=( --target "${X32_RUST_TARGET}" )`, pass `--out "${T}/wheels-${EPYTHON}"` to `maturin pep517 build-wheel`, and install `"${T}"/wheels-"${EPYTHON}"/*.whl` (per-impl dir prevents `abi3` wheel collisions across Python impls; do not parse stdout).

**Multilib packages:**
- Use `multilib-minimal` or `multilib-is-native-abi` patterns.
- Set `cross_compiling=yes` when building for x32 ABI so configure scripts select the right target.
- Note for `rust-bin`: on an x32-native host, `ABI_X86="x32 64"` has no standalone std tarball for the non-native x86_64 ABI; skip with `ewarn`.

**Patches:**
- Package-local patches go in `files/` and are referenced via `PATCHES=( "${FILESDIR}"/<patch-name>.patch )`.
- Cross-package x32 fixes go in `profiles/x32/patches/` (auto-applied via `eapply_user` or `profile.bashrc`).

## Key x32 Technical Patterns

- **Ruby coroutine selection (`configure.ac`)**: Gentoo ebuild forces `--with-coroutine=amd64` on x32 CHOSTs, which uses 8-byte `movq` on stack pointers despite x32 having 4-byte pointers. Override to `ucontext` after the ebuild's forced option using `AC_CHECK_FUNCS([getcontext swapcontext makecontext])` when `ac_cv_sizeof_voidp=4`.
- **LLVM OpenMP (`kmp.h`, `LibompHandleFlags.cmake`)**: Add `KMP_ARCH_X86_X32` to existing `KMP_ARCH_X86_64` conditionals, select `-mx32` where appropriate, and account for `ld-linux-x32.so.2` in expected library deps.
- **Rust `ring` crate (ILP32 pointer width)**:
  - `src/cpu/intel.rs`: pointer-size assertion must be 4 on x32.
  - `src/arithmetic/limbs/x86_64/mont.rs`: `8 * Limb::BITS == 512` fails (32-bit limbs on x32).
  - All `cfg(target_arch = "x86_64")` gates need `target_pointer_width = "64"` added (handled automatically by `x32_rust_patch_ring_vendor`).
- **General**: x32 defines `__ILP32__` (32-bit pointers, `SIZEOF_VOIDP=4`, 8-byte stack slots, 64-bit GPRs; vs `x86_64` with `SIZEOF_VOIDP=8`).

## Ruby-Specific Validation

After a Ruby rebuild, verify the coroutine backend:

```bash
grep COROUTINE_H /usr/include/ruby-3.*/x86_64-linux-x32/ruby/config.h

RUBYOPT="" ruby33 -e 'f = Fiber.new { |x| (1..10000).each { |i| Fiber.yield i*x }; :done }; puts (1..10000).map { |i| f.resume(i) }.size; puts f.resume(1)'
```
