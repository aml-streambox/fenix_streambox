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
	
	# Get absolute paths
}
PKG_NAME="android-binder"
PKG_VERSION="amlogic-yocto-1.0"
PKG_SHA256=""
PKG_SOURCE_DIR=""
PKG_SITE=""
PKG_URL=""
PKG_ARCH="arm aarch64"
PKG_LICENSE="Apache-2.0"
PKG_SHORTDESC="Android Binder IPC Framework (Amlogic version)"

PKG_NEED_BUILD="YES"

make_target() {
	local pkgdir="$BUILD_IMAGES/.tmp/${PKG_NAME}_${VERSION}_${DISTRIB_ARCH}"
	rm -rf $pkgdir
	mkdir -p $pkgdir/DEBIAN
	mkdir -p $pkgdir/usr/lib
	mkdir -p $pkgdir/usr/bin
	mkdir -p $pkgdir/usr/include/binder
	mkdir -p $pkgdir/usr/include/utils
	mkdir -p $pkgdir/lib/systemd/system
	mkdir -p $pkgdir/etc/init.d

	# Set up control file
	cat <<-EOF > $pkgdir/DEBIAN/control
Package: ${PKG_NAME}
Version: ${VERSION}
Architecture: ${DISTRIB_ARCH}
Maintainer: Khadas <hello@khadas.com>
Depends: systemd
Section: libs
Priority: optional
Description: Android Binder IPC Framework
 ${PKG_SHORTDESC}
 Amlogic version with Makefile build system.
 Provides libbinder.so, servicemanager, and systemd services.
EOF

	# Build the package using the Makefile in the source
	# PKG_BUILD is set by build_package function: BUILD/${PKG_NAME}-${PKG_VERSION}
	local PKG_BUILD_DIR="${BUILD}/${PKG_NAME}-${PKG_VERSION}"
	cd "$PKG_BUILD_DIR"
	if [ ! -f Makefile ]; then
		error_msg "Makefile not found in $PKG_BUILD_DIR"
		error_msg "Contents of $PKG_BUILD_DIR:"
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

	# Create staging directory
	mkdir -p "$STAGING_DIR/usr/lib"
	mkdir -p "$STAGING_DIR/usr/bin"
	mkdir -p "$STAGING_DIR/usr/include/binder"
	mkdir -p "$STAGING_DIR/usr/include/utils"

	# Create output directories for object files (required by Makefile)
	mkdir -p "$OUT_DIR/binder" "$OUT_DIR/utils" "$OUT_DIR/cutils" "$OUT_DIR/servicemgr"

	# Ensure kernel binder headers are accessible
	# The Makefile includes from STAGING_DIR/usr/include, so we need to set up kernel headers
	# or ensure system headers are accessible via -I flags (Makefile handles this)

	# Patch Makefile to use cross-compiler
	# The Makefile uses $(CC) and $(CXX) variables, so we need to ensure they're set
	if ! grep -q "^CC[[:space:]]*:=" "$PKG_BUILD_DIR/Makefile" 2>/dev/null; then
		local CC_ESC=$(echo "$CC" | sed 's/[[\.*^$()+?{|]/\\&/g')
		local CXX_ESC=$(echo "$CXX" | sed 's/[[\.*^$()+?{|]/\\&/g')
		sed -i "1i CC := ${CC_ESC}\nCXX := ${CXX_ESC}" "$PKG_BUILD_DIR/Makefile"
		info_msg "Added CC=${CC} and CXX=${CXX} to Makefile"
	else
		local CC_ESC=$(echo "$CC" | sed 's/[[\.*^$()+?{|]/\\&/g')
		local CXX_ESC=$(echo "$CXX" | sed 's/[[\.*^$()+?{|]/\\&/g')
		sed -i "s|^CC[[:space:]]*:=.*|CC := ${CC_ESC}|" "$PKG_BUILD_DIR/Makefile"
		sed -i "s|^CXX[[:space:]]*:=.*|CXX := ${CXX_ESC}|" "$PKG_BUILD_DIR/Makefile"
		info_msg "Updated CC=${CC} and CXX=${CXX} in Makefile"
	fi
	
	# Build libbinder.so and servicemanager
	info_msg "Building ${PKG_NAME} with CC=${CC} CXX=${CXX}..."
	make clean 2>/dev/null || true
	make all CC="${CC}" CXX="${CXX}" || {
		error_msg "Build failed"
		return 1
	}

	# Install libraries
	if [ -f "$OUT_DIR/libbinder.so" ]; then
		install -m 644 "$OUT_DIR/libbinder.so" "${pkgdir}/usr/lib/"
		${STRIP} "${pkgdir}/usr/lib/libbinder.so" 2>/dev/null || true
	else
		error_msg "libbinder.so not found after build"
		return 1
	fi

	# Install servicemanager binary
	if [ -f "$OUT_DIR/servicemanager" ]; then
		install -m 755 "$OUT_DIR/servicemanager" "${pkgdir}/usr/bin/"
		${STRIP} "${pkgdir}/usr/bin/servicemanager" 2>/dev/null || true
	else
		error_msg "servicemanager not found after build"
		return 1
	fi

	# Install headers
	if [ -d "$PKG_BUILD_DIR/include/binder" ]; then
		install -m 644 "$PKG_BUILD_DIR/include/binder"/* "${pkgdir}/usr/include/binder/" 2>/dev/null || true
	fi
	if [ -d "$PKG_BUILD_DIR/include/utils" ]; then
		install -m 644 "$PKG_BUILD_DIR/include/utils"/* "${pkgdir}/usr/include/utils/" 2>/dev/null || true
	fi

	# Install systemd service files
	if [ -f "$PKG_DIR/files/binder.service" ]; then
		install -m 644 "$PKG_DIR/files/binder.service" "${pkgdir}/lib/systemd/system/"
	fi
	if [ -f "$PKG_DIR/files/dev-binderfs.mount" ]; then
		install -m 644 "$PKG_DIR/files/dev-binderfs.mount" "${pkgdir}/lib/systemd/system/"
	fi

	# Install binder.sh setup script
	if [ -f "$PKG_DIR/files/binder.sh" ]; then
		install -m 755 "$PKG_DIR/files/binder.sh" "${pkgdir}/usr/bin/"
	fi

	# Install init.d script (for sysvinit compatibility)
	if [ -f "$PKG_DIR/files/binder.init" ]; then
		install -m 755 "$PKG_DIR/files/binder.init" "${pkgdir}/etc/init.d/binder"
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
