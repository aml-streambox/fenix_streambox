PKG_NAME="libexpat1-dev"
PKG_VERSION="2.6.1-2ubuntu0.3"
PKG_SHA256=""
PKG_SOURCE_DIR=""
PKG_SITE=""
PKG_URL=""
PKG_ARCH="arm aarch64"
PKG_LICENSE="MIT"
PKG_SHORTDESC="Expat XML parser development headers (transitional package, uses libexpat1)"

# Transitional/no-op package.
# All headers and libraries are provided directly by libexpat1.
# We keep this package only to satisfy any legacy Depends.
PKG_NEED_BUILD="YES"

make_target() {
	local pkgdir="$BUILD_IMAGES/.tmp/${PKG_NAME}_${VERSION}_${DISTRIB_ARCH}"
	# Overwrite by recreating directory structure
	mkdir -p $pkgdir/DEBIAN

	# Set up control file (transitional, no files installed)
	cat <<-EOF > $pkgdir/DEBIAN/control
Package: ${PKG_NAME}
Version: ${VERSION}
Architecture: ${DISTRIB_ARCH}
Maintainer: Khadas <hello@khadas.com>
Depends: libexpat1 (= ${VERSION})
Section: libdevel
Priority: optional
Description: Expat XML parser development files (transitional)
 ${PKG_SHORTDESC}
 This transitional package depends on libexpat1, which now provides both
 the runtime library and development headers.
EOF

	info_msg "libexpat1-dev is now a transitional package; no files installed."

	# Build empty deb
	info_msg "Building Debian package: $PKG_NAME"
	fakeroot dpkg-deb -b -Zxz $pkgdir ${pkgdir}.deb
	
	# Overwrite package directory contents instead of removing
	find $pkgdir -mindepth 1 -delete 2>/dev/null || true
}

makeinstall_target() {
	local pkgdir="$BUILD_IMAGES/.tmp/${PKG_NAME}_${VERSION}_${DISTRIB_ARCH}"
	mkdir -p $BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/${PKG_NAME}/
	# Overwrite old debs by deleting contents
	find $BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/${PKG_NAME}/ -mindepth 1 -delete 2>/dev/null || true
	cp ${pkgdir}.deb $BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/${PKG_NAME}/ 2>/dev/null || true

	# Overwrite deb file instead of removing
	: > ${pkgdir}.deb 2>/dev/null || true
}

