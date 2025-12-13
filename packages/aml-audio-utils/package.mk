PKG_NAME="aml-audio-utils"
PKG_VERSION="amlogic-yocto-1.0"
PKG_SHA256=""
PKG_SOURCE_DIR=""
PKG_SITE=""
PKG_URL=""
PKG_ARCH="arm aarch64"
PKG_LICENSE="AMLOGIC"
PKG_SHORTDESC="Amlogic Audio Utilities Library"

PKG_NEED_BUILD="YES"

make_target() {
	local pkgdir="$BUILD_IMAGES/.tmp/${PKG_NAME}_${VERSION}_${DISTRIB_ARCH}"
	# Overwrite by recreating directory structure
	mkdir -p $pkgdir/DEBIAN
	mkdir -p $pkgdir/usr/lib
	mkdir -p $pkgdir/usr/include/audio_utils
	mkdir -p $pkgdir/usr/include/IpcBuffer

	# Set up control file
	cat <<-EOF > $pkgdir/DEBIAN/control
Package: ${PKG_NAME}
Version: ${VERSION}
Architecture: ${DISTRIB_ARCH}
Maintainer: Khadas <hello@khadas.com>
Depends: android-binder, android-liblog, libboost-system1.83.0
Build-Depends: libboost1.83-dev
Section: libs
Priority: optional
Description: Amlogic Audio Utilities Library
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

	# Set build environment variables as expected by the Makefile
	export AML_BUILD_DIR="$PKG_BUILD_DIR"
	export STAGING_DIR="$PKG_BUILD_DIR/staging"
	export TARGET_DIR="$pkgdir"
	export STRIP="${CROSS_COMPILE}strip"
	
	# Set cross-compiler environment variables for Makefile
	# CROSS_COMPILE is set by Fenix build system (e.g., "aarch64-linux-gnu-")
	export CC="${CROSS_COMPILE}gcc"
	export CXX="${CROSS_COMPILE}g++"
	
	# Verify cross-compiler exists
	if ! command -v "$CC" >/dev/null 2>&1; then
		# Try to detect based on DISTRIB_ARCH if CROSS_COMPILE not set
		if [ -z "$CROSS_COMPILE" ]; then
			if [ "$DISTRIB_ARCH" = "aarch64" ]; then
				CROSS_COMPILE="aarch64-linux-gnu-"
			elif [ "$DISTRIB_ARCH" = "armhf" ] || [ "$DISTRIB_ARCH" = "arm" ]; then
				CROSS_COMPILE="arm-linux-gnueabihf-"
			fi
			export CC="${CROSS_COMPILE}gcc"
			export CXX="${CROSS_COMPILE}g++"
		fi
		
		if ! command -v "$CC" >/dev/null 2>&1; then
			error_msg "Cross-compiler not found: $CC"
			error_msg "CROSS_COMPILE is: '${CROSS_COMPILE}'"
			error_msg "Please ensure cross-compiler is installed: sudo apt-get install gcc-aarch64-linux-gnu g++-aarch64-linux-gnu"
			return 1
		fi
	fi
	info_msg "Using cross-compiler: CC=$CC, CXX=$CXX"
	
	# Keep NEON support enabled (NEON is available on aarch64, flags will be handled by Makefile)
	export TOOLCHAIN_NEON_SUPPORT=y

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
	# Pass CC and CXX explicitly to make to ensure cross-compiler is used
	# Note: Makefile uses CC for both C and C++ files, so we set both
	make clean CC="$CC" CXX="$CXX" 2>/dev/null || true
	
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
	
	# Patch Makefile to use CXX for .cpp files (Makefile incorrectly uses CC for C++ files)
	# The Makefile uses $(CC) for both .c and .cpp files, but should use $(CXX) for .cpp
	if ! grep -q 'CXX \?=' "$PKG_BUILD_DIR/Makefile"; then
		# Add CXX variable if not defined
		sed -i '1i CXX ?= $(CC)' "$PKG_BUILD_DIR/Makefile"
	fi
	# Patch .cpp rule to use $(CXX) instead of $(CC)
	sed -i 's/^\t\$(CC) -c $(CFLAGS) $(CXXFLAGS) -o $@ $</\t$(CXX) -c $(CFLAGS) $(CXXFLAGS) -o $@ $</' "$PKG_BUILD_DIR/Makefile"
	
	# Keep NEON support enabled - Makefile will add -mfpu=neon -D_USE_NEON via TOOLCHAIN_NEON_SUPPORT=y
	# For aarch64, -mfpu=neon is not valid (NEON is always available), but -D_USE_NEON is fine
	# Patch Makefile to remove only -mfpu=neon for aarch64, keep -D_USE_NEON
	if [ "$DISTRIB_ARCH" = "aarch64" ]; then
		# Replace -mfpu=neon -D_USE_NEON with just -D_USE_NEON (keep NEON define, remove invalid flag)
		sed -i 's/-mfpu=neon -D_USE_NEON/-D_USE_NEON/g' "$PKG_BUILD_DIR/Makefile"
		sed -i 's/-mfpu=neon//g' "$PKG_BUILD_DIR/Makefile"
		sed -i 's/  */ /g' "$PKG_BUILD_DIR/Makefile"
		info_msg "Patched Makefile: removed -mfpu=neon for aarch64, kept -D_USE_NEON"
	fi
	# Add STAGING_DIR include path to CFLAGS line (for cutils/log.h from android-binder)
	# Boost headers should be available via system or will be installed as dependency
	sed -i "s|CFLAGS+=|CFLAGS+=-I${STAGING_DIR}/usr/include |" "$PKG_BUILD_DIR/Makefile"
	
	# Get boost headers from libboost1.83-dev package
	# Check if the package was built and extract it to staging
	local BOOST_INCLUDE=""
	local BOOST_STAGING_DIR="$BUILD/staging/libboost1.83-dev"
	
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
	
	# Use boost headers from staging
	if [ -d "$BOOST_STAGING_DIR/usr/include/boost" ]; then
		BOOST_INCLUDE="-I$BOOST_STAGING_DIR/usr/include"
		info_msg "Using boost headers from staged libboost1.83-dev package"
	else
		error_msg "Boost headers not found in staged package: $BOOST_STAGING_DIR/usr/include/boost"
		return 1
	fi
	
	if [ -n "$BOOST_INCLUDE" ]; then
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
	
	# Build (Makefile now has all correct include paths and library paths)
	# Explicitly pass CC and CXX to make to ensure cross-compiler is used
	make all CC="$CC" CXX="$CXX" || {
		error_msg "Build failed"
		return 1
	}

	# Install libraries
	if [ -f "$AML_BUILD_DIR/libamaudioutils.so" ]; then
		install -m 644 "$AML_BUILD_DIR/libamaudioutils.so" "${pkgdir}/usr/lib/"
		${STRIP} "${pkgdir}/usr/lib/libamaudioutils.so" 2>/dev/null || true
	else
		error_msg "libamaudioutils.so not found after build"
		return 1
	fi

	if [ -f "$AML_BUILD_DIR/libcutils.so" ]; then
		install -m 644 "$AML_BUILD_DIR/libcutils.so" "${pkgdir}/usr/lib/"
		${STRIP} "${pkgdir}/usr/lib/libcutils.so" 2>/dev/null || true
	else
		error_msg "libcutils.so not found after build"
		return 1
	fi

	# Install headers
	if [ -d "$PKG_BUILD_DIR/include/audio_utils" ]; then
		install -m 644 "$PKG_BUILD_DIR/include/audio_utils"/* "${pkgdir}/usr/include/audio_utils/" 2>/dev/null || true
	fi
	if [ -d "$PKG_BUILD_DIR/include/IpcBuffer" ]; then
		install -m 644 "$PKG_BUILD_DIR/include/IpcBuffer"/* "${pkgdir}/usr/include/IpcBuffer/" 2>/dev/null || true
	fi

	info_msg "Building Debian package: $PKG_NAME"
	fakeroot dpkg-deb -b -Zxz $pkgdir ${pkgdir}.deb

	# Overwrite package directory contents instead of removing (next build will recreate it)
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

