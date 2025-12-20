PKG_NAME="libprotobuf32t64"
PKG_VERSION="3.21.12-8.2ubuntu0.2"
PKG_SHA256=""
PKG_SOURCE_DIR=""
PKG_SITE=""
PKG_URL=""
PKG_ARCH="arm aarch64"
PKG_LICENSE="BSD-3-Clause"
PKG_SHORTDESC="Protocol Buffers C++ library (runtime)"

PKG_NEED_BUILD="YES"

	make_target() {
		local pkgdir="$BUILD_IMAGES/.tmp/${PKG_NAME}_${PKG_VERSION}_${DISTRIB_ARCH}"
		# Overwrite by recreating directory structure
		mkdir -p $pkgdir/DEBIAN

		# Set up control file
		cat <<-EOF > $pkgdir/DEBIAN/control
Package: ${PKG_NAME}
Version: ${PKG_VERSION}
Architecture: ${DISTRIB_ARCH}
Maintainer: Khadas <hello@khadas.com>
Depends: 
Section: libs
Priority: optional
Description: Protocol Buffers C++ library (runtime)
 ${PKG_SHORTDESC}
 This package provides libprotoc.so.32 and libprotobuf.so.32 runtime libraries.
 Note: For host architecture (amd64) runtime libraries used during build.
 Includes header files in /usr/include for development purposes.
EOF

	# Copy from local sources directory
	local PKG_DIR="$PKGS_DIR/$PKG_NAME"
	if [ ! -d "$PKG_DIR/sources/usr" ]; then
		error_msg "Local sources not found at $PKG_DIR/sources/usr"
		error_msg "Please ensure libprotobuf32t64 files are extracted to packages/libprotobuf32t64/sources/usr/"
		error_msg "Extract from libprotobuf32t64_3.21.12-8.2ubuntu0.2_amd64.deb:"
		error_msg "  dpkg-deb -x libprotobuf32t64_3.21.12-8.2ubuntu0.2_amd64.deb packages/libprotobuf32t64/sources/"
		return 1
	fi

	info_msg "Copying libprotobuf32t64 from local sources..."
	
	# Copy shared libraries (for host architecture - needed for protoc runtime)
	# Note: This package provides runtime libraries for the host build system (amd64)
	if [ -d "$PKG_DIR/sources/usr/lib/x86_64-linux-gnu" ]; then
		mkdir -p "$pkgdir/usr/lib/x86_64-linux-gnu"
		find "$PKG_DIR/sources/usr/lib/x86_64-linux-gnu" \( -name "libprotoc.so*" -o -name "libprotobuf.so*" \) 2>/dev/null | while read lib; do
			if [ -e "$lib" ]; then
				cp -L "$lib" "$pkgdir/usr/lib/x86_64-linux-gnu/" 2>/dev/null || cp "$lib" "$pkgdir/usr/lib/x86_64-linux-gnu/" 2>/dev/null || true
			fi
		done
	fi
	if [ -d "$PKG_DIR/sources/usr/lib" ]; then
		mkdir -p "$pkgdir/usr/lib"
		find "$PKG_DIR/sources/usr/lib" \( -name "libprotoc.so*" -o -name "libprotobuf.so*" \) 2>/dev/null | while read lib; do
			if [ -e "$lib" ]; then
				cp -L "$lib" "$pkgdir/usr/lib/" 2>/dev/null || cp "$lib" "$pkgdir/usr/lib/" 2>/dev/null || true
			fi
		done
	fi

	# Copy development headers (if present in sources)
	if [ -d "$PKG_DIR/sources/usr/include" ]; then
		mkdir -p "$pkgdir/usr/include"
		cp -r "$PKG_DIR/sources/usr/include/"* "$pkgdir/usr/include/" 2>/dev/null || true
	fi

	info_msg "Building Debian package: $PKG_NAME"
	fakeroot dpkg-deb -b -Zxz $pkgdir ${pkgdir}.deb

	# Overwrite package directory contents instead of removing
	find $pkgdir -mindepth 1 -delete 2>/dev/null || true
}

	makeinstall_target() {
		local pkgdir="$BUILD_IMAGES/.tmp/${PKG_NAME}_${PKG_VERSION}_${DISTRIB_ARCH}"
	mkdir -p $BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/${PKG_NAME}/
	# Overwrite old debs by deleting contents
	find $BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/${PKG_NAME}/ -mindepth 1 -delete 2>/dev/null || true
	cp ${pkgdir}.deb $BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/${PKG_NAME}/ 2>/dev/null || true

	# Overwrite deb file instead of removing
	: > ${pkgdir}.deb 2>/dev/null || true
}

