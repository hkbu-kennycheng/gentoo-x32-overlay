# profiles/x32/profile.bashrc
#
# Auto-apply x32 user patches and provide a transient git repo helper for
# rapid patch creation.
#
# This file is sourced into the ebuild environment via the profile-formats
# `profile-bashrcs` mechanism (see metadata/layout.conf).

x32_patches_dir() {
	# Canonical location of the x32 patch tree inside this overlay.
	# Overridable via X32_PATCHES_DIR for tests/containers with custom paths.
	echo "${X32_PATCHES_DIR:-/var/db/repos/x32-overlay/profiles/x32/patches}"
}

x32_link_user_patches() {
	# Symlink /etc/portage/patches at the overlay's patch tree so Portage's
	# eapply_user picks up x32 patches automatically. Only create the link
	# when /etc/portage/patches is absent (do not clobber user configuration).
	local patches_src="$(x32_patches_dir)"
	local patches_dst="${EROOT}/etc/portage/patches"

	[[ -d ${patches_src} ]] || return 0

	if [[ ! -e ${patches_dst} && ! -L ${patches_dst} ]]; then
		mkdir -p "${EROOT}/etc/portage" 2>/dev/null || return 0
		if ln -snf "${patches_src}" "${patches_dst}" 2>/dev/null; then
			einfo "Linked ${patches_dst} -> ${patches_src}"
		fi
	fi
}

x32_apply_overlay_patches() {
	# Manually apply x32 patches when /etc/portage/patches is not symlinked
	# to the overlay's patch tree (in which case eapply_user in the ebuild's
	# default src_prepare already handles them).
	local patches_src="$(x32_patches_dir)"

	[[ -L ${EROOT}/etc/portage/patches ]] && return 0

	local d
	for d in "${patches_src}/${CATEGORY}/${P}" \
		 "${patches_src}/${CATEGORY}/${PF}" \
		 "${patches_src}/${CATEGORY}/${PN}"; do
		if [[ -d ${d} ]]; then
			local f
			for f in "${d}"/*.patch; do
				[[ -f ${f} ]] || continue
				einfo "Applying x32 patch: ${f#${patches_src}/}"
				(cd "${S}" && eapply "${f}") || \
					die "Failed to apply x32 patch: ${f}"
			done
		fi
	done
	return 0
}

x32_post_src_prepare() {
	# When X32_GIT_PATCH=1, initialize a transient git repo in ${S} so that
	# `git diff` produces clean patches against the pristine sources.
	if [[ ${X32_GIT_PATCH} == 1 && ! -e ${S}/.git ]]; then
		(
			cd "${S}" || return 0
			git init -q . 2>/dev/null || return 0
			git add -A 2>/dev/null || return 0
			git -c user.email=x32@gentoo.org -c user.name="x32-dev" \
				commit -qm "x32 baseline ${PF}" 2>/dev/null
		)
		einfo "Initialized transient git repo in ${S} (X32_GIT_PATCH=1)"
	fi
	return 0
}

pre_src_prepare() {
	x32_link_user_patches
	x32_apply_overlay_patches
	return 0
}

post_src_prepare() {
	x32_post_src_prepare
	return 0
}
