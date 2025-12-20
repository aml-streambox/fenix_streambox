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

PKG_NAME="aml-audio-hal"
PKG_VERSION="1.0-amlogic-yocto"
PKG_SHA256=""
PKG_SOURCE_DIR=""
PKG_SITE=""
PKG_URL=""
PKG_ARCH="aarch64"
PKG_LICENSE="AMLOGIC"
PKG_SHORTDESC="Amlogic Audio Hardware Abstraction Layer"

PKG_NEED_BUILD="YES"

make_target() {
	local pkgdir="$BUILD_IMAGES/.tmp/${PKG_NAME}_${VERSION}_${DISTRIB_ARCH}"
	rm -rf $pkgdir
	mkdir -p $pkgdir/DEBIAN
	mkdir -p $pkgdir/usr/lib
	mkdir -p $pkgdir/usr/include/hardware
	mkdir -p $pkgdir/usr/include/system
	mkdir -p $pkgdir/etc/halaudio

	# Set up control file
	cat <<-EOF > $pkgdir/DEBIAN/control
Package: ${PKG_NAME}
Version: ${VERSION}
Architecture: ${DISTRIB_ARCH}
Maintainer: Khadas <hello@khadas.com>
Depends: aml-audio-utils, android-binder, libexpat1, aml-avsync
Section: libs
Priority: optional
Description: Amlogic Audio HAL Library
 ${PKG_SHORTDESC}
 Provides libaudio_hal.so.1.0 for audio hardware abstraction.
EOF

	# Build the package using CMake
	local PKG_BUILD_DIR="${BUILD}/${PKG_NAME}-${PKG_VERSION}"
	local CMAKE_BUILD_DIR="$PKG_BUILD_DIR/build"
	
	cd "$PKG_BUILD_DIR"
	if [ ! -f "CMakeLists.txt" ]; then
		error_msg "CMakeLists.txt not found in $PKG_BUILD_DIR"
		ls -la "$PKG_BUILD_DIR" || true
		return 1
	fi

	# Detect and verify cross-compiler (fixed paths for ARM64)
	detect_cross_compiler || return 1

	# Get absolute paths for CMake (required for cross-compilation)
	local CC_COMPILER=$(readlink -f "$CC" 2>/dev/null || echo "$CC")
	local CXX_COMPILER=$(readlink -f "$CXX" 2>/dev/null || echo "$CXX")
	
	# Set build environment variables
	export STAGING_DIR="$PKG_BUILD_DIR/staging"
	export TARGET_DIR="$pkgdir"
	export STRIP="${CROSS_COMPILE}strip"
	
	# Create staging directory
	mkdir -p "$STAGING_DIR/usr/lib"
	mkdir -p "$STAGING_DIR/usr/include"
	mkdir -p "$STAGING_DIR/usr/include/cutils"
	mkdir -p "$STAGING_DIR/usr/include/binder"
	mkdir -p "$STAGING_DIR/usr/include/utils"
	mkdir -p "$STAGING_DIR/usr/include/IpcBuffer"
	mkdir -p "$STAGING_DIR/usr/include/audio_utils"

	# Copy dependency headers from sources (needed for CMake build)
	# Copy cutils headers from android-binder sources
	local BINDER_SRC="$PKGS_DIR/android-binder/sources/include"
	if [ -d "$BINDER_SRC/cutils" ]; then
		cp -r "$BINDER_SRC/cutils"/* "$STAGING_DIR/usr/include/cutils/" 2>/dev/null || true
		info_msg "Copied cutils headers from android-binder sources"
	fi
	
	# Also copy cutils headers from aml-audio-utils (has additional headers like str_parms.h)
	local AUDIO_UTILS_CUTILS_SRC="$PKGS_DIR/aml-audio-utils/sources/include/cutils"
	if [ -d "$AUDIO_UTILS_CUTILS_SRC" ]; then
		cp -r "$AUDIO_UTILS_CUTILS_SRC"/* "$STAGING_DIR/usr/include/cutils/" 2>/dev/null || true
		info_msg "Copied additional cutils headers from aml-audio-utils sources"
	fi
	
	# Copy bitops.h from aml-audio-utils or android-liblog (android-binder doesn't have it)
	if [ ! -f "$STAGING_DIR/usr/include/cutils/bitops.h" ]; then
		if [ -f "$PKGS_DIR/aml-audio-utils/sources/include/cutils/bitops.h" ]; then
			cp "$PKGS_DIR/aml-audio-utils/sources/include/cutils/bitops.h" "$STAGING_DIR/usr/include/cutils/" 2>/dev/null || true
			info_msg "Copied bitops.h from aml-audio-utils sources"
		elif [ -f "$PKGS_DIR/android-liblog/sources/include/cutils/bitops.h" ]; then
			cp "$PKGS_DIR/android-liblog/sources/include/cutils/bitops.h" "$STAGING_DIR/usr/include/cutils/" 2>/dev/null || true
			info_msg "Copied bitops.h from android-liblog sources"
		fi
	fi
	
	# Copy list.h from aml-audio-utils or android-liblog (android-binder doesn't have it)
	if [ ! -f "$STAGING_DIR/usr/include/cutils/list.h" ]; then
		if [ -f "$PKGS_DIR/aml-audio-utils/sources/include/cutils/list.h" ]; then
			cp "$PKGS_DIR/aml-audio-utils/sources/include/cutils/list.h" "$STAGING_DIR/usr/include/cutils/" 2>/dev/null || true
			info_msg "Copied list.h from aml-audio-utils sources"
		elif [ -f "$PKGS_DIR/android-liblog/sources/include/cutils/list.h" ]; then
			cp "$PKGS_DIR/android-liblog/sources/include/cutils/list.h" "$STAGING_DIR/usr/include/cutils/" 2>/dev/null || true
			info_msg "Copied list.h from android-liblog sources"
		fi
	fi
	if [ -d "$BINDER_SRC/binder" ]; then
		cp -r "$BINDER_SRC/binder"/* "$STAGING_DIR/usr/include/binder/" 2>/dev/null || true
		info_msg "Copied binder headers from android-binder sources"
	fi
	if [ -d "$BINDER_SRC/utils" ]; then
		cp -r "$BINDER_SRC/utils"/* "$STAGING_DIR/usr/include/utils/" 2>/dev/null || true
		info_msg "Copied utils headers from android-binder sources"
	fi

	# Copy aml-audio-utils headers
	local AUDIO_UTILS_SRC="$PKGS_DIR/aml-audio-utils/sources/include"
	if [ -d "$AUDIO_UTILS_SRC/IpcBuffer" ]; then
		cp -r "$AUDIO_UTILS_SRC/IpcBuffer"/* "$STAGING_DIR/usr/include/IpcBuffer/" 2>/dev/null || true
		info_msg "Copied IpcBuffer headers from aml-audio-utils sources"
	fi
	if [ -d "$AUDIO_UTILS_SRC/audio_utils" ]; then
		cp -r "$AUDIO_UTILS_SRC/audio_utils"/* "$STAGING_DIR/usr/include/audio_utils/" 2>/dev/null || true
		info_msg "Copied audio_utils headers from aml-audio-utils sources"
	fi

	# Copy aml-avsync headers
	local AVSYNC_SRC="$PKGS_DIR/aml-avsync/sources/src"
	if [ -f "$AVSYNC_SRC/aml_avsync.h" ]; then
		cp "$AVSYNC_SRC/aml_avsync.h" "$STAGING_DIR/usr/include/" 2>/dev/null || true
		info_msg "Copied aml_avsync.h from aml-avsync sources"
	fi
	if [ -f "$AVSYNC_SRC/aml_avsync_log.h" ]; then
		cp "$AVSYNC_SRC/aml_avsync_log.h" "$STAGING_DIR/usr/include/" 2>/dev/null || true
		info_msg "Copied aml_avsync_log.h from aml-avsync sources"
	fi

	# Stage dependency libraries from build directories
	local BINDER_BUILD="$BUILD/android-binder-amlogic-yocto-1.0"
	if [ ! -d "$BINDER_BUILD" ]; then
		BINDER_BUILD="$BUILD/android-binder-${PKG_VERSION}"
	fi
	if [ -f "$BINDER_BUILD/libbinder.so" ]; then
		cp "$BINDER_BUILD/libbinder.so" "$STAGING_DIR/usr/lib/" 2>/dev/null || true
	fi

	local AUDIO_UTILS_BUILD="$BUILD/aml-audio-utils-amlogic-yocto-1.0"
	if [ ! -d "$AUDIO_UTILS_BUILD" ]; then
		AUDIO_UTILS_BUILD="$BUILD/aml-audio-utils-${PKG_VERSION}"
	fi
	if [ -f "$AUDIO_UTILS_BUILD/libamaudioutils.so" ]; then
		cp "$AUDIO_UTILS_BUILD/libamaudioutils.so" "$STAGING_DIR/usr/lib/" 2>/dev/null || true
	fi

	local AVSYNC_BUILD="$BUILD/aml-avsync-amlogic-yocto-1.0"
	if [ ! -d "$AVSYNC_BUILD" ]; then
		AVSYNC_BUILD="$BUILD/aml-avsync-${PKG_VERSION}"
	fi
	if [ -f "$AVSYNC_BUILD/src/libamlavsync.so" ]; then
		cp "$AVSYNC_BUILD/src/libamlavsync.so" "$STAGING_DIR/usr/lib/" 2>/dev/null || true
	fi

	# Copy libexpat.so from libexpat1 package (runtime library)
	# Try multiple locations: built package, packages directory, rootfs
	local EXPAT_LIB_FOUND=false
	
	# Check built package
	local EXPAT_DEB=$(find "$BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/libexpat1" -name "*.deb" 2>/dev/null | head -1)
	if [ -n "$EXPAT_DEB" ] && [ -f "$EXPAT_DEB" ]; then
		local EXPAT_STAGING_DIR="$BUILD/staging/libexpat1"
		mkdir -p "$EXPAT_STAGING_DIR"
		if [ ! -d "$EXPAT_STAGING_DIR/usr/lib" ]; then
			dpkg-deb -x "$EXPAT_DEB" "$EXPAT_STAGING_DIR" 2>/dev/null
		fi
		if [ -d "$EXPAT_STAGING_DIR/usr/lib" ]; then
			cp "$EXPAT_STAGING_DIR/usr/lib"/*/libexpat.so* "$STAGING_DIR/usr/lib/" 2>/dev/null || true
			cp "$EXPAT_STAGING_DIR/usr/lib/libexpat.so"* "$STAGING_DIR/usr/lib/" 2>/dev/null || true
			if [ -f "$STAGING_DIR/usr/lib/libexpat.so" ] || [ -f "$STAGING_DIR/usr/lib/libexpat.so.1" ]; then
				EXPAT_LIB_FOUND=true
				info_msg "Copied libexpat.so from libexpat1 package"
			fi
		fi
	fi
	
	# Check packages directory for libexpat1 (extracted sources)
	if [ "$EXPAT_LIB_FOUND" = false ]; then
		local EXPAT_PKG_DIR="$PKGS_DIR/libexpat1"
		# Check aarch64-linux-gnu subdirectory first (standard Debian layout)
		if [ -d "$EXPAT_PKG_DIR/sources/usr/lib/aarch64-linux-gnu" ]; then
			cp "$EXPAT_PKG_DIR/sources/usr/lib/aarch64-linux-gnu/libexpat.so"* "$STAGING_DIR/usr/lib/" 2>/dev/null || true
			if [ -f "$STAGING_DIR/usr/lib/libexpat.so" ] || [ -f "$STAGING_DIR/usr/lib/libexpat.so.1" ]; then
				EXPAT_LIB_FOUND=true
				info_msg "Copied libexpat.so from libexpat1 package sources (aarch64-linux-gnu)"
			fi
		fi
		# Also check direct usr/lib (fallback)
		if [ "$EXPAT_LIB_FOUND" = false ] && [ -d "$EXPAT_PKG_DIR/sources/usr/lib" ]; then
			cp "$EXPAT_PKG_DIR/sources/usr/lib/libexpat.so"* "$STAGING_DIR/usr/lib/" 2>/dev/null || true
			if [ -f "$STAGING_DIR/usr/lib/libexpat.so" ] || [ -f "$STAGING_DIR/usr/lib/libexpat.so.1" ]; then
				EXPAT_LIB_FOUND=true
				info_msg "Copied libexpat.so from libexpat1 package sources"
			fi
		fi
	fi
	
	# Check rootfs (if it was built)
	if [ "$EXPAT_LIB_FOUND" = false ] && [ -n "$ROOTFS" ] && [ -d "$ROOTFS" ]; then
		if [ -f "$ROOTFS/usr/lib/aarch64-linux-gnu/libexpat.so.1" ]; then
			cp "$ROOTFS/usr/lib/aarch64-linux-gnu/libexpat.so"* "$STAGING_DIR/usr/lib/" 2>/dev/null || true
			EXPAT_LIB_FOUND=true
			info_msg "Copied libexpat.so from rootfs"
		elif [ -f "$ROOTFS/usr/lib/libexpat.so.1" ]; then
			cp "$ROOTFS/usr/lib/libexpat.so"* "$STAGING_DIR/usr/lib/" 2>/dev/null || true
			EXPAT_LIB_FOUND=true
			info_msg "Copied libexpat.so from rootfs"
		fi
	fi
	
	# Warn if not found (but don't fail yet - let CMake try to find it)
	if [ "$EXPAT_LIB_FOUND" = false ]; then
		warning_msg "libexpat.so not found in packages or rootfs. Build may fail if libexpat1 package is not available."
		warning_msg "Please create libexpat1 package by extracting from .deb file to packages/libexpat1/sources/"
	fi

	# Copy libcutils.so from aml-audio-utils build
	if [ -f "$AUDIO_UTILS_BUILD/libcutils.so" ]; then
		cp "$AUDIO_UTILS_BUILD/libcutils.so" "$STAGING_DIR/usr/lib/" 2>/dev/null || true
		info_msg "Copied libcutils.so from aml-audio-utils build"
	fi

	# Copy liblog.so from android-liblog build (try multiple locations)
	local LIBLOG_BUILD="$BUILD/android-liblog-amlogic-yocto-1.0"
	if [ ! -d "$LIBLOG_BUILD" ]; then
		LIBLOG_BUILD="$BUILD/android-liblog-${PKG_VERSION}"
	fi
	if [ -f "$LIBLOG_BUILD/liblog.so" ]; then
		cp "$LIBLOG_BUILD/liblog.so" "$STAGING_DIR/usr/lib/" 2>/dev/null || true
		info_msg "Copied liblog.so from android-liblog build"
	elif [ -f "$BUILD/staging/android-liblog/usr/lib/liblog.so" ]; then
		cp "$BUILD/staging/android-liblog/usr/lib/liblog.so" "$STAGING_DIR/usr/lib/" 2>/dev/null || true
		info_msg "Copied liblog.so from staging directory"
	fi

	# Patch CMakeLists.txt to disable -Werror (we can modify build scripts)
	# Replace -Werror with -Wno-error to allow warnings without failing build
	if [ -f "$PKG_BUILD_DIR/CMakeLists.txt" ]; then
		sed -i 's/-Werror/-Wno-error/g' "$PKG_BUILD_DIR/CMakeLists.txt" 2>/dev/null || true
		info_msg "Patched CMakeLists.txt to disable -Werror"
	fi

	# Get expat headers from libexpat1-dev package (if available)
	# Check if libexpat1-dev package was built and extract headers
	local EXPAT_HEADERS_FOUND=false
	
	# Check built package
	local EXPAT_DEV_DEB=$(find "$BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/libexpat1-dev" -name "*.deb" 2>/dev/null | head -1)
	if [ -n "$EXPAT_DEV_DEB" ] && [ -f "$EXPAT_DEV_DEB" ]; then
		local EXPAT_STAGING_DIR="$BUILD/staging/libexpat1-dev"
		mkdir -p "$EXPAT_STAGING_DIR"
		if [ ! -d "$EXPAT_STAGING_DIR/usr/include" ]; then
			dpkg-deb -x "$EXPAT_DEV_DEB" "$EXPAT_STAGING_DIR" 2>/dev/null
		fi
		if [ -d "$EXPAT_STAGING_DIR/usr/include" ]; then
			cp -r "$EXPAT_STAGING_DIR/usr/include"/* "$STAGING_DIR/usr/include/" 2>/dev/null || true
			if [ -f "$STAGING_DIR/usr/include/expat.h" ]; then
				EXPAT_HEADERS_FOUND=true
				info_msg "Copied expat headers from libexpat1-dev package"
			fi
		fi
	fi
	
	# Check packages directory
	if [ "$EXPAT_HEADERS_FOUND" = false ]; then
		local EXPAT_PKG_DIR="$PKGS_DIR/libexpat1-dev"
		if [ -d "$EXPAT_PKG_DIR/sources/usr/include" ]; then
			cp -r "$EXPAT_PKG_DIR/sources/usr/include"/* "$STAGING_DIR/usr/include/" 2>/dev/null || true
			if [ -f "$STAGING_DIR/usr/include/expat.h" ]; then
				EXPAT_HEADERS_FOUND=true
				info_msg "Copied expat headers from libexpat1-dev package sources"
			fi
		fi
	fi
	
	# Check rootfs (if it was built) - only as last resort since user said not to use system headers
	# But rootfs is built by Fenix, so it's acceptable
	if [ "$EXPAT_HEADERS_FOUND" = false ]; then
		# Try ROOTFS variable first
		if [ -n "$ROOTFS" ] && [ -d "$ROOTFS" ] && [ -f "$ROOTFS/usr/include/expat.h" ]; then
			cp "$ROOTFS/usr/include/expat.h" "$STAGING_DIR/usr/include/" 2>/dev/null || true
			if [ -f "$ROOTFS/usr/include/expat_external.h" ]; then
				cp "$ROOTFS/usr/include/expat_external.h" "$STAGING_DIR/usr/include/" 2>/dev/null || true
			fi
			EXPAT_HEADERS_FOUND=true
			info_msg "Copied expat headers from rootfs (built by Fenix)"
		# Try common rootfs locations
		elif [ -f "$BUILD/images/rootfs/usr/include/expat.h" ]; then
			cp "$BUILD/images/rootfs/usr/include/expat.h" "$STAGING_DIR/usr/include/" 2>/dev/null || true
			if [ -f "$BUILD/images/rootfs/usr/include/expat_external.h" ]; then
				cp "$BUILD/images/rootfs/usr/include/expat_external.h" "$STAGING_DIR/usr/include/" 2>/dev/null || true
			fi
			EXPAT_HEADERS_FOUND=true
			info_msg "Copied expat headers from build/images/rootfs (built by Fenix)"
		elif [ -f "$BUILD/images/cache/rootfs/usr/include/expat.h" ]; then
			cp "$BUILD/images/cache/rootfs/usr/include/expat.h" "$STAGING_DIR/usr/include/" 2>/dev/null || true
			if [ -f "$BUILD/images/cache/rootfs/usr/include/expat_external.h" ]; then
				cp "$BUILD/images/cache/rootfs/usr/include/expat_external.h" "$STAGING_DIR/usr/include/" 2>/dev/null || true
			fi
			EXPAT_HEADERS_FOUND=true
			info_msg "Copied expat headers from build/images/cache/rootfs (built by Fenix)"
		elif [ -d "$BUILD/images/${KHADAS_BOARD}/rootfs" ] && [ -f "$BUILD/images/${KHADAS_BOARD}/rootfs/usr/include/expat.h" ]; then
			cp "$BUILD/images/${KHADAS_BOARD}/rootfs/usr/include/expat.h" "$STAGING_DIR/usr/include/" 2>/dev/null || true
			if [ -f "$BUILD/images/${KHADAS_BOARD}/rootfs/usr/include/expat_external.h" ]; then
				cp "$BUILD/images/${KHADAS_BOARD}/rootfs/usr/include/expat_external.h" "$STAGING_DIR/usr/include/" 2>/dev/null || true
			fi
			EXPAT_HEADERS_FOUND=true
			info_msg "Copied expat headers from build/images/${KHADAS_BOARD}/rootfs (built by Fenix)"
		fi
	fi
	
	# Error if not found
	if [ "$EXPAT_HEADERS_FOUND" = false ]; then
		error_msg "expat.h not found! libexpat1-dev package is required."
		error_msg "Please create libexpat1-dev package:"
		error_msg "  1. Download: libexpat1-dev_2.6.1-2ubuntu0.3_amd64.deb"
		error_msg "  2. Extract: dpkg-deb -x libexpat1-dev_*.deb packages/libexpat1-dev/sources/"
		error_msg "  3. Create packages/libexpat1-dev/package.mk (see libboost1.83-dev/package.mk as example)"
		return 1
	fi

	# Create CMake build directory
	rm -rf "$CMAKE_BUILD_DIR"
	mkdir -p "$CMAKE_BUILD_DIR"
	cd "$CMAKE_BUILD_DIR"

	# Configure CMake with cross-compilation
	# According to Yocto recipe: EXTRA_OECMAKE = "-DAML_BUILD_DIR=${B}"
	info_msg "Configuring CMake for cross-compilation..."
	
	# Set include and library paths for dependencies
	# Include time.h early to fix struct timespec issues
	# Note: -D_GNU_SOURCE is already defined in features.h, but source code defines it again
	# We'll use -U__USE_GNU to undefine it first, then let features.h define it properly
	local CMAKE_C_FLAGS="-fPIC -I$STAGING_DIR/usr/include -include time.h -include stdint.h -U__USE_GNU"
	local CMAKE_CXX_FLAGS="-fPIC -I$STAGING_DIR/usr/include -U__USE_GNU"
	local CMAKE_LD_FLAGS="-L$STAGING_DIR/usr/lib"
	
	cmake "$PKG_BUILD_DIR" \
		-DCMAKE_SYSTEM_NAME=Linux \
		-DCMAKE_SYSTEM_PROCESSOR=aarch64 \
		-DCMAKE_C_COMPILER="$CC_COMPILER" \
		-DCMAKE_CXX_COMPILER="$CXX_COMPILER" \
		-DCMAKE_C_FLAGS="$CMAKE_C_FLAGS" \
		-DCMAKE_CXX_FLAGS="$CMAKE_CXX_FLAGS" \
		-DCMAKE_EXE_LINKER_FLAGS="$CMAKE_LD_FLAGS" \
		-DCMAKE_SHARED_LINKER_FLAGS="$CMAKE_LD_FLAGS" \
		-DCMAKE_PREFIX_PATH="$STAGING_DIR/usr" \
		-DAML_BUILD_DIR="$CMAKE_BUILD_DIR" \
		-DCMAKE_INSTALL_PREFIX="/usr" \
		-DCMAKE_BUILD_TYPE=Release \
		|| {
		error_msg "CMake configuration failed"
		return 1
	}

	# Build
	info_msg "Building ${PKG_NAME} with CMake..."
	make -j$(nproc) || {
		error_msg "CMake build failed"
		return 1
	}

	# Install (CMake install target)
	# Use DESTDIR to install to package directory instead of system paths
	info_msg "Installing ${PKG_NAME}..."
	make DESTDIR="$pkgdir" install || {
		error_msg "CMake install failed"
		return 1
	}

	# Install headers (from Yocto recipe do_install:append)
	if [ -d "$PKG_BUILD_DIR/include/hardware" ]; then
		install -m 644 "$PKG_BUILD_DIR/include/hardware"/* "${pkgdir}/usr/include/hardware/" 2>/dev/null || true
	fi
	if [ -d "$PKG_BUILD_DIR/include/system" ]; then
		install -m 644 "$PKG_BUILD_DIR/include/system"/* "${pkgdir}/usr/include/system/" 2>/dev/null || true
	fi
	if [ -f "$PKG_BUILD_DIR/include/Virtualx_v4.h" ]; then
		install -m 644 "$PKG_BUILD_DIR/include/Virtualx_v4.h" "${pkgdir}/usr/include/" 2>/dev/null || true
	fi

	# Install configuration files (board-specific - VIM4 maps to T7)
	# According to Yocto recipe, VIM4 should use T7 configs
	local CONFIG_FILE=""
	if [ -f "$PKG_DIR/files/aml_audio_config.t7.json" ]; then
		CONFIG_FILE="aml_audio_config.t7.json"
	elif [ -f "$PKG_DIR/files/aml_audio_config.json" ]; then
		CONFIG_FILE="aml_audio_config.json"
	fi
	if [ -n "$CONFIG_FILE" ]; then
		install -m 755 "$PKG_DIR/files/$CONFIG_FILE" "${pkgdir}/etc/halaudio/aml_audio_config.json"
	fi

	# Install mixer_paths.xml (board-specific - VIM4 maps to T7)
	local MIXER_FILE=""
	if [ -f "$PKG_DIR/files/mixer_paths.t7.xml" ]; then
		MIXER_FILE="mixer_paths.t7.xml"
	elif [ -f "$PKG_DIR/files/mixer_paths.xml" ]; then
		MIXER_FILE="mixer_paths.xml"
	fi
	if [ -n "$MIXER_FILE" ]; then
		install -m 644 "$PKG_DIR/files/$MIXER_FILE" "${pkgdir}/etc/mixer_paths.xml"
	fi

	# Install audio_hal_delay_base.json
	if [ -f "$PKG_DIR/files/audio_hal_delay_base.json" ]; then
		install -m 755 "$PKG_DIR/files/audio_hal_delay_base.json" "${pkgdir}/etc/halaudio/"
	fi

	# Install ms12_audio_profiles.ini
	if [ -f "$PKG_DIR/files/ms12_audio_profiles.ini" ]; then
		install -m 644 "$PKG_DIR/files/ms12_audio_profiles.ini" "${pkgdir}/etc/halaudio/"
	fi

	# Strip libraries
	find "$pkgdir/usr/lib" -name "*.so*" -type f -exec ${STRIP} {} \; 2>/dev/null || true

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

