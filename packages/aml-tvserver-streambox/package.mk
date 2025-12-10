PKG_NAME="aml-tvserver-streambox"
PKG_VERSION="58781d31b991032bf3f1822ec9fe2a54ef7237d1"
PKG_SHA256=""
PKG_SOURCE_DIR="aml_tvserver_streambox-${PKG_VERSION}*"
PKG_SITE="https://github.com/anshi233/aml_tvserver_streambox"
PKG_URL="$PKG_SITE/archive/$PKG_VERSION.tar.gz"
PKG_ARCH="arm aarch64"
PKG_LICENSE="Proprietary"
PKG_SHORTDESC="Amlogic TV Server Stream Box"
PKG_SOURCE_NAME="aml_tvserver_streambox-${PKG_VERSION}.tar.gz"
PKG_NEED_BUILD="YES"


make_target() {
	local pkgdir="$BUILD_IMAGES/.tmp/${PKG_NAME}_${VERSION}_${DISTRIB_ARCH}"
	rm -rf $pkgdir
	mkdir -p $pkgdir/DEBIAN

	# Set up control file
	cat <<-EOF > $pkgdir/DEBIAN/control
Package: ${PKG_NAME}
Version: ${VERSION}
Architecture: ${DISTRIB_ARCH}
Maintainer: Khadas <hello@khadas.com>
Depends: 
Section: utils
Priority: optional
Description: Amlogic TV Server Stream Box
 ${PKG_SHORTDESC}
EOF

	# Build the package using the Makefile in the source
	cd $PKG_BUILD_DIR
	if [ -f Makefile ]; then
		# Set STAGING_DIR and TARGET_DIR for the build
		export STAGING_DIR="${STAGING_DIR:-$PKG_BUILD_DIR/staging}"
		export TARGET_DIR="${TARGET_DIR:-$pkgdir}"
		make all
	fi

	# Install built binaries and libraries from the build root directory
	# The Makefile builds: libtvclient.so, libtv.so, tvservice, tvtest in OUT_DIR (root)
	mkdir -p "${pkgdir}"/usr/bin
	mkdir -p "${pkgdir}"/usr/lib

	# Install binaries: tvtest and tvservice
	if [ -f "$PKG_BUILD_DIR/tvtest" ]; then
		install -m 755 "$PKG_BUILD_DIR/tvtest" "${pkgdir}"/usr/bin/
	fi
	if [ -f "$PKG_BUILD_DIR/tvservice" ]; then
		install -m 755 "$PKG_BUILD_DIR/tvservice" "${pkgdir}"/usr/bin/
	fi

	# Install libraries: libtv.so and libtvclient.so
	if [ -f "$PKG_BUILD_DIR/libtv.so" ]; then
		install -m 644 "$PKG_BUILD_DIR/libtv.so" "${pkgdir}"/usr/lib/
	fi
	if [ -f "$PKG_BUILD_DIR/libtvclient.so" ]; then
		install -m 644 "$PKG_BUILD_DIR/libtvclient.so" "${pkgdir}"/usr/lib/
	fi

	info_msg "Building package: $PKG_NAME"
	fakeroot dpkg-deb -b -Zxz $pkgdir ${pkgdir}.deb

	# Cleanup
	rm -rf $pkgdir
}

makeinstall_target() {
	local pkgdir="$BUILD_IMAGES/.tmp/${PKG_NAME}_${VERSION}_${DISTRIB_ARCH}"
	mkdir -p $BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/${PKG_NAME}/
	# Remove old debs
	rm -rf $BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/${PKG_NAME}/*
	cp ${pkgdir}.deb $BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/${PKG_NAME}/ 2>/dev/null || true

	# Cleanup
	rm -f ${pkgdir}.deb
}
