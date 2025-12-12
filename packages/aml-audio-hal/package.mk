PKG_NAME="aml-audio-hal"
PKG_VERSION="amlogic-yocto-1.0"
PKG_SHA256=""
PKG_SOURCE_DIR=""
PKG_SITE=""
PKG_URL=""
PKG_ARCH="arm aarch64"
PKG_LICENSE="AMLOGIC"
PKG_SHORTDESC="Amlogic Audio Hardware Abstraction Layer"

PKG_NEED_BUILD="YES"

make_target() {
	local pkgdir="$BUILD_IMAGES/.tmp/${PKG_NAME}_${VERSION}_${DISTRIB_ARCH}"
	# Overwrite by recreating directory structure
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
	cd "$PKG_BUILD_DIR"
	if [ ! -f CMakeLists.txt ]; then
		error_msg "CMakeLists.txt not found in $PKG_BUILD_DIR"
		ls -la "$PKG_BUILD_DIR" || true
		return 1
	fi

	# Set build environment variables
	export AML_BUILD_DIR="$PKG_BUILD_DIR"
	export STRIP="${CROSS_COMPILE}strip"
	
	# Create build directory
	mkdir -p "$PKG_BUILD_DIR/build"
	cd "$PKG_BUILD_DIR/build"
	
	# Set up library and include paths for dependencies
	local CMAKE_PREFIX_PATH=""
	local CMAKE_INCLUDE_PATH=""
	local CMAKE_LIBRARY_PATH=""
	
	# Add aml-audio-utils paths (provides libamaudioutils.so and libcutils.so)
	local AUDIO_UTILS_BUILD="$BUILD/aml-audio-utils-amlogic-yocto-1.0"
	if [ -d "$AUDIO_UTILS_BUILD" ]; then
		CMAKE_PREFIX_PATH="$AUDIO_UTILS_BUILD:$CMAKE_PREFIX_PATH"
		CMAKE_INCLUDE_PATH="$AUDIO_UTILS_BUILD/include:$CMAKE_INCLUDE_PATH"
		# Add library path - check staging directory first, then root
		if [ -d "$AUDIO_UTILS_BUILD/staging/usr/lib" ]; then
			CMAKE_LIBRARY_PATH="$AUDIO_UTILS_BUILD/staging/usr/lib:$CMAKE_LIBRARY_PATH"
		elif [ -d "$AUDIO_UTILS_BUILD/lib" ]; then
			CMAKE_LIBRARY_PATH="$AUDIO_UTILS_BUILD/lib:$CMAKE_LIBRARY_PATH"
		else
			CMAKE_LIBRARY_PATH="$AUDIO_UTILS_BUILD:$CMAKE_LIBRARY_PATH"
		fi
	fi
	
	# Add android-binder paths (includes cutils headers and libcutils.so)
	local BINDER_BUILD="$BUILD/android-binder-amlogic-yocto-1.0"
	local BINDER_SRC="$PKGS_DIR/android-binder/sources/include"
	if [ -d "$BINDER_BUILD" ]; then
		CMAKE_PREFIX_PATH="$BINDER_BUILD:$CMAKE_PREFIX_PATH"
		CMAKE_INCLUDE_PATH="$BINDER_BUILD/include:$CMAKE_INCLUDE_PATH"
		# Add libbinder.so and libcutils.so library path - check both root and lib directory
		if [ -d "$BINDER_BUILD/lib" ]; then
			CMAKE_LIBRARY_PATH="$BINDER_BUILD/lib:$CMAKE_LIBRARY_PATH"
		else
			CMAKE_LIBRARY_PATH="$BINDER_BUILD:$CMAKE_LIBRARY_PATH"
		fi
	fi
	# Also add cutils headers from binder sources if available
	if [ -d "$BINDER_SRC/cutils" ]; then
		CMAKE_INCLUDE_PATH="$(dirname "$BINDER_SRC"):$CMAKE_INCLUDE_PATH"
	fi
	
	# Add android-liblog paths (also provides cutils headers and liblog.so)
	local LIBLOG_BUILD="$BUILD/android-liblog-amlogic-yocto-1.0"
	if [ -d "$LIBLOG_BUILD" ]; then
		CMAKE_PREFIX_PATH="$LIBLOG_BUILD:$CMAKE_PREFIX_PATH"
		CMAKE_INCLUDE_PATH="$LIBLOG_BUILD/include:$CMAKE_INCLUDE_PATH"
		# Add liblog.so library path - check both root and lib directory
		if [ -d "$LIBLOG_BUILD/lib" ]; then
			CMAKE_LIBRARY_PATH="$LIBLOG_BUILD/lib:$CMAKE_LIBRARY_PATH"
		else
			CMAKE_LIBRARY_PATH="$LIBLOG_BUILD:$CMAKE_LIBRARY_PATH"
		fi
	fi
	
	# Add aml-avsync paths
	local AVSYNC_BUILD="$BUILD/aml-avsync-amlogic-yocto-1.0"
	if [ -d "$AVSYNC_BUILD" ]; then
		CMAKE_PREFIX_PATH="$AVSYNC_BUILD:$CMAKE_PREFIX_PATH"
		CMAKE_INCLUDE_PATH="$AVSYNC_BUILD/include:$CMAKE_INCLUDE_PATH"
		CMAKE_LIBRARY_PATH="$AVSYNC_BUILD:$CMAKE_LIBRARY_PATH"
	fi
	
	# Add rootfs paths for Debian packages (expat, etc.)
	if [ -d "$ROOTFS_TEMP/usr/lib" ]; then
		CMAKE_LIBRARY_PATH="$ROOTFS_TEMP/usr/lib:$CMAKE_LIBRARY_PATH"
	fi
	if [ -d "$ROOTFS_TEMP/usr/include" ]; then
		CMAKE_INCLUDE_PATH="$ROOTFS_TEMP/usr/include:$CMAKE_INCLUDE_PATH"
	fi
	
	export CMAKE_PREFIX_PATH
	export CMAKE_INCLUDE_PATH
	export CMAKE_LIBRARY_PATH
	
	# Determine board-specific config files
	# VIM4 uses A311D2 (T7 family), try t7 config first
	local AUDIO_CONFIG="aml_audio_config.json"
	local MIXER_CONFIG="mixer_paths.xml"
	local AVSYNC_CONFIG="audio_hal_delay_base.json"
	
	# Map KHADAS_BOARD to config files (VIM4 is typically T7)
	if [ "$KHADAS_BOARD" = "VIM4" ]; then
		if [ -f "$PKGS_DIR/${PKG_NAME}/files/aml_audio_config.t7.json" ]; then
			AUDIO_CONFIG="aml_audio_config.t7.json"
		fi
		if [ -f "$PKGS_DIR/${PKG_NAME}/files/mixer_paths.t7.xml" ]; then
			MIXER_CONFIG="mixer_paths.t7.xml"
		fi
	fi
	
	# Configure CMake for cross-compilation
	info_msg "Configuring ${PKG_NAME} with CMake..."
	
	# Get cross-compiler path - check if CROSS_COMPILE is set, otherwise use default
	local CC_COMPILER="${CROSS_COMPILE}gcc"
	local CXX_COMPILER="${CROSS_COMPILE}g++"
	
	# Verify cross-compiler exists, fallback to checking PATH
	if ! command -v "$CC_COMPILER" >/dev/null 2>&1; then
		# Try to find it in common toolchain locations
		if [ -f "$TOOLCHAINS/aarch64-linux-gnu/bin/aarch64-linux-gnu-gcc" ]; then
			CC_COMPILER="$TOOLCHAINS/aarch64-linux-gnu/bin/aarch64-linux-gnu-gcc"
			CXX_COMPILER="$TOOLCHAINS/aarch64-linux-gnu/bin/aarch64-linux-gnu-g++"
		elif command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
			CC_COMPILER="aarch64-linux-gnu-gcc"
			CXX_COMPILER="aarch64-linux-gnu-g++"
		else
			error_msg "Cross-compiler not found. CROSS_COMPILE='${CROSS_COMPILE}', tried: $CC_COMPILER"
			return 1
		fi
	fi
	
	# Get absolute path to compiler to avoid CMake picking up wrong compiler from rootfs
	CC_COMPILER=$(command -v "$CC_COMPILER")
	CXX_COMPILER=$(command -v "$CXX_COMPILER")
	
	if [ -z "$CC_COMPILER" ] || [ -z "$CXX_COMPILER" ]; then
		error_msg "Failed to resolve compiler paths: C=$CC_COMPILER, CXX=$CXX_COMPILER"
		return 1
	fi
	
	info_msg "Using cross-compiler: C=$CC_COMPILER, CXX=$CXX_COMPILER"
	
	# Prepare cutils headers for CMake - copy to a staging location that CMake can find
	local STAGING_INCLUDE_DIR="$PKG_BUILD_DIR/staging/include"
	mkdir -p "$STAGING_INCLUDE_DIR/cutils"
	mkdir -p "$STAGING_INCLUDE_DIR/audio_utils"
	mkdir -p "$STAGING_INCLUDE_DIR/android"
	mkdir -p "$STAGING_INCLUDE_DIR/IpcBuffer"
	
	# Copy cutils headers from android-binder sources
	if [ -d "$BINDER_SRC/cutils" ]; then
		cp -r "$BINDER_SRC/cutils"/* "$STAGING_INCLUDE_DIR/cutils/" 2>/dev/null || true
		info_msg "Copied cutils headers from android-binder sources"
	fi
	
	# Copy missing cutils headers (like bitops.h) from android-liblog sources
	local LIBLOG_SRC="$PKGS_DIR/android-liblog/sources/include"
	if [ -d "$LIBLOG_SRC/cutils" ]; then
		# Copy bitops.h and any other missing headers
		cp "$LIBLOG_SRC/cutils/bitops.h" "$STAGING_INCLUDE_DIR/cutils/" 2>/dev/null || true
		# Also copy from aml-audio-utils if available
		local AUDIO_UTILS_SRC="$PKGS_DIR/aml-audio-utils/sources/include"
		if [ -f "$AUDIO_UTILS_SRC/cutils/bitops.h" ] && [ ! -f "$STAGING_INCLUDE_DIR/cutils/bitops.h" ]; then
			cp "$AUDIO_UTILS_SRC/cutils/bitops.h" "$STAGING_INCLUDE_DIR/cutils/" 2>/dev/null || true
		fi
		info_msg "Copied additional cutils headers (bitops.h) from android-liblog/aml-audio-utils"
	fi
	
	# Also check build directories for cutils headers
	if [ -d "$LIBLOG_BUILD/include/cutils" ]; then
		# Copy any missing headers from liblog build
		for hdr in "$LIBLOG_BUILD/include/cutils"/*.h; do
			[ -f "$hdr" ] && cp "$hdr" "$STAGING_INCLUDE_DIR/cutils/" 2>/dev/null || true
		done
	fi
	
	# Copy audio_utils headers from aml-audio-utils sources or build
	local AUDIO_UTILS_SRC="$PKGS_DIR/aml-audio-utils/sources/include"
	if [ -d "$AUDIO_UTILS_SRC/audio_utils" ]; then
		cp -r "$AUDIO_UTILS_SRC/audio_utils"/* "$STAGING_INCLUDE_DIR/audio_utils/" 2>/dev/null || true
		info_msg "Copied audio_utils headers from aml-audio-utils sources"
	elif [ -d "$AUDIO_UTILS_BUILD/staging/usr/include/audio_utils" ]; then
		cp -r "$AUDIO_UTILS_BUILD/staging/usr/include/audio_utils"/* "$STAGING_INCLUDE_DIR/audio_utils/" 2>/dev/null || true
		info_msg "Copied audio_utils headers from aml-audio-utils build"
	fi
	
	# Copy IpcBuffer headers from aml-audio-utils sources or build
	if [ -d "$AUDIO_UTILS_SRC/IpcBuffer" ]; then
		cp -r "$AUDIO_UTILS_SRC/IpcBuffer"/* "$STAGING_INCLUDE_DIR/IpcBuffer/" 2>/dev/null || true
		info_msg "Copied IpcBuffer headers from aml-audio-utils sources"
	elif [ -d "$AUDIO_UTILS_BUILD/staging/usr/include/IpcBuffer" ]; then
		cp -r "$AUDIO_UTILS_BUILD/staging/usr/include/IpcBuffer"/* "$STAGING_INCLUDE_DIR/IpcBuffer/" 2>/dev/null || true
		info_msg "Copied IpcBuffer headers from aml-audio-utils build"
	fi
	
	# Copy android headers (needed by cutils/logd.h which includes android/log.h)
	local LIBLOG_SRC="$PKGS_DIR/android-liblog/sources/include"
	if [ -d "$LIBLOG_SRC/android" ]; then
		cp -r "$LIBLOG_SRC/android"/* "$STAGING_INCLUDE_DIR/android/" 2>/dev/null || true
		info_msg "Copied android headers from android-liblog sources"
	elif [ -d "$LIBLOG_BUILD/include/android" ]; then
		cp -r "$LIBLOG_BUILD/include/android"/* "$STAGING_INCLUDE_DIR/android/" 2>/dev/null || true
		info_msg "Copied android headers from android-liblog build"
	fi
	
	# Copy aml_avsync headers from aml-avsync sources or build
	local AVSYNC_SRC_DIR="$PKGS_DIR/aml-avsync/sources"
	# Check src directory first (where headers actually are)
	if [ -f "$AVSYNC_SRC_DIR/src/aml_avsync.h" ]; then
		cp "$AVSYNC_SRC_DIR/src/aml_avsync.h" "$STAGING_INCLUDE_DIR/" 2>/dev/null || true
		info_msg "Copied aml_avsync.h from aml-avsync sources"
	fi
	if [ -f "$AVSYNC_SRC_DIR/src/aml_avsync_log.h" ]; then
		cp "$AVSYNC_SRC_DIR/src/aml_avsync_log.h" "$STAGING_INCLUDE_DIR/" 2>/dev/null || true
		info_msg "Copied aml_avsync_log.h from aml-avsync sources"
	fi
	# Also check include directory
	if [ -f "$AVSYNC_SRC_DIR/include/aml_avsync.h" ]; then
		cp "$AVSYNC_SRC_DIR/include/aml_avsync.h" "$STAGING_INCLUDE_DIR/" 2>/dev/null || true
		info_msg "Copied aml_avsync.h from aml-avsync include directory"
	fi
	if [ -f "$AVSYNC_SRC_DIR/include/aml_avsync_log.h" ]; then
		cp "$AVSYNC_SRC_DIR/include/aml_avsync_log.h" "$STAGING_INCLUDE_DIR/" 2>/dev/null || true
		info_msg "Copied aml_avsync_log.h from aml-avsync include directory"
	fi
	# Also check build directory
	if [ ! -f "$STAGING_INCLUDE_DIR/aml_avsync.h" ]; then
		if [ -f "$AVSYNC_BUILD/src/aml_avsync.h" ]; then
			cp "$AVSYNC_BUILD/src/aml_avsync.h" "$STAGING_INCLUDE_DIR/" 2>/dev/null || true
			info_msg "Copied aml_avsync.h from aml-avsync build"
		elif [ -f "$AVSYNC_BUILD/include/aml_avsync.h" ]; then
			cp "$AVSYNC_BUILD/include/aml_avsync.h" "$STAGING_INCLUDE_DIR/" 2>/dev/null || true
			info_msg "Copied aml_avsync.h from aml-avsync build include"
		fi
	fi
	if [ ! -f "$STAGING_INCLUDE_DIR/aml_avsync_log.h" ]; then
		if [ -f "$AVSYNC_BUILD/src/aml_avsync_log.h" ]; then
			cp "$AVSYNC_BUILD/src/aml_avsync_log.h" "$STAGING_INCLUDE_DIR/" 2>/dev/null || true
			info_msg "Copied aml_avsync_log.h from aml-avsync build"
		elif [ -f "$AVSYNC_BUILD/include/aml_avsync_log.h" ]; then
			cp "$AVSYNC_BUILD/include/aml_avsync_log.h" "$STAGING_INCLUDE_DIR/" 2>/dev/null || true
			info_msg "Copied aml_avsync_log.h from aml-avsync build include"
		fi
	fi
	
	# Add the staging include directory to CMAKE_INCLUDE_PATH
	if [ -d "$STAGING_INCLUDE_DIR" ]; then
		CMAKE_INCLUDE_PATH="$STAGING_INCLUDE_DIR:$CMAKE_INCLUDE_PATH"
	fi
	export CMAKE_INCLUDE_PATH
	
	# Determine architecture for CMake
	local CMAKE_SYSTEM_PROCESSOR="aarch64"
	if [ "$DISTRIB_ARCH" = "arm" ]; then
		CMAKE_SYSTEM_PROCESSOR="arm"
	fi
	
	# Build include flags for CMake - add staging include path
	local CMAKE_C_FLAGS="-I$STAGING_INCLUDE_DIR"
	local CMAKE_CXX_FLAGS="-I$STAGING_INCLUDE_DIR"
	
	# Build library path flags for linker - ensure libcutils.so and liblog.so can be found
	local CMAKE_LD_FLAGS=""
	# Always add explicit paths to the libraries we need
	if [ -d "$BUILD/android-liblog-amlogic-yocto-1.0" ]; then
		CMAKE_LD_FLAGS="$CMAKE_LD_FLAGS -L$BUILD/android-liblog-amlogic-yocto-1.0"
	fi
	if [ -d "$BUILD/aml-audio-utils-amlogic-yocto-1.0" ]; then
		CMAKE_LD_FLAGS="$CMAKE_LD_FLAGS -L$BUILD/aml-audio-utils-amlogic-yocto-1.0"
	fi
	if [ -d "$BUILD/android-binder-amlogic-yocto-1.0" ]; then
		CMAKE_LD_FLAGS="$CMAKE_LD_FLAGS -L$BUILD/android-binder-amlogic-yocto-1.0"
	fi
	# Add aml-avsync library path (provides libamlavsync.so)
	if [ -d "$AVSYNC_BUILD" ]; then
		# Check if library is in src directory (where it's built)
		if [ -f "$AVSYNC_BUILD/src/libamlavsync.so" ]; then
			CMAKE_LD_FLAGS="$CMAKE_LD_FLAGS -L$AVSYNC_BUILD/src"
		else
			CMAKE_LD_FLAGS="$CMAKE_LD_FLAGS -L$AVSYNC_BUILD"
		fi
	fi
	# Also add any paths from CMAKE_LIBRARY_PATH
	if [ -n "$CMAKE_LIBRARY_PATH" ]; then
		# Convert CMAKE_LIBRARY_PATH (colon-separated) to -L flags
		IFS=':' read -ra LIB_DIRS <<< "$CMAKE_LIBRARY_PATH"
		for lib_dir in "${LIB_DIRS[@]}"; do
			[ -d "$lib_dir" ] && CMAKE_LD_FLAGS="$CMAKE_LD_FLAGS -L$lib_dir"
		done
	fi
	
	cmake .. \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_SYSTEM_NAME=Linux \
		-DCMAKE_SYSTEM_PROCESSOR="$CMAKE_SYSTEM_PROCESSOR" \
		-DCMAKE_C_COMPILER="$CC_COMPILER" \
		-DCMAKE_CXX_COMPILER="$CXX_COMPILER" \
		-DCMAKE_CROSSCOMPILING=ON \
		-DCMAKE_C_FLAGS="$CMAKE_C_FLAGS $CMAKE_LD_FLAGS" \
		-DCMAKE_CXX_FLAGS="$CMAKE_CXX_FLAGS $CMAKE_LD_FLAGS" \
		-DCMAKE_EXE_LINKER_FLAGS="$CMAKE_LD_FLAGS" \
		-DCMAKE_SHARED_LINKER_FLAGS="$CMAKE_LD_FLAGS" \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DAML_BUILD_DIR="$PKG_BUILD_DIR" \
		-DUSE_MSYNC=ON \
		-DUSE_DTV=OFF \
		-DDISABLE_SERVER=OFF \
		-DCMAKE_FIND_ROOT_PATH="$ROOTFS_TEMP;$BUILD/android-liblog-amlogic-yocto-1.0;$BUILD/aml-audio-utils-amlogic-yocto-1.0;$AVSYNC_BUILD/src;$AVSYNC_BUILD" \
		-DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
		-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH \
		-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
		-DCMAKE_PREFIX_PATH="$CMAKE_PREFIX_PATH" \
		|| {
			error_msg "CMake configuration failed"
			return 1
		}
	
	# Build
	info_msg "Building ${PKG_NAME}..."
	make -j$(nproc) || {
		error_msg "Build failed"
		return 1
	}
	
	# Install to package directory
	# CMake installs to CMAKE_INSTALL_PREFIX which we set to /usr
	# Use DESTDIR to redirect to pkgdir
	make install DESTDIR="$pkgdir" || {
		error_msg "Install failed"
		return 1
	}
	
	# Install configuration files
	if [ -f "$PKGS_DIR/${PKG_NAME}/files/${AUDIO_CONFIG}" ]; then
		install -m 755 "$PKGS_DIR/${PKG_NAME}/files/${AUDIO_CONFIG}" "${pkgdir}/etc/halaudio/aml_audio_config.json"
	else
		warning_msg "Audio config file ${AUDIO_CONFIG} not found, using default"
		if [ -f "$PKGS_DIR/${PKG_NAME}/files/aml_audio_config.json" ]; then
			install -m 755 "$PKGS_DIR/${PKG_NAME}/files/aml_audio_config.json" "${pkgdir}/etc/halaudio/"
		fi
	fi
	
	if [ -f "$PKGS_DIR/${PKG_NAME}/files/${MIXER_CONFIG}" ]; then
		install -m 644 "$PKGS_DIR/${PKG_NAME}/files/${MIXER_CONFIG}" "${pkgdir}/etc/mixer_paths.xml"
	else
		warning_msg "Mixer config file ${MIXER_CONFIG} not found, using default"
		if [ -f "$PKGS_DIR/${PKG_NAME}/files/mixer_paths.xml" ]; then
			install -m 644 "$PKGS_DIR/${PKG_NAME}/files/mixer_paths.xml" "${pkgdir}/etc/"
		fi
	fi
	
	if [ -f "$PKGS_DIR/${PKG_NAME}/files/${AVSYNC_CONFIG}" ]; then
		install -m 755 "$PKGS_DIR/${PKG_NAME}/files/${AVSYNC_CONFIG}" "${pkgdir}/etc/halaudio/audio_hal_delay_base.json"
	else
		warning_msg "AV sync config file ${AVSYNC_CONFIG} not found, using default"
		if [ -f "$PKGS_DIR/${PKG_NAME}/files/audio_hal_delay_base.json" ]; then
			install -m 755 "$PKGS_DIR/${PKG_NAME}/files/audio_hal_delay_base.json" "${pkgdir}/etc/halaudio/"
		fi
	fi
	
	# Install ms12_audio_profiles.ini if available
	if [ -f "$PKGS_DIR/${PKG_NAME}/files/ms12_audio_profiles.ini" ]; then
		install -m 644 "$PKGS_DIR/${PKG_NAME}/files/ms12_audio_profiles.ini" "${pkgdir}/etc/halaudio/"
	fi
	
	# Install headers
	if [ -d "$PKG_BUILD_DIR/include/hardware" ]; then
		for f in "$PKG_BUILD_DIR/include/hardware"/*.h; do
			if [ -f "$f" ]; then
				install -m 644 "$f" "${pkgdir}/usr/include/hardware/"
			fi
		done
	fi
	
	if [ -d "$PKG_BUILD_DIR/include/system" ]; then
		for f in "$PKG_BUILD_DIR/include/system"/*.h; do
			if [ -f "$f" ]; then
				install -m 644 "$f" "${pkgdir}/usr/include/system/"
			fi
		done
	fi
	
	# Install Virtualx_v4.h if available
	if [ -f "$PKG_BUILD_DIR/include/Virtualx_v4.h" ]; then
		install -m 644 "$PKG_BUILD_DIR/include/Virtualx_v4.h" "${pkgdir}/usr/include/"
	fi
	
	# Strip binaries and libraries
	find "${pkgdir}/usr/lib" -type f -name "*.so*" -exec ${STRIP} {} \; 2>/dev/null || true
	find "${pkgdir}/usr/bin" -type f -executable -exec ${STRIP} {} \; 2>/dev/null || true
	
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

