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

PKG_NAME="android-liblog"
PKG_VERSION="1.0-amlogic-yocto"
PKG_SHA256=""
PKG_SOURCE_DIR=""
PKG_SITE=""
PKG_URL=""
PKG_ARCH="aarch64"
PKG_LICENSE="Apache-2.0"
PKG_SHORTDESC="Android logging library (Amlogic version)"

PKG_NEED_BUILD="YES"

make_target() {
	local pkgdir="$BUILD_IMAGES/.tmp/${PKG_NAME}_${VERSION}_${DISTRIB_ARCH}"
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
Description: Android logging library (Amlogic version)
 ${PKG_SHORTDESC}
 Provides liblog.so and logging headers.
 Note: ashmem.h is provided by android-binder package to avoid conflicts.
EOF

	# Build the package using the Makefile in the source
	local PKG_BUILD_DIR="${BUILD}/${PKG_NAME}-${PKG_VERSION}"
	local PKG_DIR="$PKGS_DIR/$PKG_NAME"
	cd "$PKG_BUILD_DIR"
	if [ ! -f Makefile ]; then
		error_msg "Makefile not found in $PKG_BUILD_DIR"
		ls -la "$PKG_BUILD_DIR" || true
		return 1
	fi

	# Detect and verify cross-compiler (fixed paths for ARM64)
	detect_cross_compiler || return 1

	# Set build environment variables as expected by the Makefile
	export OUT_DIR="$PKG_BUILD_DIR"
	export STAGING_DIR="$PKG_BUILD_DIR/staging"
	export TARGET_DIR="$pkgdir"
	export STRIP="${CROSS_COMPILE}strip"
	export LIBLOG_SRC_DIR="$PKG_BUILD_DIR"

	# Create staging and target directories
	mkdir -p "$STAGING_DIR/usr/lib"
	mkdir -p "$STAGING_DIR/usr/include/android"
	mkdir -p "$STAGING_DIR/usr/include/cutils"
	mkdir -p "$pkgdir/usr/lib"
	mkdir -p "$pkgdir/usr/include/android"
	mkdir -p "$pkgdir/usr/include/cutils"

	# Patch Makefile to set CC at the top (if not already set)
	if ! grep -q "^CC[[:space:]]*:=" "$PKG_BUILD_DIR/Makefile" 2>/dev/null && ! grep -q "^CC[[:space:]]*=" "$PKG_BUILD_DIR/Makefile" 2>/dev/null; then
		local CC_ESC=$(echo "$CC" | sed 's/[[\.*^$()+?{|]/\\&/g')
		sed -i "1i CC := ${CC_ESC}" "$PKG_BUILD_DIR/Makefile"
		info_msg "Set CC=${CC} in Makefile"
	fi

	# Build liblog.so
	info_msg "Building ${PKG_NAME}..."
	make clean 2>/dev/null || true
	make all CC="${CC}" || {
		error_msg "Build failed"
		return 1
	}

	# Verify build outputs exist
	if [ ! -f "$OUT_DIR/liblog.so" ] && [ ! -f "$OUT_DIR/liblog.so.1" ] && [ ! -f "$OUT_DIR/liblog.so.1.0.0" ]; then
		error_msg "liblog.so not found after build"
		return 1
	fi

	# Install libraries (copy directly, don't use Makefile install target to avoid conflicts)
	if [ -f "$OUT_DIR/liblog.so.1.0.0" ]; then
		install -m 644 "$OUT_DIR/liblog.so.1.0.0" "${pkgdir}/usr/lib/"
		${STRIP} "${pkgdir}/usr/lib/liblog.so.1.0.0" 2>/dev/null || true
	fi
	if [ -f "$OUT_DIR/liblog.so.1" ]; then
		install -m 644 "$OUT_DIR/liblog.so.1" "${pkgdir}/usr/lib/"
		${STRIP} "${pkgdir}/usr/lib/liblog.so.1" 2>/dev/null || true
	fi
	if [ -f "$OUT_DIR/liblog.so" ]; then
		install -m 644 "$OUT_DIR/liblog.so" "${pkgdir}/usr/lib/"
		${STRIP} "${pkgdir}/usr/lib/liblog.so" 2>/dev/null || true
	fi

	# Install headers manually (excluding ashmem.h)
	local HEADER_SRC_DIR="$PKG_DIR/sources/include"
	
	# Install android headers
	if [ -d "$HEADER_SRC_DIR/android" ]; then
		cp -r "$HEADER_SRC_DIR/android"/* "${pkgdir}/usr/include/android/" 2>/dev/null || true
	fi
	
	# Install cutils headers (EXCLUDING ashmem.h - owned by android-binder)
	if [ -d "$HEADER_SRC_DIR/cutils" ]; then
		find "$HEADER_SRC_DIR/cutils" -type f ! -name "ashmem.h" -exec cp {} "${pkgdir}/usr/include/cutils/" \; 2>/dev/null || true
		info_msg "Installed cutils headers (excluded ashmem.h - provided by android-binder)"
	fi

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
