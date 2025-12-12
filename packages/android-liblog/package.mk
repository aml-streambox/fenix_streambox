PKG_NAME="android-liblog"
PKG_VERSION="amlogic-yocto-1.0"
PKG_SHA256=""
PKG_SOURCE_DIR=""
PKG_SITE=""
PKG_URL=""
PKG_ARCH="arm aarch64"
PKG_LICENSE="Apache-2.0"
PKG_SHORTDESC="Android Logging Library (Amlogic version)"

PKG_NEED_BUILD="YES"

make_target() {
	local pkgdir="$BUILD_IMAGES/.tmp/${PKG_NAME}_${VERSION}_${DISTRIB_ARCH}"
	# Overwrite by recreating directory structure
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
Description: Android Logging Library
 ${PKG_SHORTDESC}
 Provides liblog.so for Android logging functionality.
EOF

	# Build the package using the Makefile in the source
	local PKG_BUILD_DIR="${BUILD}/${PKG_NAME}-${PKG_VERSION}"
	cd "$PKG_BUILD_DIR"
	if [ ! -f Makefile ]; then
		error_msg "Makefile not found in $PKG_BUILD_DIR"
		ls -la "$PKG_BUILD_DIR" || true
		return 1
	fi

	# Set build environment variables as expected by the Makefile
	export OUT_DIR="$PKG_BUILD_DIR"
	export TARGET_DIR="$pkgdir"
	export STAGING_DIR="$PKG_BUILD_DIR/staging"
	export LIBLOG_SRC_DIR="$PKG_BUILD_DIR"
	export STRIP="${CROSS_COMPILE}strip"

	# Create staging directory
	mkdir -p "$STAGING_DIR/usr/lib"
	mkdir -p "$STAGING_DIR/usr/include"

	# The Makefile references -lglibc_bridge and C++ libraries from ./lib
	# These libraries are provided in the sources/lib directory
	# Ensure LIBLOG_SRC_DIR is set so Makefile can find include directory
	
	# Build liblog.so
	info_msg "Building ${PKG_NAME}..."
	make clean 2>/dev/null || true
	
	make all || {
		error_msg "Build failed"
		return 1
	}

	# Install libraries (liblog.so, liblog.so.1, liblog.so.1.0.0)
	if [ -f "$OUT_DIR/liblog.so.1.0.0" ]; then
		install -m 755 "$OUT_DIR/liblog.so.1.0.0" "${pkgdir}/usr/lib/"
		${STRIP} "${pkgdir}/usr/lib/liblog.so.1.0.0" 2>/dev/null || true
		# Create symlinks
		ln -sf liblog.so.1.0.0 "${pkgdir}/usr/lib/liblog.so.1"
		ln -sf liblog.so.1 "${pkgdir}/usr/lib/liblog.so"
	elif [ -f "$OUT_DIR/liblog.so" ]; then
		install -m 755 "$OUT_DIR/liblog.so" "${pkgdir}/usr/lib/"
		${STRIP} "${pkgdir}/usr/lib/liblog.so" 2>/dev/null || true
	else
		error_msg "liblog.so not found after build"
		return 1
	fi

	# Install headers
	if [ -d "$PKG_BUILD_DIR/include" ]; then
		if [ -d "$PKG_BUILD_DIR/include/android" ]; then
			mkdir -p "${pkgdir}/usr/include/android"
			cp -r "$PKG_BUILD_DIR/include/android"/* "${pkgdir}/usr/include/android/" 2>/dev/null || true
		fi
		if [ -d "$PKG_BUILD_DIR/include/cutils" ]; then
			mkdir -p "${pkgdir}/usr/include/cutils"
			cp -r "$PKG_BUILD_DIR/include/cutils"/* "${pkgdir}/usr/include/cutils/" 2>/dev/null || true
		fi
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

