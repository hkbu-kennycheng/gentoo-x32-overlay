# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2
#
# @ECLASS: x32-rust.eclass
# @MAINTAINER:
# Gentoo x32 project
# @SUPPORTED_EAPIS: 8
# @BLURB: Helpers for building Rust crates for the x32 ABI
# @DESCRIPTION:
# Helpers for building Rust crates for the x32 ABI
# (x86_64-unknown-linux-gnux32, ILP32 on x86-64). Provides:
#
#   x32_rust_export_env        - export cross-compilation environment variables
#   x32_rust_patch_ring_vendor - patch vendored ring-* crates for ILP32
#
# x32 is an x86_64 CPU ABI with 32-bit pointers. Most Rust crates assume
# target_arch = "x86_64" implies 64-bit pointers, which breaks on x32.

case ${EAPI} in
	8) ;;
	*) die "${ECLASS}: EAPI ${EAPI} not supported" ;;
esac

# @ECLASS_VARIABLE: X32_RUST_TARGET
# @DESCRIPTION:
# The Rust target triple used for x32 builds.
: "${X32_RUST_TARGET:=x86_64-unknown-linux-gnux32}"

# @ECLASS_VARIABLE: X32_RING_CRATE
# @DESCRIPTION:
# Name (with version) of the vendored ring crate to patch, e.g. "ring-0.17.14".
# Auto-discovered from ${S}/vendor when unset.
: "${X32_RING_CRATE:=}"

# @FUNCTION: x32_rust_is_x32
# @DESCRIPTION:
# Returns 0 when the current build is an x32 ABI build.
x32_rust_is_x32() {
	use abi_x86_x32 || [[ ${ABI} == x32 ]]
}

# @FUNCTION: x32_rust_export_env
# @DESCRIPTION:
# Export the environment variables required to cross-compile Rust crates
# for the x32 ABI. No-op on non-x32 builds.
x32_rust_export_env() {
	x32_rust_is_x32 || return 0

	export CARGO_BUILD_TARGET="${X32_RUST_TARGET}"
	export RUST_TARGET="${X32_RUST_TARGET}"
	export PKG_CONFIG_SYSROOT_DIR=/
	export cross_compiling=yes

	if [[ -n ${EPYTHON} ]]; then
		export PYO3_CROSS_LIB_DIR="/usr/lib/${EPYTHON}"
	fi

	einfo "x32-rust: target=${CARGO_BUILD_TARGET} cross_compiling=yes"
}

