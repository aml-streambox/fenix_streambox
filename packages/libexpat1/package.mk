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

PKG_NAME="libexpat1"
PKG_VERSION="2.6.1-2ubuntu0.3"
PKG_SHA256=""
PKG_SOURCE_DIR=""
PKG_SITE=""
PKG_URL=""
PKG_ARCH="aarch64"
PKG_LICENSE="MIT"
PKG_SHORTDESC="Expat XML parser runtime library"

PKG_NEED_BUILD="YES"

make_target() {
	local pkgdir="$BUILD_IMAGES/.tmp/${PKG_NAME}_${VERSION}_${DISTRIB_ARCH}"
	rm -rf $pkgdir
	mkdir -p $pkgdir/DEBIAN
	mkdir -p $pkgdir/usr/lib

	# Set up control file
	cat <<-EOF > $pkgdir/DEBIAN/control
Package: ${PKG_NAME}
Version: ${VERSION}
Architecture: ${DISTRIB_ARCH}
Maintainer: Khadas <hello@khadas.com>
Depends: 
Section: libs
Priority: optional
Description: Expat XML parser runtime library
 ${PKG_SHORTDESC}
 This package provides the runtime library for Expat XML parser.
EOF

	# Build from source
	local PKG_BUILD_DIR="${BUILD}/${PKG_NAME}-${PKG_VERSION}"
	local PKG_DIR="$PKGS_DIR/$PKG_NAME"
	local SOURCE_DIR="$PKG_DIR/sources/libexpat-R_2_6_1/expat"
	
	if [ ! -d "$SOURCE_DIR" ]; then
		error_msg "Source directory not found: $SOURCE_DIR"
		error_msg "Please ensure expat source code is extracted to packages/libexpat1/sources/"
		error_msg "Download from: https://archive.ubuntu.com/ubuntu/pool/main/e/expat/expat_2.6.1.orig.tar.gz"
		return 1
	fi
	
	cd "$PKG_BUILD_DIR"
	
	# Copy source code to build directory (if not already there)
	if [ ! -f "configure" ] && [ -d "$SOURCE_DIR" ]; then
		info_msg "Copying expat source code to build directory..."
		cp -r "$SOURCE_DIR"/* . 2>/dev/null || true
	fi
	
	# Apply Debian patches if they exist
	if [ -d "$PKG_DIR/sources/debian/patches" ]; then
		info_msg "Applying Debian patches..."
		# Read patch series file if it exists to apply patches in order
		local PATCH_SERIES="$PKG_DIR/sources/debian/patches/series"
		if [ -f "$PATCH_SERIES" ]; then
			# Apply patches in order from series file
			while IFS= read -r patch_name || [ -n "$patch_name" ]; do
				# Skip empty lines and comments
				[ -z "$patch_name" ] && continue
				[ "${patch_name#\#}" != "$patch_name" ] && continue
				
				local patch="$PKG_DIR/sources/debian/patches/$patch_name"
				if [ -f "$patch" ]; then
					info_msg "Applying patch: $patch_name"
					# Try different patch strip levels
					# Patches reference "expat-2.6.1/expat/lib/xmlparse.c" but files are at "lib/xmlparse.c"
					# So we need -p2 to strip "expat-2.6.1/expat/" or -p1 to strip "expat/"
					local PATCH_SUCCESS=false
					if patch -p2 < "$patch" 2>/dev/null; then
						PATCH_SUCCESS=true
					elif patch -p1 < "$patch" 2>/dev/null; then
						PATCH_SUCCESS=true
					elif patch -p3 < "$patch" 2>/dev/null; then
						PATCH_SUCCESS=true
					fi
					
					if [ "$PATCH_SUCCESS" = false ]; then
						warning_msg "Patch $patch_name failed with -p1, -p2, and -p3"
						# Try to apply with fuzz as last resort
						if ! patch -p2 --fuzz=3 < "$patch" 2>/dev/null; then
							if ! patch -p1 --fuzz=3 < "$patch" 2>/dev/null; then
								error_msg "Patch $patch_name failed to apply. Please check patch paths."
								return 1
							fi
						fi
					fi
				fi
			done < "$PATCH_SERIES"
		else
			# Fallback: apply all patches in alphabetical order
			for patch in "$PKG_DIR/sources/debian/patches"/*.patch; do
				if [ -f "$patch" ] && [ "$(basename "$patch")" != "series" ]; then
					info_msg "Applying patch: $(basename $patch)"
					# Try different patch strip levels
					# Patches reference "expat-2.6.1/expat/lib/xmlparse.c" but files are at "lib/xmlparse.c"
					local PATCH_SUCCESS=false
					if patch -p2 < "$patch" 2>/dev/null; then
						PATCH_SUCCESS=true
					elif patch -p1 < "$patch" 2>/dev/null; then
						PATCH_SUCCESS=true
					elif patch -p3 < "$patch" 2>/dev/null; then
						PATCH_SUCCESS=true
					fi
					
					if [ "$PATCH_SUCCESS" = false ]; then
						warning_msg "Patch $(basename $patch) failed with -p1, -p2, and -p3"
						# Try to apply with fuzz as last resort
						if ! patch -p2 --fuzz=3 < "$patch" 2>/dev/null; then
							if ! patch -p1 --fuzz=3 < "$patch" 2>/dev/null; then
								error_msg "Patch $(basename $patch) failed to apply. Please check patch paths."
								return 1
							fi
						fi
					fi
				fi
			done
		fi
	fi
	
	# Detect and verify cross-compiler
	detect_cross_compiler || return 1
	
	# Generate configure script if needed
	if [ ! -f "configure" ]; then
		if [ -f "buildconf.sh" ]; then
			info_msg "Running buildconf.sh..."
			./buildconf.sh || return 1
		elif [ -f "autogen.sh" ]; then
			info_msg "Running autogen.sh..."
			./autogen.sh || return 1
		elif [ -f "configure.ac" ]; then
			info_msg "Running autoreconf..."
			autoreconf -fiv || return 1
		else
			error_msg "No configure script, buildconf.sh, autogen.sh, or configure.ac found"
			return 1
		fi
	fi
	
	# Configure for cross-compilation
	info_msg "Configuring expat for cross-compilation..."
	
	# Determine host triplet from cross-compiler
	local HOST_TRIPLET=""
	if [[ "$CC" == *"aarch64-linux-gnu"* ]]; then
		HOST_TRIPLET="aarch64-linux-gnu"
	elif [[ "$CC" == *"aarch64-none-linux-gnu"* ]]; then
		HOST_TRIPLET="aarch64-none-linux-gnu"
	else
		# Extract from compiler path
		HOST_TRIPLET=$(basename $(dirname $(dirname "$CC")))
	fi
	
	# Clean previous build
	rm -rf build
	mkdir -p build
	cd build
	
	# Configure with cross-compilation settings
	../configure \
		--host="$HOST_TRIPLET" \
		--prefix=/usr \
		--libdir=/usr/lib \
		--disable-static \
		--enable-shared \
		CC="$CC" \
		CXX="$CXX" \
		CFLAGS="-fPIC -O2" \
		CXXFLAGS="-fPIC -O2" \
		LDFLAGS="" \
		|| { error_msg "Configure failed"; return 1; }
	
	# Build
	info_msg "Building expat..."
	make -j$(nproc) || { error_msg "Build failed"; return 1; }
	
	# Install full expat (runtime + headers) to package directory.
	# This combined package provides both libexpat1 and the dev headers.
	info_msg "Installing expat (runtime + headers) to package directory..."
	make DESTDIR="$pkgdir" install || { error_msg "Install failed"; return 1; }
	
	# Strip libraries
	export STRIP="${CROSS_COMPILE}strip"
	find "$pkgdir/usr/lib" -name "*.so*" -type f -exec ${STRIP} {} \; 2>/dev/null || true
	
	# Build Debian package
	info_msg "Building Debian package: $PKG_NAME"
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
