PKG_NAME="gstreamer_aml"
PKG_VERSION="72170d4fd09f2c03aa577394d357e32d1e63d200"
PKG_SHA256="b4cb1b5b9b0e353493d383caff257b34e67e914965eaa44de51d9f3332a500db"
PKG_SOURCE_DIR="gstreamer_aml-${PKG_VERSION}*"
PKG_SITE="$GITHUB_URL/numbqq/gstreamer_aml"
PKG_URL="$PKG_SITE/archive/$PKG_VERSION.tar.gz"
PKG_ARCH="arm aarch64"
PKG_LICENSE="GPL"
PKG_SHORTDESC="gstreamer_aml"
PKG_SOURCE_NAME="gstreamer_aml-${PKG_VERSION}.tar.gz"
PKG_NEED_BUILD="NO"


make_target() {
	:
}

makeinstall_target() {
	local dest="$BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/gstreamer_aml"
	local src=""

	mkdir -p "$dest"
	# Remove old debs
	rm -rf "$dest"/*

	if compgen -G "${DISTRIB_RELEASE}/${DISTRIB_ARCH}/*.deb" > /dev/null; then
		src="${DISTRIB_RELEASE}/${DISTRIB_ARCH}"
	elif [ -d "${DISTRIB_RELEASE}/${DISTRIB_ARCH}/${KHADAS_BOARD}/${LINUX}" ]; then
		src="${DISTRIB_RELEASE}/${DISTRIB_ARCH}/${KHADAS_BOARD}/${LINUX}"
	elif [ "$KHADAS_BOARD" = "TVPRO" ] && [ "$LINUX" = "7.1-rc1" ] && [ -d "${DISTRIB_RELEASE}/${DISTRIB_ARCH}/VIM4/5.15" ]; then
		src="${DISTRIB_RELEASE}/${DISTRIB_ARCH}/VIM4/5.15"
	else
		error_msg "No gstreamer_aml debs for ${DISTRIB_RELEASE}/${DISTRIB_ARCH}/${KHADAS_BOARD}/${LINUX}"
		return 1
	fi

	cp -rf "$src"/* "$dest"
}