# @FUNCTION: x32_rust_patch_ring_vendor
# @DESCRIPTION:
# Patch a vendored ring-* crate so it builds on x32 (ILP32):
#
#   1. src/cpu/intel.rs: relax the pointer-size assertion to 4 bytes on
#      x32 (target_pointer_width = "32").
#   2. src/arithmetic/limbs/x86_64/mont.rs: neutralize the
#      "8 * Limb::BITS == 512" assertion (on x32 Limb::BITS is 32).
#   3. All files: rewrite cfg gates 'target_arch = "x86_64"' to
#      'all(target_arch = "x86_64", target_pointer_width = "64")' so the
#      x86_64 SIMD/asm backends are only selected on true 64-bit targets.
#   4. Regenerate .cargo-checksum.json file checksums and update the
#      ring entry in Cargo.lock so cargo accepts the vendored tree.
#
# No-op on non-x32 builds. Auto-discovers the ring crate under ${S}/vendor
# when X32_RING_CRATE is unset.
x32_rust_patch_ring_vendor() {
	x32_rust_is_x32 || return 0

	local ring_dir=""

	if [[ -n ${X32_RING_CRATE} ]]; then
		ring_dir="${S}/vendor/${X32_RING_CRATE}"
		[[ -d ${ring_dir} ]] || die "x32-rust: vendored crate not found: ${ring_dir}"
	else
		local d
		for d in "${S}"/vendor/ring-*; do
			[[ -d ${d} ]] || continue
			[[ -n ${ring_dir} ]] && die "x32-rust: multiple ring-* crates vendored, set X32_RING_CRATE"
			ring_dir="${d}"
		done
		# Not all Rust crates vendor ring; when none is found there is
		# nothing to patch (only an explicit X32_RING_CRATE is required).
		if [[ -z ${ring_dir} ]]; then
			einfo "x32-rust: no ring-* crate vendored, skipping ring patch"
			return 0
		fi
	fi

	einfo "x32-rust: patching vendored ring crate: ${ring_dir##*/}"

	python3 - "${ring_dir}" "${S}/Cargo.lock" <<'PYEOF' || die "x32-rust: failed to patch vendored ring crate"
import hashlib
import json
import os
import re
import sys

ring_dir, cargo_lock = sys.argv[1], sys.argv[2]

# 1. src/cpu/intel.rs: relax pointer-size assertion for ILP32.
intel_rs = os.path.join(ring_dir, "src/cpu/intel.rs")
if os.path.exists(intel_rs):
    with open(intel_rs) as f:
        content = f.read()
    old = '#[cfg(target_arch = "x86_64")]\n    const _ASSUMED_POINTER_SIZE: usize = 8;'
    new = (
        '#[cfg(all(target_arch = "x86_64", target_pointer_width = "64"))]\n'
        '    const _ASSUMED_POINTER_SIZE: usize = 8;\n'
        '    #[cfg(all(target_arch = "x86_64", target_pointer_width = "32"))]\n'
        '    const _ASSUMED_POINTER_SIZE: usize = 4;'
    )
    if old in content:
        content = content.replace(old, new)
        with open(intel_rs, "w") as f:
            f.write(content)

# 2. Neutralize the Limb::BITS assertion in x86_64 mont.rs.
mont_rs = os.path.join(ring_dir, "src/arithmetic/limbs/x86_64/mont.rs")
if os.path.exists(mont_rs):
    with open(mont_rs) as f:
        content = f.read()
    content = content.replace(
        "const _512_IS_LIMB_BITS_TIMES_8: () = assert!(8 * Limb::BITS == 512);",
        "// x32-compatible: Limb::BITS is 32 on x32, 64 on x86_64.\n"
        "const _512_IS_LIMB_BITS_TIMES_8: () = ();",
    )
    with open(mont_rs, "w") as f:
        f.write(content)

# 3. Gate all x86_64 cfgs on 64-bit pointers.
old = 'target_arch = "x86_64"'
new = 'all(target_arch = "x86_64", target_pointer_width = "64")'
for root, dirs, files in os.walk(ring_dir):
    for fn in files:
        if not fn.endswith(".rs"):
            continue
        fpath = os.path.join(root, fn)
        with open(fpath) as f:
            content = f.read()
        if old in content:
            content = content.replace(old, new)
            with open(fpath, "w") as f:
                f.write(content)

# 4. Regenerate .cargo-checksum.json and update Cargo.lock.
files = {}
all_content = b""
for root, dirs, filenames in os.walk(ring_dir):
    for fn in filenames:
        if fn in (".cargo-checksum.json", ".cargo_vcs_info.json"):
            continue
        fpath = os.path.join(root, fn)
        relpath = os.path.relpath(fpath, ring_dir)
        with open(fpath, "rb") as f:
            content = f.read()
        files[relpath.replace(os.sep, "/")] = hashlib.sha256(content).hexdigest()
        all_content += content
package_checksum = hashlib.sha256(all_content).hexdigest()

checksum_path = os.path.join(ring_dir, ".cargo-checksum.json")
if os.path.exists(checksum_path):
    with open(checksum_path) as f:
        checksum_data = json.load(f)
    checksum_data["files"] = files
    checksum_data["package"] = package_checksum
    with open(checksum_path, "w") as f:
        json.dump(checksum_data, f, separators=(",", ":"))

if os.path.exists(cargo_lock):
    with open(cargo_lock) as f:
        lock = f.read()
    # Cargo.lock v4 registry entries include a "source" line between
    # "version" and "checksum"; it must be matched optionally.
    lock = re.sub(
        r'(name = "ring"\nversion = "[^"]+"\n(?:source = "[^"]*"\n)?checksum = )"[^"]*"',
        r'\g<1>"{}"'.format(package_checksum),
        lock,
    )
    with open(cargo_lock, "w") as f:
        f.write(lock)
PYEOF

	einfo "x32-rust: vendored ring patched for ILP32"
}
