PKG_NAME="libgrpc++-dev"
PKG_VERSION="1.51.1-4.1build5"
PKG_SHA256=""
PKG_SOURCE_DIR=""
PKG_SITE=""
PKG_URL=""
PKG_ARCH="arm aarch64"
PKG_LICENSE="Apache-2.0"
PKG_SHORTDESC="gRPC C++ development libraries and headers"

PKG_NEED_BUILD="YES"

# Ensure build directory exists for stamp file creation
# This is called after sources are copied, but before stamp file is written
post_unpack() {
	mkdir -p "$BUILD/${PKG_NAME}-${PKG_VERSION}"
}

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
Depends: libgrpc++1.51t64 (= 1.51.1-4.1build5), libgrpc-dev (= 1.51.1-4.1build5)
Section: libdevel
Priority: optional
Description: gRPC C++ development libraries and headers
 ${PKG_SHORTDESC}
 This package provides grpcpp/grpc++ development headers (grpcpp/server.h, etc.).
EOF

	# Copy from local sources directory
	local PKG_DIR="$PKGS_DIR/$PKG_NAME"
	if [ ! -d "$PKG_DIR/sources/usr" ]; then
		error_msg "Local sources not found at $PKG_DIR/sources/usr"
		error_msg "Please ensure libgrpc++-dev files are extracted to packages/libgrpc++-dev/sources/usr/"
		return 1
	fi

	info_msg "Copying libgrpc++-dev from local sources..."
	
	# Copy development headers (grpcpp and grpc++)
	if [ -d "$PKG_DIR/sources/usr/include/grpcpp" ]; then
		mkdir -p "$pkgdir/usr/include"
		cp -r "$PKG_DIR/sources/usr/include/grpcpp" "$pkgdir/usr/include/" 2>/dev/null || true
	fi
	if [ -d "$PKG_DIR/sources/usr/include/grpc++" ]; then
		mkdir -p "$pkgdir/usr/include"
		cp -r "$PKG_DIR/sources/usr/include/grpc++" "$pkgdir/usr/include/" 2>/dev/null || true
	fi
	
	# Copy pkg-config files
	if [ -d "$PKG_DIR/sources/usr/lib/pkgconfig" ]; then
		mkdir -p "$pkgdir/usr/lib/pkgconfig"
		cp -r "$PKG_DIR/sources/usr/lib/pkgconfig/"*grpc* "$pkgdir/usr/lib/pkgconfig/" 2>/dev/null || true
	fi
	
	# Copy cmake files (if any)
	if [ -d "$PKG_DIR/sources/usr/lib/cmake" ]; then
		mkdir -p "$pkgdir/usr/lib/cmake"
		cp -r "$PKG_DIR/sources/usr/lib/cmake/"*grpc* "$pkgdir/usr/lib/cmake/" 2>/dev/null || true
	fi
	
	# Copy static libraries (if any)
	if [ -d "$PKG_DIR/sources/usr/lib" ]; then
		mkdir -p "$pkgdir/usr/lib"
		find "$PKG_DIR/sources/usr/lib" -type f -name "*.a" -exec cp --parents {} "$pkgdir/" \; 2>/dev/null || true
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

