PKG_NAME="aml-ubootenv-dev"
PKG_VERSION="1.0" # Placeholder version
PKG_SHA256=""
PKG_ARCH="aarch64"
PKG_LICENSE="AMLOGIC"
PKG_SHORTDESC="Amlogic U-Boot Environment development files (ubootenv.h, libubootenv.so)"

# This package is a simple wrapper around the headers and library copied from Yocto.
# Sources must already exist under:
#   packages/aml-ubootenv-dev/sources/include/ubootenv.h
#   packages/aml-ubootenv-dev/sources/lib/libubootenv.so
PKG_NEED_BUILD="YES"

make_target() {
	local pkgdir="$BUILD_IMAGES/.tmp/${PKG_NAME}_${VERSION}_${DISTRIB_ARCH}"
	rm -rf "$pkgdir"
	mkdir -p "$pkgdir/DEBIAN"
	mkdir -p "$pkgdir/usr/include"
	mkdir -p "$pkgdir/usr/lib"

	# Control file
	cat <<-EOF > "$pkgdir/DEBIAN/control"
Package: ${PKG_NAME}
Version: ${VERSION}
Architecture: ${DISTRIB_ARCH}
Maintainer: Khadas <hello@khadas.com>
Section: libdevel
Priority: optional
Description: Amlogic U-Boot Environment development files
 ${PKG_SHORTDESC}
EOF

	local SRC_DIR="$PKGS_DIR/$PKG_NAME/sources"
	local SRC_INC_DIR="$SRC_DIR/include"
	local SRC_LIB_DIR="$SRC_DIR/lib"

	# Header
	if [ -f "$SRC_INC_DIR/ubootenv.h" ]; then
		install -m 0644 "$SRC_INC_DIR/ubootenv.h" "$pkgdir/usr/include/" || {
			error_msg "Failed to install ubootenv.h"
			return 1
		}
	else
		error_msg "ubootenv.h not found in $SRC_INC_DIR"
		return 1
	fi

	# Library
	if [ -f "$SRC_LIB_DIR/libubootenv.so" ]; then
		install -m 0644 "$SRC_LIB_DIR/libubootenv.so" "$pkgdir/usr/lib/" || {
			error_msg "Failed to install libubootenv.so"
			return 1
		}
	else
		error_msg "libubootenv.so not found in $SRC_LIB_DIR"
		return 1
	fi

	info_msg "Building Debian package: ${PKG_NAME}"
	fakeroot dpkg-deb -b -Zxz "$pkgdir" "${pkgdir}.deb"

	# Cleanup build root (deb is kept)
	find "$pkgdir" -mindepth 1 -delete 2>/dev/null || true
}

makeinstall_target() {
	local pkgdir="$BUILD_IMAGES/.tmp/${PKG_NAME}_${VERSION}_${DISTRIB_ARCH}"
	mkdir -p "$BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/${PKG_NAME}/"

	# Overwrite any existing debs
	find "$BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/${PKG_NAME}/" -mindepth 1 -delete 2>/dev/null || true
	cp "${pkgdir}.deb" "$BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/${PKG_NAME}/" 2>/dev/null || true

	# Truncate the tmp deb to avoid reusing it
	: > "${pkgdir}.deb" 2>/dev/null || true
}


