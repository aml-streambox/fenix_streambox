# Helper function to set fixed cross-compiler path for ARM64 (VIM4 board only)
detect_cross_compiler() {
	# Fixed toolchain paths for ARM64 - try multiple compilers to find one that works
	local TOOLCHAIN_OPTIONS=(
		"$BUILD/gcc-linaro-aarch64-linux-gnu-7.3.1-2018.05:aarch64-linux-gnu"
		"$BUILD/gcc-arm-aarch64-none-linux-gnu-12.2.rel1:aarch64-none-linux-gnu"
		"$BUILD/gcc-arm-aarch64-none-linux-gnu-mainline-12.2.rel1:aarch64-none-linux-gnu"
	)
	
	# Try each toolchain in order
	CC=""
	CXX=""
	for toolchain_spec in "${TOOLCHAIN_OPTIONS[@]}"; do
		local TOOLCHAIN_DIR="${toolchain_spec%%:*}"
		local CROSS_COMPILE_PREFIX="${toolchain_spec##*:}"
		
		if [ -d "$TOOLCHAIN_DIR/bin" ] && [ -f "$TOOLCHAIN_DIR/bin/${CROSS_COMPILE_PREFIX}-gcc" ]; then
			CC="$TOOLCHAIN_DIR/bin/${CROSS_COMPILE_PREFIX}-gcc"
			CXX="$TOOLCHAIN_DIR/bin/${CROSS_COMPILE_PREFIX}-g++"
			CROSS_COMPILE="${CROSS_COMPILE_PREFIX}-"
			info_msg "Using toolchain: $TOOLCHAIN_DIR"
			break
		fi
	done
	
	if [ -z "$CC" ]; then
		error_msg "Cross-compiler not found in fixed paths"
		error_msg ""
		error_msg "Tried toolchain locations:"
		for toolchain_spec in "${TOOLCHAIN_OPTIONS[@]}"; do
			local TOOLCHAIN_DIR="${toolchain_spec%%:*}"
			local CROSS_COMPILE_PREFIX="${toolchain_spec##*:}"
			error_msg "  - $TOOLCHAIN_DIR/bin/${CROSS_COMPILE_PREFIX}-gcc"
		done
		error_msg ""
		error_msg "Please ensure at least one toolchain is extracted to the build directory"
		return 1
	fi
	
	# Verify cross-compiler exists
	if [ ! -f "$CC" ] || [ ! -x "$CC" ]; then
		error_msg "Cross-compiler not executable: $CC"
		return 1
	fi
	
	if [ ! -f "$CXX" ] || [ ! -x "$CXX" ]; then
		error_msg "Cross-compiler C++ not executable: $CXX"
		return 1
	fi
	
	# Get absolute paths
	CC=$(readlink -f "$CC" 2>/dev/null || echo "$CC")
	CXX=$(readlink -f "$CXX" 2>/dev/null || echo "$CXX")
	
	export CC CXX CROSS_COMPILE
	info_msg "Using cross-compiler: CC=$CC, CXX=$CXX"
	return 0
}

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
	# Overwrite by recreating directory structure
	mkdir -p $pkgdir/DEBIAN
	mkdir -p $pkgdir/usr/bin
	mkdir -p $pkgdir/usr/lib

	# Set up control file
	cat <<-EOF > $pkgdir/DEBIAN/control
Package: ${PKG_NAME}
Version: ${VERSION}
Architecture: ${DISTRIB_ARCH}
Maintainer: Khadas <hello@khadas.com>
Depends: android-binder, aml-audio-service, zlib1g
Section: utils
Priority: optional
Description: Amlogic TV Server Stream Box
 ${PKG_SHORTDESC}
 Provides libtv.so, libtvclient.so, tvservice, and tvtest.
