# Helper function to set fixed cross-compiler path for ARM64 (VIM4 board only)
detect_cross_compiler() {
	# Fixed toolchain paths for ARM64 - try multiple compilers to find one that works
	local TOOLCHAIN_OPTIONS=(
		"$BUILD/gcc-arm-aarch64-none-linux-gnu-mainline-12.2.rel1:aarch64-none-linux-gnu"
		"$BUILD/gcc-arm-aarch64-none-linux-gnu-12.2.rel1:aarch64-none-linux-gnu"
		"$BUILD/gcc-linaro-aarch64-linux-gnu-7.3.1-2018.05:aarch64-linux-gnu"
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

PKG_NAME="dolby-ms12"
PKG_VERSION="amlogic-yocto-1.0"
PKG_SHA256=""
PKG_SOURCE_DIR=""
PKG_SITE=""
PKG_URL=""
PKG_ARCH="aarch64"
PKG_LICENSE="AMLOGIC"
PKG_SHORTDESC="Dolby MS12 audio processing library (proprietary pre-built binaries)"

PKG_NEED_BUILD="YES"

make_target() {
	local pkgdir="$BUILD_IMAGES/.tmp/${PKG_NAME}_${VERSION}_${DISTRIB_ARCH}"
	rm -rf $pkgdir
	mkdir -p $pkgdir/DEBIAN
	mkdir -p $pkgdir/usr/lib
	mkdir -p $pkgdir/usr/bin
	mkdir -p $pkgdir/lib/optee_armtz

	# Set up control file
	cat <<-EOF > $pkgdir/DEBIAN/control
Package: ${PKG_NAME}
Version: ${VERSION}
Architecture: ${DISTRIB_ARCH}
Maintainer: Khadas <hello@khadas.com>
Depends: optee-userspace
Section: libs
Priority: optional
Description: Dolby MS12 audio processing library
 ${PKG_SHORTDESC}
 This package provides pre-built Dolby MS12 audio processing binaries.
 Includes libdolbyms12.so library, dolby_fw_dms12 firmware, and OP-TEE trusted applications.
EOF

	# Copy pre-built binaries from Yocto source
	local PKG_DIR="$PKGS_DIR/$PKG_NAME"
	local SOURCE_DIR="$PKG_DIR/sources"
	
	if [ ! -d "$SOURCE_DIR" ]; then
		error_msg "Source directory not found: $SOURCE_DIR"
		error_msg "Please copy dolby-ms12 source from Yocto:"
		error_msg "  mkdir -p packages/dolby-ms12/sources"
		error_msg "  cp -r ~/yocto/aml-comp/multimedia/aml-multimedia/dolby_ms12_release/src packages/dolby-ms12/sources/"
		return 1
	fi
	
	# Determine architecture-specific subdirectory
	# Yocto uses: arm.aapcs-linux.hard for ARM, aarch64.lp64. for aarch64
	local ARCH_SUBDIR="aarch64.lp64."
	if [ ! -d "$SOURCE_DIR/$ARCH_SUBDIR" ]; then
		# Try alternative naming
		ARCH_SUBDIR="aarch64"
		if [ ! -d "$SOURCE_DIR/$ARCH_SUBDIR" ]; then
			# Try ARM naming as fallback
			ARCH_SUBDIR="arm.aapcs-linux.hard"
		fi
	fi
	
	info_msg "Installing Dolby MS12 binaries from $SOURCE_DIR..."
	
	# Install dolby_fw_dms12 binary (architecture-specific)
	if [ -f "$SOURCE_DIR/$ARCH_SUBDIR/dolby_fw_dms12" ]; then
		install -m 0755 "$SOURCE_DIR/$ARCH_SUBDIR/dolby_fw_dms12" "$pkgdir/usr/bin/" || {
			error_msg "Failed to install dolby_fw_dms12"
			return 1
		}
		info_msg "Installed dolby_fw_dms12 from $ARCH_SUBDIR/"
	elif [ -f "$SOURCE_DIR/dolby_fw_dms12" ]; then
		install -m 0755 "$SOURCE_DIR/dolby_fw_dms12" "$pkgdir/usr/bin/" || {
			error_msg "Failed to install dolby_fw_dms12"
			return 1
		}
		info_msg "Installed dolby_fw_dms12 from root"
	else
		warning_msg "dolby_fw_dms12 not found, skipping binary installation"
	fi
	
	# Install libdolbyms12.so library
	# Note: The source libdolbyms12.so is typically empty (0 bytes) - this is intentional
	# It's a placeholder that may be replaced at runtime or the actual library
	# (libms12v2.so.1.0) is built by aml-audio-hal package
	local LIB_FOUND=false
	if [ -f "$SOURCE_DIR/libdolbyms12.so" ]; then
		# Install even if empty (placeholder file)
		install -m 0644 "$SOURCE_DIR/libdolbyms12.so" "$pkgdir/usr/lib/" || {
			warning_msg "Failed to install libdolbyms12.so (may be empty placeholder)"
		}
		if [ -s "$SOURCE_DIR/libdolbyms12.so" ]; then
			info_msg "Installed libdolbyms12.so (non-empty)"
		else
			info_msg "Installed libdolbyms12.so placeholder (empty file - may be replaced at runtime)"
		fi
		LIB_FOUND=true
	fi
	
	# Also check for libms12v2.so* in source (alternative naming)
	if [ -f "$SOURCE_DIR/libms12v2.so.1.0" ] && [ -s "$SOURCE_DIR/libms12v2.so.1.0" ]; then
		install -m 0644 "$SOURCE_DIR/libms12v2.so.1.0" "$pkgdir/usr/lib/" || {
			error_msg "Failed to install libms12v2.so.1.0"
			return 1
		}
		# Create symlinks if needed
		if [ ! -f "$pkgdir/usr/lib/libms12v2.so.1" ]; then
			ln -s libms12v2.so.1.0 "$pkgdir/usr/lib/libms12v2.so.1" 2>/dev/null || true
		fi
		if [ ! -f "$pkgdir/usr/lib/libms12v2.so" ]; then
			ln -s libms12v2.so.1 "$pkgdir/usr/lib/libms12v2.so" 2>/dev/null || true
		fi
		LIB_FOUND=true
		info_msg "Installed libms12v2.so.1.0 from source (with symlinks)"
	fi
	
	# Note: libms12v2.so.1.0 is also built by aml-audio-hal package
	# The dolby-ms12 package provides the firmware and OP-TEE components
	# The actual library is provided by aml-audio-hal
	if [ "$LIB_FOUND" = false ]; then
		warning_msg "libdolbyms12.so not found or is empty - this may be intentional"
		warning_msg "The actual library (libms12v2.so.1.0) is provided by aml-audio-hal package"
	fi
	
	# Install OP-TEE trusted applications (*.ta files)
	if ls "$SOURCE_DIR"/*.ta 1>/dev/null 2>&1; then
		install -m 0644 "$SOURCE_DIR"/*.ta "$pkgdir/lib/optee_armtz/" || {
			warning_msg "Failed to install OP-TEE TA files (may not be critical)"
		}
		info_msg "Installed OP-TEE trusted applications"
	fi
	
	# Strip binaries and libraries (if not already stripped)
	export STRIP="${CROSS_COMPILE}strip"
	find "$pkgdir/usr/bin" -type f -executable -exec ${STRIP} {} \; 2>/dev/null || true
	find "$pkgdir/usr/lib" -name "*.so*" -type f -exec ${STRIP} {} \; 2>/dev/null || true
	
	info_msg "Building Debian package: ${PKG_NAME}"
	fakeroot dpkg-deb -b -Zxz $pkgdir ${pkgdir}.deb
	rm -rf $pkgdir
}

makeinstall_target() {
	local pkgdir="$BUILD_IMAGES/.tmp/${PKG_NAME}_${VERSION}_${DISTRIB_ARCH}"
	mkdir -p $BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/${PKG_NAME}/
	find $BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/${PKG_NAME}/ -mindepth 1 -delete 2>/dev/null || true
	cp ${pkgdir}.deb $BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/${PKG_NAME}/ 2>/dev/null || true
	: > ${pkgdir}.deb 2>/dev/null || true
}

