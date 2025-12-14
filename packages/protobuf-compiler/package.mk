PKG_NAME="protobuf-compiler"
PKG_VERSION="3.21.12-8.2ubuntu0.2"
PKG_SHA256=""
PKG_SOURCE_DIR=""
PKG_SITE=""
PKG_URL=""
PKG_ARCH="arm aarch64"
PKG_LICENSE="BSD-3-Clause"
PKG_SHORTDESC="Protocol Buffers compiler and development files"

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
Depends: libprotobuf32t64 (= 3.21.12-8.2ubuntu0.2)
Section: devel
Priority: optional
Description: Protocol Buffers compiler
 ${PKG_SHORTDESC}
 This package provides protoc compiler and development headers.
 Note: Binary is architecture-independent, using amd64 version.
EOF

	# Copy from local sources directory
	local PKG_DIR="$PKGS_DIR/$PKG_NAME"
	if [ ! -d "$PKG_DIR/sources/usr" ]; then
		error_msg "Local sources not found at $PKG_DIR/sources/usr"
		error_msg "Please ensure protobuf-compiler files are extracted to packages/protobuf-compiler/sources/usr/"
		return 1
	fi

	info_msg "Copying protobuf-compiler from local sources..."
	
	# Copy protoc binary
	if [ -f "$PKG_DIR/sources/usr/bin/protoc" ]; then
		mkdir -p "$pkgdir/usr/bin"
		cp "$PKG_DIR/sources/usr/bin/protoc" "$pkgdir/usr/bin/" 2>/dev/null || true
		chmod 755 "$pkgdir/usr/bin/protoc" 2>/dev/null || true
	fi
	
	# Copy development headers (if any)
	if [ -d "$PKG_DIR/sources/usr/include/google/protobuf" ]; then
		mkdir -p "$pkgdir/usr/include/google"
		cp -r "$PKG_DIR/sources/usr/include/google/protobuf" "$pkgdir/usr/include/google/" 2>/dev/null || true
	fi
	
	# Copy any other files
	if [ -d "$PKG_DIR/sources/usr/lib" ]; then
		mkdir -p "$pkgdir/usr/lib"
		# Copy only static libraries and plugin binaries
		find "$PKG_DIR/sources/usr/lib" -type f \( -name "*.a" -o -name "protoc" \) -exec cp --parents {} "$pkgdir/" \; 2>/dev/null || true
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
