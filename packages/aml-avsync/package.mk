	# Get absolute paths
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

PKG_NAME="aml-avsync"
PKG_VERSION="1.0-amlogic-yocto"
PKG_SHA256=""
PKG_SOURCE_DIR=""
PKG_SITE=""
PKG_URL=""
PKG_ARCH="aarch64"
PKG_LICENSE="AMLOGIC"
PKG_SHORTDESC="Amlogic Audio/Video synchronization library"

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
 Includes header files in /usr/include for development purposes.
EOF

	# Build the package using the Makefile in the source
	local PKG_BUILD_DIR="${BUILD}/${PKG_NAME}-${PKG_VERSION}"
	cd "$PKG_BUILD_DIR"
	if [ ! -f "src/Makefile" ]; then
		error_msg "Makefile not found in $PKG_BUILD_DIR/src/"
		ls -la "$PKG_BUILD_DIR" || true
		return 1
	fi

	# Detect and verify cross-compiler (fixed paths for ARM64)
	detect_cross_compiler || return 1

	# Set build environment variables as expected by the Makefile
	# According to Yocto recipe: OUT_DIR="${B}/src"
	local OUT_DIR="$PKG_BUILD_DIR/src"
	export OUT_DIR
	export STAGING_DIR="$PKG_BUILD_DIR/staging"
	export TARGET_DIR="$pkgdir"
	export STRIP="${CROSS_COMPILE}strip"
	export TARGET_CFLAGS="-fPIC -O2"

	# Create staging directory
	mkdir -p "$STAGING_DIR/usr/lib"
	mkdir -p "$STAGING_DIR/usr/include"

	# Pre-build step: Run version_config.sh to generate version header
	# According to Yocto recipe: bash version_config.sh ${OUT_DIR}
	cd "$PKG_BUILD_DIR"
	if [ -f "version_config.sh" ]; then
		info_msg "Running version_config.sh to generate version header..."
		bash version_config.sh "$OUT_DIR" || {
			error_msg "version_config.sh failed"
			return 1
		}
	else
		error_msg "version_config.sh not found in $PKG_BUILD_DIR"
		return 1
	fi

	# Build from src/ directory (as per Yocto recipe)
	cd "$PKG_BUILD_DIR/src"
	
	# Patch Makefile to use cross-compiler
	# The Makefile uses $(CC) variable, so we need to ensure it's set
	if ! grep -q "^CC[[:space:]]*:=" "$PKG_BUILD_DIR/src/Makefile" 2>/dev/null; then
		local CC_ESC=$(echo "$CC" | sed 's/[[\.*^$()+?{|]/\\&/g')
		sed -i "1i CC := ${CC_ESC}" "$PKG_BUILD_DIR/src/Makefile"
		info_msg "Added CC=${CC} to Makefile"
	else
		local CC_ESC=$(echo "$CC" | sed 's/[[\.*^$()+?{|]/\\&/g')
		sed -i "s|^CC[[:space:]]*:=.*|CC := ${CC_ESC}|" "$PKG_BUILD_DIR/src/Makefile"
		info_msg "Updated CC=${CC} in Makefile"
	fi

	# Build libamlavsync.so
	info_msg "Building ${PKG_NAME} with CC=${CC}..."
	make clean 2>/dev/null || true
	make all CC="${CC}" || {
		error_msg "Build failed"
		return 1
	}

	# Verify build output
	if [ ! -f "$OUT_DIR/libamlavsync.so" ]; then
		error_msg "libamlavsync.so not found after build"
		return 1
	fi

	# Install library
	install -m 644 "$OUT_DIR/libamlavsync.so" "${pkgdir}/usr/lib/"
	${STRIP} "${pkgdir}/usr/lib/libamlavsync.so" 2>/dev/null || true

	# Install headers from sources/src directory
	local HEADER_SRC_DIR="$PKG_DIR/sources/src"
	if [ -d "$HEADER_SRC_DIR" ]; then
		# Install all header files from src directory
		for header_file in "$HEADER_SRC_DIR"/*.h; do
			if [ -f "$header_file" ]; then
				install -m 644 "$header_file" "${pkgdir}/usr/include/" 2>/dev/null || true
			fi
		done
	fi
	# Also try from PKG_BUILD_DIR/src (if build copies them there)
	if [ -f "$PKG_BUILD_DIR/src/aml_avsync.h" ]; then
		install -m 644 "$PKG_BUILD_DIR/src/aml_avsync.h" "${pkgdir}/usr/include/" 2>/dev/null || true
	fi
	if [ -f "$PKG_BUILD_DIR/src/aml_avsync_log.h" ]; then
		install -m 644 "$PKG_BUILD_DIR/src/aml_avsync_log.h" "${pkgdir}/usr/include/" 2>/dev/null || true
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