EOF

	# Build the package using the Makefile in the source
	local PKG_BUILD_DIR="${BUILD}/${PKG_NAME}-${PKG_VERSION}"
	cd "$PKG_BUILD_DIR"
	if [ ! -f Makefile ]; then
		error_msg "Makefile not found in $PKG_BUILD_DIR"
		ls -la "$PKG_BUILD_DIR" || true
		return 1
	fi

	# Detect and verify cross-compiler (do NOT rely on CROSS_COMPILE env var)
	detect_cross_compiler || return 1

	# Set build environment variables as expected by the Makefile
	export OUT_DIR="$PKG_BUILD_DIR"
	export STAGING_DIR="$PKG_BUILD_DIR/staging"
	export TARGET_DIR="$pkgdir"
	export STRIP="${CROSS_COMPILE}strip"
	
	# Create staging directory for headers and libraries
	mkdir -p "$STAGING_DIR/usr/lib"
	mkdir -p "$STAGING_DIR/usr/include"
	
	# Get dependency libraries for linking
	# android-binder (libbinder.so, liblog.so)
	local BINDER_BUILD="$BUILD/android-binder-amlogic-yocto-1.0"
	if [ ! -d "$BINDER_BUILD" ]; then
		BINDER_BUILD="$BUILD/android-binder-${PKG_VERSION}"
	fi
	if [ -f "$BINDER_BUILD/libbinder.so" ]; then
		cp "$BINDER_BUILD/libbinder.so" "$STAGING_DIR/usr/lib/" 2>/dev/null || true
	fi
	
	# android-liblog (liblog.so)
	local LIBLOG_BUILD="$BUILD/android-liblog-amlogic-yocto-1.0"
	if [ ! -d "$LIBLOG_BUILD" ]; then
		LIBLOG_BUILD="$BUILD/android-liblog-${PKG_VERSION}"
	fi
	if [ -f "$LIBLOG_BUILD/liblog.so" ]; then
		cp "$LIBLOG_BUILD/liblog.so" "$STAGING_DIR/usr/lib/" 2>/dev/null || true
	fi
	
	# aml-audio-service (libaudio_client.so)
	local AUDIO_SERVICE_BUILD="$BUILD/aml-audio-service-amlogic-yocto-1.0"
	if [ ! -d "$AUDIO_SERVICE_BUILD" ]; then
		AUDIO_SERVICE_BUILD="$BUILD/aml-audio-service-${PKG_VERSION}"
	fi
	if [ -f "$AUDIO_SERVICE_BUILD/libaudio_client.so" ]; then
		cp "$AUDIO_SERVICE_BUILD/libaudio_client.so" "$STAGING_DIR/usr/lib/" 2>/dev/null || true
	fi
	
	# Patch Makefile to set CC and CXX (similar to aml-audio-utils)
	# Escape special characters in CC/CXX for sed
	local CC_ESC=$(echo "$CC" | sed 's/[[\.*^$()+?{|]/\\&/g')
	local CXX_ESC=$(echo "$CXX" | sed 's/[[\.*^$()+?{|]/\\&/g')
	
	# Check if CC is already defined in Makefile
	if ! grep -q "^CC[[:space:]]*:=" "$PKG_BUILD_DIR/Makefile" 2>/dev/null && ! grep -q "^CC[[:space:]]*=" "$PKG_BUILD_DIR/Makefile" 2>/dev/null; then
		# Add CC and CXX at the beginning of Makefile
		sed -i "1i CC := ${CC_ESC}\nCXX := ${CXX_ESC}" "$PKG_BUILD_DIR/Makefile"
		info_msg "Set CC=${CC} and CXX=${CXX} in Makefile"
	else
		# Update or add CC/CXX definitions
		if grep -q "^CC[[:space:]]*:=" "$PKG_BUILD_DIR/Makefile" 2>/dev/null; then
			sed -i "s|^CC[[:space:]]*:=.*|CC := ${CC_ESC}|" "$PKG_BUILD_DIR/Makefile"
		else
			sed -i "1i CC := ${CC_ESC}" "$PKG_BUILD_DIR/Makefile"
		fi
		if grep -q "^CXX[[:space:]]*:=" "$PKG_BUILD_DIR/Makefile" 2>/dev/null; then
			sed -i "s|^CXX[[:space:]]*:=.*|CXX := ${CXX_ESC}|" "$PKG_BUILD_DIR/Makefile"
		else
			sed -i "1i CXX := ${CXX_ESC}" "$PKG_BUILD_DIR/Makefile"
		fi
		info_msg "Updated CC=${CC} and CXX=${CXX} in Makefile"
	fi
	
	# Build
	info_msg "Building ${PKG_NAME}..."
	make clean 2>/dev/null || true
	make all || {
		error_msg "Build failed"
		return 1
	}
	
	# Verify build outputs exist
	local BUILD_FAILED=0
	if [ ! -f "$OUT_DIR/libtv.so" ]; then
		error_msg "libtv.so not found after build"
		BUILD_FAILED=1
	fi
	if [ ! -f "$OUT_DIR/libtvclient.so" ]; then
		error_msg "libtvclient.so not found after build"
		BUILD_FAILED=1
	fi
	if [ ! -f "$OUT_DIR/tvservice" ]; then
		error_msg "tvservice not found after build"
		BUILD_FAILED=1
	fi
	if [ ! -f "$OUT_DIR/tvtest" ]; then
		error_msg "tvtest not found after build"
		BUILD_FAILED=1
	fi
	
	if [ "$BUILD_FAILED" = 1 ]; then
		error_msg "Build verification failed - some targets are missing"
		return 1
	fi
	
	# Use Makefile's install target
	info_msg "Installing built binaries and libraries..."
	make install || {
		error_msg "Install failed"
		return 1
	}
	
	# Verify installation
	if [ ! -f "$pkgdir/usr/lib/libtv.so" ] || [ ! -f "$pkgdir/usr/lib/libtvclient.so" ] || \
	   [ ! -f "$pkgdir/usr/bin/tvservice" ] || [ ! -f "$pkgdir/usr/bin/tvtest" ]; then
		error_msg "Installation verification failed - some files are missing in package directory"
		return 1
	fi
	
	# Strip binaries and libraries
	find "$pkgdir/usr/bin" -type f -executable -exec ${STRIP} {} \; 2>/dev/null || true
	find "$pkgdir/usr/lib" -name "*.so*" -exec ${STRIP} {} \; 2>/dev/null || true
	
	info_msg "Building Debian package: ${PKG_NAME}"
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
