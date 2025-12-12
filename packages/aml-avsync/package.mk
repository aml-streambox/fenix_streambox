PKG_NAME="aml-avsync"
PKG_VERSION="amlogic-yocto-1.0"
PKG_SHA256=""
PKG_SOURCE_DIR=""
PKG_SITE=""
PKG_URL=""
PKG_ARCH="arm aarch64"
PKG_LICENSE="AMLOGIC"
PKG_SHORTDESC="Amlogic Audio/Video Synchronization Library"

PKG_NEED_BUILD="YES"

make_target() {
	local pkgdir="$BUILD_IMAGES/.tmp/${PKG_NAME}_${VERSION}_${DISTRIB_ARCH}"
	rm -rf $pkgdir
	mkdir -p $pkgdir/DEBIAN
	mkdir -p $pkgdir/usr/lib
	mkdir -p $pkgdir/usr/include

	# Set up control file
	cat <<-EOF > $pkgdir/DEBIAN/control
Package: ${PKG_NAME}
Version: ${VERSION}
Architecture: ${DISTRIB_ARCH}
Maintainer: Khadas <hello@khadas.com>
Depends: 
Section: libs
Priority: optional
Description: Amlogic AV Sync Library
 ${PKG_SHORTDESC}
 Provides libamlavsync.so for audio/video synchronization.
EOF

	# Build the package using the Makefile in the source
	local PKG_BUILD_DIR="${BUILD}/${PKG_NAME}-${PKG_VERSION}"
	local OUT_DIR="$PKG_BUILD_DIR/src"
	
	cd "$PKG_BUILD_DIR"
	if [ ! -f Makefile ]; then
		error_msg "Makefile not found in $PKG_BUILD_DIR"
		ls -la "$PKG_BUILD_DIR" || true
		return 1
	fi

	# Set build environment variables as expected by the Makefile
	export OUT_DIR="$OUT_DIR"
	export STAGING_DIR="$PKG_BUILD_DIR/staging"
	export TARGET_DIR="$pkgdir"
	export TARGET_CFLAGS="${CFLAGS}"
	export STRIP="${CROSS_COMPILE}strip"

	# Create staging directory
	mkdir -p "$STAGING_DIR/usr/lib"
	mkdir -p "$STAGING_DIR/usr/include"
	mkdir -p "$OUT_DIR"

	# Run version_config.sh script first (as per Yocto recipe)
	if [ -f "$PKG_BUILD_DIR/version_config.sh" ]; then
		info_msg "Running version_config.sh..."
		bash "$PKG_BUILD_DIR/version_config.sh" "$OUT_DIR" || {
			error_msg "version_config.sh failed"
			return 1
		}
	fi

	# Build libamlavsync.so
	info_msg "Building ${PKG_NAME}..."
	cd "$PKG_BUILD_DIR/src"
	make clean 2>/dev/null || true
	make all || {
		error_msg "Build failed"
		return 1
	}

	# Install library
	if [ -f "$OUT_DIR/libamlavsync.so" ]; then
		install -m 644 "$OUT_DIR/libamlavsync.so" "${pkgdir}/usr/lib/"
		${STRIP} "${pkgdir}/usr/lib/libamlavsync.so" 2>/dev/null || true
	else
		error_msg "libamlavsync.so not found after build"
		return 1
	fi

	# Install headers (as per Yocto recipe)
	if [ -f "$PKG_BUILD_DIR/src/aml_avsync.h" ]; then
		install -m 644 "$PKG_BUILD_DIR/src/aml_avsync.h" "${pkgdir}/usr/include/"
	fi
	if [ -f "$PKG_BUILD_DIR/src/aml_avsync_log.h" ]; then
		install -m 644 "$PKG_BUILD_DIR/src/aml_avsync_log.h" "${pkgdir}/usr/include/"
	fi

	info_msg "Building Debian package: $PKG_NAME"
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

