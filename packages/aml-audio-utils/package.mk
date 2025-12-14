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

PKG_NAME="aml-audio-utils"
PKG_VERSION="amlogic-yocto-1.0"
PKG_SHA256=""
PKG_SOURCE_DIR=""
PKG_SITE=""
PKG_URL=""
PKG_ARCH="arm aarch64"
PKG_LICENSE="AMLOGIC"
PKG_SHORTDESC="Amlogic Audio Utils Library"

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
Depends: android-binder, libboost-system1.83.0, android-liblog
Section: libs
Priority: optional
Description: Amlogic Audio Utils Library
 ${PKG_SHORTDESC}
 Provides libamaudioutils.so, libcutils.so, and IPC Buffer headers.
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
	export AML_BUILD_DIR="$PKG_BUILD_DIR"
	export STAGING_DIR="$PKG_BUILD_DIR/staging"
	export TARGET_DIR="$pkgdir"
	export STRIP="${CROSS_COMPILE}strip"
	
	# Create target directory structure (Makefile install target needs these directories)
	mkdir -p "$pkgdir/usr/lib"
	mkdir -p "$pkgdir/usr/include"
	
	# Disable NEON support (code has ARM32 inline assembly incompatible with aarch64)
	# The compiler will still auto-vectorize with aarch64 NEON/SIMD automatically
	export TOOLCHAIN_NEON_SUPPORT=n

	# Create staging directory
	mkdir -p "$STAGING_DIR/usr/lib"
	mkdir -p "$STAGING_DIR/usr/include/audio_utils"
	mkdir -p "$STAGING_DIR/usr/include/IpcBuffer"
	mkdir -p "$STAGING_DIR/usr/include/cutils"

	# Add android-binder headers (needed for cutils/log.h and other cutils headers)
	# Check if android-binder sources are available (from package sources)
	local BINDER_SRC="$PKGS_DIR/android-binder/sources/include"
	if [ -d "$BINDER_SRC/cutils" ]; then
		# Copy cutils headers from android-binder sources
		cp -r "$BINDER_SRC/cutils"/* "$STAGING_DIR/usr/include/cutils/" 2>/dev/null || true
	fi

	# Build libamaudioutils.so and libcutils.so
	info_msg "Building ${PKG_NAME}..."
	make clean 2>/dev/null || true
	
	# Patch Makefile AFTER clean to set CC/CXX and fix NEON flags
	# (Makefile might be restored from sources, so patch after clean)
	# Set CC and CXX in Makefile to use cross-compiler (override any defaults)
	# Escape special characters in CC/CXX for sed
	local CC_ESC=$(echo "$CC" | sed 's/[[\.*^$()+?{|]/\\&/g')
	local CXX_ESC=$(echo "$CXX" | sed 's/[[\.*^$()+?{|]/\\&/g')
	
	# Check if CC is already defined in Makefile
	if ! grep -q "^CC[[:space:]]*:=" "$PKG_BUILD_DIR/Makefile" 2>/dev/null && ! grep -q "^CC[[:space:]]*=" "$PKG_BUILD_DIR/Makefile" 2>/dev/null; then
		# Add CC and CXX at the beginning of Makefile (before any includes or conditionals)
		sed -i "1i CC := ${CC_ESC}\nCXX := ${CXX_ESC}" "$PKG_BUILD_DIR/Makefile"
		info_msg "Set CC=${CC} and CXX=${CXX} in Makefile"
	else
		# Update or add CC/CXX definitions - place at top of file
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
	
	# Patch Makefile to use CXX for .cpp files (Makefile incorrectly uses CC for C++ files)
	sed -i 's/^\t\$(CC) -c $(CFLAGS) $(CXXFLAGS) -o $@ $</\t$(CXX) -c $(CFLAGS) $(CXXFLAGS) -o $@ $</' "$PKG_BUILD_DIR/Makefile"
	
	# No need to patch Makefile - TOOLCHAIN_NEON_SUPPORT=n prevents TOOLCHAIN_NEON_FLAGS from being set
	# This means $(TOOLCHAIN_NEON_FLAGS) in CFLAGS will be empty, avoiding ARM32 inline assembly
	
	# Add missing string.h include to resampler.c to fix memcpy/memmove warnings
	if [ -f "$PKG_BUILD_DIR/src/resampler.c" ] && ! grep -q "#include <string.h>" "$PKG_BUILD_DIR/src/resampler.c" 2>/dev/null; then
		# Add after the last #include (typically after speex_resampler.h)
		sed -i '/^#include <speex\/speex_resampler\.h>/a#include <string.h>' "$PKG_BUILD_DIR/src/resampler.c" 2>/dev/null || \
		# Fallback: add after first #include line
		sed -i '/^#include/a#include <string.h>' "$PKG_BUILD_DIR/src/resampler.c" 2>/dev/null || true
	fi
	
	# Re-create staging directory after clean (clean removes it) and copy android-binder headers
	mkdir -p "$STAGING_DIR/usr/include/cutils"
	if [ -d "$BINDER_SRC/cutils" ]; then
		cp -r "$BINDER_SRC/cutils"/* "$STAGING_DIR/usr/include/cutils/" 2>/dev/null || true
		
		# Fix gettid() conflict - comment out the declaration since glibc 2.30+ provides it
		# The system's unistd.h provides gettid() with __THROW (noexcept), causing a conflict
		if [ -f "$STAGING_DIR/usr/include/cutils/threads.h" ]; then
			# Comment out the conflicting declaration - system provides it in glibc 2.30+
			sed -i 's/^extern pid_t gettid();$/\/\/ extern pid_t gettid(); \/\/ System provides in glibc 2.30+/' "$STAGING_DIR/usr/include/cutils/threads.h" 2>/dev/null || true
		fi
	fi
	# Add STAGING_DIR include path to CFLAGS line (for cutils/log.h from android-binder)
	# Boost headers should be available via system or will be installed as dependency
	sed -i "s|CFLAGS+=|CFLAGS+=-I${STAGING_DIR}/usr/include |" "$PKG_BUILD_DIR/Makefile"
	
	# Get boost headers from libboost1.83-dev package
	# Check if the package was built and extract it to staging
	local BOOST_STAGING_DIR="$BUILD/staging/libboost1.83-dev"
	mkdir -p "$BOOST_STAGING_DIR"
	
	# First check if already extracted
	if [ ! -d "$BOOST_STAGING_DIR/usr/include/boost" ]; then
		# Check for built .deb file and extract it
		local BOOST_DEB=$(find "$BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/libboost1.83-dev" -name "*.deb" 2>/dev/null | head -1)
		if [ -n "$BOOST_DEB" ] && [ -f "$BOOST_DEB" ]; then
			info_msg "Found libboost1.83-dev package, extracting to staging..."
			mkdir -p "$BOOST_STAGING_DIR"
			if dpkg-deb -x "$BOOST_DEB" "$BOOST_STAGING_DIR" 2>/dev/null; then
				info_msg "Successfully extracted libboost1.83-dev to staging"
			else
				warning_msg "Failed to extract libboost1.83-dev package"
			fi
		else
			error_msg "libboost1.83-dev package not found. Please build it first."
			error_msg "Expected location: $BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/libboost1.83-dev/"
			return 1
		fi
	fi
	
	# Add Boost include path to CFLAGS if found
	if [ -d "$BOOST_STAGING_DIR/usr/include/boost" ]; then
		local BOOST_INCLUDE="-I$BOOST_STAGING_DIR/usr/include"
		info_msg "Using boost headers from staged libboost1.83-dev package"
		# Update CFLAGS line to include Boost headers
		sed -i "s|CFLAGS+=-I${STAGING_DIR}/usr/include |CFLAGS+=-I${STAGING_DIR}/usr/include $BOOST_INCLUDE |" "$PKG_BUILD_DIR/Makefile"
	fi
	
	# Add library path for android-binder's liblog.so (liblog is a separate package)
	# Check if android-liblog was built and add its library path
	local LIBLOG_BUILD_DIR="$BUILD/android-liblog-amlogic-yocto-1.0"
	local LIB_PATHS=""
	if [ -f "$LIBLOG_BUILD_DIR/liblog.so" ]; then
		LIB_PATHS="-L$LIBLOG_BUILD_DIR"
		info_msg "Found liblog.so from android-liblog package"
	elif [ -f "$BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/android-liblog"/*.deb ]; then
		# Extract liblog.so from built .deb if available
		local LIBLOG_DEB=$(find "$BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/android-liblog" -name "*.deb" 2>/dev/null | head -1)
		if [ -n "$LIBLOG_DEB" ] && [ -f "$LIBLOG_DEB" ]; then
			local LIBLOG_EXTRACT_DIR="$BUILD/staging/android-liblog"
			mkdir -p "$LIBLOG_EXTRACT_DIR"
			dpkg-deb -x "$LIBLOG_DEB" "$LIBLOG_EXTRACT_DIR" 2>/dev/null
			if [ -f "$LIBLOG_EXTRACT_DIR/usr/lib/liblog.so" ]; then
				LIB_PATHS="-L$LIBLOG_EXTRACT_DIR/usr/lib"
				info_msg "Extracted liblog.so from android-liblog package"
			fi
		fi
	else
		error_msg "liblog.so not found. Please build android-liblog package first."
		error_msg "Expected location: $BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/android-liblog/"
		return 1
	fi
	
	# Update Makefile LDFLAGS to include library paths
	if [ -n "$LIB_PATHS" ]; then
		sed -i "s|LDFLAGS+=-llog|LDFLAGS+=$LIB_PATHS -llog|" "$PKG_BUILD_DIR/Makefile"
	fi
	
	# Build (Makefile now has CC/CXX set and all correct include paths and library paths)
	# Also pass CC/CXX on command line as backup (Make will use command line over Makefile)
	info_msg "Running make with CC=${CC} CXX=${CXX}"
	make all CC="${CC}" CXX="${CXX}" || {
		error_msg "Build failed"
		return 1
	}

	# Install libraries
	if [ -f "$PKG_BUILD_DIR/libamaudioutils.so" ]; then
		install -m 644 "$PKG_BUILD_DIR/libamaudioutils.so" "${pkgdir}/usr/lib/"
		${STRIP} "${pkgdir}/usr/lib/libamaudioutils.so" 2>/dev/null || true
	else
		error_msg "libamaudioutils.so not found after build"
		return 1
	fi

	if [ -f "$PKG_BUILD_DIR/libcutils.so" ]; then
		install -m 644 "$PKG_BUILD_DIR/libcutils.so" "${pkgdir}/usr/lib/"
		${STRIP} "${pkgdir}/usr/lib/libcutils.so" 2>/dev/null || true
	fi

	# Install headers
	if [ -d "$PKG_BUILD_DIR/include/audio_utils" ]; then
		mkdir -p "${pkgdir}/usr/include/audio_utils"
		cp -r "$PKG_BUILD_DIR/include/audio_utils"/* "${pkgdir}/usr/include/audio_utils/" 2>/dev/null || true
	fi

	if [ -d "$PKG_BUILD_DIR/include/IpcBuffer" ]; then
		mkdir -p "${pkgdir}/usr/include/IpcBuffer"
		cp -r "$PKG_BUILD_DIR/include/IpcBuffer"/* "${pkgdir}/usr/include/IpcBuffer/" 2>/dev/null || true
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
