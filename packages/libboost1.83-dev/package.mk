PKG_NAME="libboost1.83-dev"
PKG_VERSION="1.83.0-2.1ubuntu3.1"
PKG_SHA256=""
PKG_SOURCE_DIR=""
PKG_SITE=""
PKG_URL=""
PKG_ARCH="arm aarch64"
PKG_LICENSE="BSL-1.0"
PKG_SHORTDESC="Boost C++ Libraries development files (headers are architecture-independent)"

PKG_NEED_BUILD="YES"

make_target() {
	local pkgdir="$BUILD_IMAGES/.tmp/${PKG_NAME}_${VERSION}_${DISTRIB_ARCH}"
	# Overwrite by recreating directory structure
	mkdir -p $pkgdir/DEBIAN

	# Set up control file
	cat <<-EOF > $pkgdir/DEBIAN/control
Package: ${PKG_NAME}
Version: ${VERSION}
Architecture: ${DISTRIB_ARCH}
Maintainer: Khadas <hello@khadas.com>
Depends: 
Section: libdevel
Priority: optional
Description: Boost C++ Libraries development files
 ${PKG_SHORTDESC}
 This package provides headers for all Boost libraries.
 Note: Headers are architecture-independent. Runtime libraries (libboost1.83.0, libboost-system1.83.0, etc.)
 are installed separately as needed by dependent packages (e.g., aml-audio-utils needs libboost-system1.83.0).
EOF

	# Copy from local sources directory
	local PKG_DIR="$PKGS_DIR/$PKG_NAME"
	if [ ! -d "$PKG_DIR/sources/usr" ]; then
		error_msg "Local sources not found at $PKG_DIR/sources/usr"
		error_msg "Please ensure boost headers are extracted to packages/libboost1.83-dev/sources/usr/"
		return 1
	fi

	info_msg "Copying boost headers from local sources..."
	
	# Copy headers (architecture-independent)
	if [ -d "$PKG_DIR/sources/usr/include" ]; then
		mkdir -p "$pkgdir/usr/include"
		cp -r "$PKG_DIR/sources/usr/include/"* "$pkgdir/usr/include/" 2>/dev/null || true
	fi
	
	# Copy pkg-config files if any
	if [ -d "$PKG_DIR/sources/usr/lib/pkgconfig" ]; then
		mkdir -p "$pkgdir/usr/lib/pkgconfig"
		cp -r "$PKG_DIR/sources/usr/lib/pkgconfig/"* "$pkgdir/usr/lib/pkgconfig/" 2>/dev/null || true
	fi
	
	# Copy cmake files if any
	if [ -d "$PKG_DIR/sources/usr/lib/cmake" ]; then
		mkdir -p "$pkgdir/usr/lib/cmake"
		cp -r "$PKG_DIR/sources/usr/lib/cmake/"* "$pkgdir/usr/lib/cmake/" 2>/dev/null || true
	fi
	
	# Copy any other development files
	if [ -d "$PKG_DIR/sources/usr/lib" ]; then
		mkdir -p "$pkgdir/usr/lib"
		# Only copy static libraries and symlinks, not shared libraries (those come from libboost1.83.0)
		find "$PKG_DIR/sources/usr/lib" -type f \( -name "*.a" -o -name "*.cmake" \) -exec cp --parents {} "$pkgdir/" \; 2>/dev/null || true
	fi
	
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
