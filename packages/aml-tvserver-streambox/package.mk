# Helper function to set fixed cross-compiler path for ARM64 (VIM4 board only)
detect_cross_compiler() {
	# Fixed toolchain paths for ARM64 - prioritize GCC 12.2 to match aml-audio-service
	# This avoids GLIBC version mismatches with libaudio_client.so
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

PKG_NAME="aml-tvserver-streambox"
PKG_VERSION="47b7823c2af14338e873c5ceb8fd2a9c4f277af2"
PKG_SHA256=""
PKG_SOURCE_DIR="aml_tvserver_streambox-${PKG_VERSION}*"
PKG_SITE="https://github.com/anshi233/aml_tvserver_streambox"
PKG_URL="$PKG_SITE/archive/$PKG_VERSION.tar.gz"
PKG_ARCH="arm aarch64"
PKG_LICENSE="Proprietary"
PKG_SHORTDESC="Amlogic TV Server Stream Box"
PKG_SOURCE_NAME="aml_tvserver_streambox-${PKG_VERSION}.tar.gz"
PKG_NEED_BUILD="YES"

# Verify tvconfig files exist in packages folder and extract package
# Files must be pre-copied to packages/aml-tvserver-streambox/sources/tvconfig/
unpack() {
	local TVCONFIG_DEST="$PKGS_DIR/$PKG_NAME/sources/tvconfig"
	
	# Check if tvconfig files exist in packages folder
	if [ ! -d "$TVCONFIG_DEST" ] || [ -z "$(ls -A "$TVCONFIG_DEST" 2>/dev/null)" ]; then
		error_msg "tvconfig files not found in packages folder: $TVCONFIG_DEST"
		error_msg "Please copy tvconfig files from Yocto to the packages folder before building:"
		error_msg "  mkdir -p $TVCONFIG_DEST"
		error_msg "  cp -r <yocto_path>/aml-comp/prebuilt/vendor/etc/tvconfig/a311d2/* $TVCONFIG_DEST/"
		return 1
	fi
	
	info_msg "tvconfig files found in packages folder"
	
	# Extract the package (since we define unpack(), we need to handle extraction ourselves)
	if [ -n "$PKG_URL" ] && [ -n "$PKG_SOURCE_NAME" ]; then
		local DOWNLOAD_DIR="$DOWNLOAD_PKG_DIR/$PKG_NAME"
		local SOURCE_FILE="$DOWNLOAD_DIR/$PKG_SOURCE_NAME"
		
		if [ ! -f "$SOURCE_FILE" ]; then
			error_msg "Source file not found: $SOURCE_FILE"
			return 1
		fi
		
		info_msg "Extracting $PKG_SOURCE_NAME to $BUILD..."
		
		# Extract based on file extension
		case "$PKG_SOURCE_NAME" in
			*.tar.gz|*.tgz)
				tar -xzf "$SOURCE_FILE" -C "$BUILD" || {
					error_msg "Failed to extract $PKG_SOURCE_NAME"
					return 1
				}
				;;
			*.tar.xz|*.txz)
				tar -xJf "$SOURCE_FILE" -C "$BUILD" || {
					error_msg "Failed to extract $PKG_SOURCE_NAME"
					return 1
				}
				;;
			*.tar.bz2|*.tbz)
				tar -xjf "$SOURCE_FILE" -C "$BUILD" || {
					error_msg "Failed to extract $PKG_SOURCE_NAME"
					return 1
				}
				;;
			*)
				error_msg "Unknown archive format: $PKG_SOURCE_NAME"
				return 1
				;;
		esac
		
		info_msg "Package extracted successfully"
	fi
	
	return 0
}

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
 Provides libtv.so, libtvclient.so, tvservice, and hdmiin-demo.
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
	mkdir -p "$STAGING_DIR/usr/include/binder"
	mkdir -p "$STAGING_DIR/usr/include/utils"
	mkdir -p "$STAGING_DIR/usr/include/linux/amlogic"
	
	# Copy binder headers (needed for binder/IPCThreadState.h, etc.)
	local BINDER_SRC="$PKGS_DIR/android-binder/sources/include/binder"
	if [ -d "$BINDER_SRC" ]; then
		cp -r "$BINDER_SRC"/* "$STAGING_DIR/usr/include/binder/" 2>/dev/null || true
		info_msg "Copied binder headers from android-binder sources"
	fi
	# Also check build directory
	local BINDER_BUILD="$BUILD/android-binder-amlogic-yocto-1.0"
	if [ ! -d "$BINDER_BUILD" ]; then
		BINDER_BUILD="$BUILD/android-binder-${PKG_VERSION}"
	fi
	if [ -d "$BINDER_BUILD/include/binder" ]; then
		cp -r "$BINDER_BUILD/include/binder"/* "$STAGING_DIR/usr/include/binder/" 2>/dev/null || true
		info_msg "Copied binder headers from android-binder build directory"
	fi
	
	# Copy utils headers (needed by binder headers)
	local UTILS_SRC="$PKGS_DIR/android-binder/sources/include/utils"
	if [ -d "$UTILS_SRC" ]; then
		cp -r "$UTILS_SRC"/* "$STAGING_DIR/usr/include/utils/" 2>/dev/null || true
		info_msg "Copied utils headers from android-binder sources"
	fi
	if [ -d "$BINDER_BUILD/include/utils" ]; then
		cp -r "$BINDER_BUILD/include/utils"/* "$STAGING_DIR/usr/include/utils/" 2>/dev/null || true
		info_msg "Copied utils headers from android-binder build directory"
	fi
	
	# Copy cutils headers (needed for cutils/native_handle.h, cutils/log.h, etc.)
	local CUTILS_SRC="$PKGS_DIR/android-binder/sources/include/cutils"
	if [ -d "$CUTILS_SRC" ]; then
		cp -r "$CUTILS_SRC"/* "$STAGING_DIR/usr/include/cutils/" 2>/dev/null || true
		info_msg "Copied cutils headers from android-binder sources"
	fi
	# Also check android-liblog for cutils headers
	local CUTILS_SRC2="$PKGS_DIR/android-liblog/sources/include/cutils"
	if [ -d "$CUTILS_SRC2" ]; then
		cp -r "$CUTILS_SRC2"/* "$STAGING_DIR/usr/include/cutils/" 2>/dev/null || true
		info_msg "Copied cutils headers from android-liblog sources"
	fi
	if [ -d "$BINDER_BUILD/include/cutils" ]; then
		cp -r "$BINDER_BUILD/include/cutils"/* "$STAGING_DIR/usr/include/cutils/" 2>/dev/null || true
		info_msg "Copied cutils headers from android-binder build directory"
	fi
	
	# Copy kernel headers (needed for linux/amlogic/tvin.h)
	# Note: Kernel headers are in include/uapi/amlogic/ not include/uapi/linux/amlogic/
	local KERNEL_TVIN_H=""
	if [ -f "$BUILD/linux/common_drivers/include/uapi/amlogic/tvin.h" ]; then
		KERNEL_TVIN_H="$BUILD/linux/common_drivers/include/uapi/amlogic/tvin.h"
	elif [ -f "$BUILD/linux/common_drivers/include/linux/amlogic/media/frame_provider/tvin/tvin.h" ]; then
		KERNEL_TVIN_H="$BUILD/linux/common_drivers/include/linux/amlogic/media/frame_provider/tvin/tvin.h"
	elif [ -f "$BUILD/linux/include/uapi/amlogic/tvin.h" ]; then
		KERNEL_TVIN_H="$BUILD/linux/include/uapi/amlogic/tvin.h"
	fi
	
	# Copy all amlogic kernel headers if directory exists
	local KERNEL_AMLOGIC_DIR=""
	if [ -d "$BUILD/linux/common_drivers/include/uapi/amlogic" ]; then
		KERNEL_AMLOGIC_DIR="$BUILD/linux/common_drivers/include/uapi/amlogic"
	elif [ -d "$BUILD/linux/include/uapi/amlogic" ]; then
		KERNEL_AMLOGIC_DIR="$BUILD/linux/include/uapi/amlogic"
	fi
	
	# Copy hardware/audio.h and system/audio.h from aml-audio-hal
	local AUDIO_HAL_SRC="$PKGS_DIR/aml-audio-hal/sources/include"
	if [ -d "$AUDIO_HAL_SRC/hardware" ]; then
		cp -r "$AUDIO_HAL_SRC/hardware"/* "$STAGING_DIR/usr/include/hardware/" 2>/dev/null || true
		info_msg "Copied hardware headers from aml-audio-hal sources"
	fi
	if [ -d "$AUDIO_HAL_SRC/system" ]; then
		cp -r "$AUDIO_HAL_SRC/system"/* "$STAGING_DIR/usr/include/system/" 2>/dev/null || true
		info_msg "Copied system headers from aml-audio-hal sources"
	fi
	local AUDIO_HAL_BUILD="$BUILD/aml-audio-hal-amlogic-yocto-1.0"
	if [ ! -d "$AUDIO_HAL_BUILD" ]; then
		AUDIO_HAL_BUILD="$BUILD/aml-audio-hal-${PKG_VERSION}"
	fi
	if [ -d "$AUDIO_HAL_BUILD/include/hardware" ]; then
		cp -r "$AUDIO_HAL_BUILD/include/hardware"/* "$STAGING_DIR/usr/include/hardware/" 2>/dev/null || true
		info_msg "Copied hardware headers from aml-audio-hal build directory"
	fi
	if [ -d "$AUDIO_HAL_BUILD/include/system" ]; then
		cp -r "$AUDIO_HAL_BUILD/include/system"/* "$STAGING_DIR/usr/include/system/" 2>/dev/null || true
		info_msg "Copied system headers from aml-audio-hal build directory"
	fi
	
	# Copy ubootenv.h from ported package (copied from Yocto)
	# ubootenv.h is ported from Yocto aml-ubootenv package
	local UBOOTENV_H_SRC="$PKGS_DIR/aml-ubootenv-dev/sources/include/ubootenv.h"
	if [ -f "$UBOOTENV_H_SRC" ]; then
		cp "$UBOOTENV_H_SRC" "$STAGING_DIR/usr/include/" 2>/dev/null || true
		info_msg "Copied ubootenv.h from ported aml-ubootenv-dev package"
	else
		warning_msg "ubootenv.h not found in packages/aml-ubootenv-dev/sources/include/"
		warning_msg "Please copy ubootenv.h from Yocto: cp ~/yocto/build/tmp/work/armv8a-poky-linux/aml-ubootenv/999-r0/packages-split/aml-ubootenv-dev/usr/include/ubootenv.h packages/aml-ubootenv-dev/sources/include/"
	fi
	
	if [ -n "$KERNEL_AMLOGIC_DIR" ] && [ -d "$KERNEL_AMLOGIC_DIR" ]; then
		mkdir -p "$STAGING_DIR/usr/include/linux/amlogic"
		cp "$KERNEL_AMLOGIC_DIR"/*.h "$STAGING_DIR/usr/include/linux/amlogic/" 2>/dev/null || true
		info_msg "Copied all kernel headers from: $KERNEL_AMLOGIC_DIR"
	elif [ -n "$KERNEL_TVIN_H" ] && [ -f "$KERNEL_TVIN_H" ]; then
		mkdir -p "$STAGING_DIR/usr/include/linux/amlogic"
		cp "$KERNEL_TVIN_H" "$STAGING_DIR/usr/include/linux/amlogic/tvin.h" 2>/dev/null || true
		info_msg "Copied kernel header tvin.h from: $KERNEL_TVIN_H"
		# Also try to copy amvecm_ext.h if it exists in the same directory
		local AMVECM_H=$(dirname "$KERNEL_TVIN_H")/amvecm_ext.h
		if [ -f "$AMVECM_H" ]; then
			cp "$AMVECM_H" "$STAGING_DIR/usr/include/linux/amlogic/amvecm_ext.h" 2>/dev/null || true
			info_msg "Copied kernel header amvecm_ext.h"
		fi
	else
		warning_msg "Kernel header tvin.h not found - build may fail"
		warning_msg "Searched in:"
		warning_msg "  - $BUILD/linux/common_drivers/include/uapi/amlogic/tvin.h"
		warning_msg "  - $BUILD/linux/common_drivers/include/linux/amlogic/media/frame_provider/tvin/tvin.h"
		warning_msg "  - $BUILD/linux/include/uapi/amlogic/tvin.h"
	fi
	
	# Get dependency libraries for linking
	# android-binder (libbinder.so, liblog.so)
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
	elif [ -f "$LIBLOG_BUILD/liblog.so.1.0.0" ]; then
		cp "$LIBLOG_BUILD/liblog.so.1.0.0" "$STAGING_DIR/usr/lib/liblog.so" 2>/dev/null || true
	fi
	
	# aml-audio-service (libaudio_client.so)
	local AUDIO_SERVICE_BUILD="$BUILD/aml-audio-service-amlogic-yocto-1.0"
	if [ ! -d "$AUDIO_SERVICE_BUILD" ]; then
		AUDIO_SERVICE_BUILD="$BUILD/aml-audio-service-${PKG_VERSION}"
	fi
	if [ -f "$AUDIO_SERVICE_BUILD/libaudio_client.so" ]; then
		cp "$AUDIO_SERVICE_BUILD/libaudio_client.so" "$STAGING_DIR/usr/lib/" 2>/dev/null || true
	fi
	
	# aml-audio-utils (libamaudioutils.so - needed by libaudio_client.so)
	local AUDIO_UTILS_BUILD="$BUILD/aml-audio-utils-amlogic-yocto-1.0"
	if [ ! -d "$AUDIO_UTILS_BUILD" ]; then
		AUDIO_UTILS_BUILD="$BUILD/aml-audio-utils-${PKG_VERSION}"
	fi
	if [ -f "$AUDIO_UTILS_BUILD/libamaudioutils.so" ]; then
		cp "$AUDIO_UTILS_BUILD/libamaudioutils.so" "$STAGING_DIR/usr/lib/" 2>/dev/null || true
		info_msg "Copied libamaudioutils.so from aml-audio-utils build"
	fi
	
	# libubootenv.so (needed for bootenv functions)
	local UBOOTENV_LIB="$PKGS_DIR/aml-ubootenv-dev/sources/lib/libubootenv.so"
	if [ -f "$UBOOTENV_LIB" ]; then
		cp "$UBOOTENV_LIB" "$STAGING_DIR/usr/lib/" 2>/dev/null || true
		info_msg "Copied libubootenv.so from ported package"
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
	
	# Add include paths to Makefile CFLAGS/CXXFLAGS for binder, cutils, utils, and kernel headers
	# Check if CFLAGS already has the staging include path
	if ! grep -q "STAGING_DIR.*include" "$PKG_BUILD_DIR/Makefile" 2>/dev/null; then
		if grep -q "^CFLAGS" "$PKG_BUILD_DIR/Makefile" 2>/dev/null; then
			sed -i "s|^CFLAGS +=|CFLAGS += -I$STAGING_DIR/usr/include |" "$PKG_BUILD_DIR/Makefile"
			info_msg "Added staging include path to CFLAGS"
		fi
		if grep -q "^CXXFLAGS" "$PKG_BUILD_DIR/Makefile" 2>/dev/null; then
			sed -i "s|^CXXFLAGS +=|CXXFLAGS += -I$STAGING_DIR/usr/include |" "$PKG_BUILD_DIR/Makefile"
			info_msg "Added staging include path to CXXFLAGS"
		fi
	fi
	
	# Add library path to LDFLAGS
	if ! grep -q "STAGING_DIR.*lib" "$PKG_BUILD_DIR/Makefile" 2>/dev/null; then
		if grep -q "^LDFLAGS" "$PKG_BUILD_DIR/Makefile" 2>/dev/null; then
			sed -i "s|^LDFLAGS +=|LDFLAGS += -L$STAGING_DIR/usr/lib |" "$PKG_BUILD_DIR/Makefile"
			info_msg "Added staging library path to LDFLAGS"
		fi
	fi
	
	# Add -lubootenv and -lamaudioutils to LDLIBS if libraries exist
	# The Makefile uses $(LDLIBS) variable in the link commands
	# Check if LDLIBS is defined, if not, add it after LDFLAGS definitions
	if [ -f "$STAGING_DIR/usr/lib/libubootenv.so" ] || [ -f "$STAGING_DIR/usr/lib/libamaudioutils.so" ]; then
		if ! grep -q "^LDLIBS" "$PKG_BUILD_DIR/Makefile" 2>/dev/null; then
			# Add LDLIBS definition after LDFLAGS
			local LDFLAGS_LINE=$(grep -n "^LDFLAGS" "$PKG_BUILD_DIR/Makefile" 2>/dev/null | tail -1 | cut -d: -f1)
			if [ -n "$LDFLAGS_LINE" ]; then
				sed -i "${LDFLAGS_LINE}a LDLIBS :=" "$PKG_BUILD_DIR/Makefile"
				info_msg "Added LDLIBS definition to Makefile"
			else
				# Add at the beginning if no LDFLAGS found
				sed -i "1i LDLIBS :=" "$PKG_BUILD_DIR/Makefile"
				info_msg "Added LDLIBS definition at beginning of Makefile"
			fi
		fi
		
		# Add libraries to LDLIBS
		if [ -f "$STAGING_DIR/usr/lib/libubootenv.so" ] && ! grep -q "\-lubootenv" "$PKG_BUILD_DIR/Makefile" 2>/dev/null; then
			# Add to existing LDLIBS line or create new one
			if grep -q "^LDLIBS[[:space:]]*+=" "$PKG_BUILD_DIR/Makefile" 2>/dev/null; then
				sed -i "/^LDLIBS[[:space:]]*+=/a LDLIBS += -lubootenv" "$PKG_BUILD_DIR/Makefile"
			elif grep -q "^LDLIBS[[:space:]]*:=" "$PKG_BUILD_DIR/Makefile" 2>/dev/null; then
				sed -i "s|^LDLIBS[[:space:]]*:=.*|& -lubootenv|" "$PKG_BUILD_DIR/Makefile"
			else
				echo "LDLIBS += -lubootenv" >> "$PKG_BUILD_DIR/Makefile"
			fi
			info_msg "Added -lubootenv to LDLIBS"
		fi
		if [ -f "$STAGING_DIR/usr/lib/libamaudioutils.so" ] && ! grep -q "\-lamaudioutils" "$PKG_BUILD_DIR/Makefile" 2>/dev/null; then
			if grep -q "^LDLIBS[[:space:]]*+=" "$PKG_BUILD_DIR/Makefile" 2>/dev/null; then
				sed -i "/^LDLIBS[[:space:]]*+=/a LDLIBS += -lamaudioutils" "$PKG_BUILD_DIR/Makefile"
			elif grep -q "^LDLIBS[[:space:]]*:=" "$PKG_BUILD_DIR/Makefile" 2>/dev/null; then
				sed -i "s|^LDLIBS[[:space:]]*:=.*|& -lamaudioutils|" "$PKG_BUILD_DIR/Makefile"
			else
				echo "LDLIBS += -lamaudioutils" >> "$PKG_BUILD_DIR/Makefile"
			fi
			info_msg "Added -lamaudioutils to LDLIBS"
		fi
	fi
	
	# Remove -lz and -lubootenv from all LDFLAGS lines (system libraries, available at runtime)
	sed -i '/^LDFLAGS/ s/\s*-lz\s*/ /g; /^LDFLAGS/ s/\s*-lubootenv\s*/ /g; /^LDFLAGS/ s/  \+/ /g' "$PKG_BUILD_DIR/Makefile" 2>/dev/null || true
	info_msg "Removed -lz and -lubootenv from LDFLAGS (system libraries, available at runtime)"
	
	# Add include paths to Makefile CFLAGS/CXXFLAGS for binder, cutils, utils, and kernel headers
	if grep -q "^CFLAGS" "$PKG_BUILD_DIR/Makefile" 2>/dev/null; then
		sed -i "s|^CFLAGS +=|CFLAGS += -I$STAGING_DIR/usr/include |" "$PKG_BUILD_DIR/Makefile"
		info_msg "Added staging include path to CFLAGS"
	fi
	if grep -q "^CXXFLAGS" "$PKG_BUILD_DIR/Makefile" 2>/dev/null; then
		sed -i "s|^CXXFLAGS +=|CXXFLAGS += -I$STAGING_DIR/usr/include |" "$PKG_BUILD_DIR/Makefile"
		info_msg "Added staging include path to CXXFLAGS"
	fi
	
	# Add library path to LDFLAGS
	if grep -q "^LDFLAGS" "$PKG_BUILD_DIR/Makefile" 2>/dev/null; then
		sed -i "s|^LDFLAGS +=|LDFLAGS += -L$STAGING_DIR/usr/lib |" "$PKG_BUILD_DIR/Makefile"
		info_msg "Added staging library path to LDFLAGS"
	fi
	
	# Build
	info_msg "Building ${PKG_NAME}..."
	make clean 2>/dev/null || true
	
	# Re-create staging directory and copy headers after clean (clean may have removed them)
	mkdir -p "$STAGING_DIR/usr/lib"
	mkdir -p "$STAGING_DIR/usr/include/binder"
	mkdir -p "$STAGING_DIR/usr/include/utils"
	mkdir -p "$STAGING_DIR/usr/include/cutils"
	mkdir -p "$STAGING_DIR/usr/include/linux/amlogic"
	mkdir -p "$STAGING_DIR/usr/include/hardware"
	mkdir -p "$STAGING_DIR/usr/include/system"
	
	# Copy audio_if.h from aml-audio-service
	local AUDIO_IF_H="$PKGS_DIR/aml-audio-service/sources/include/audio_if.h"
	if [ -f "$AUDIO_IF_H" ]; then
		cp "$AUDIO_IF_H" "$STAGING_DIR/usr/include/" 2>/dev/null || true
		info_msg "Copied audio_if.h from aml-audio-service"
	fi
	local AUDIO_IF_H2="$PKGS_DIR/aml-audio-service/sources/include/audio_if_client.h"
	if [ -f "$AUDIO_IF_H2" ]; then
		cp "$AUDIO_IF_H2" "$STAGING_DIR/usr/include/" 2>/dev/null || true
		info_msg "Copied audio_if_client.h from aml-audio-service"
	fi
	
	# Re-copy headers after clean
	if [ -d "$BINDER_SRC" ]; then
		cp -r "$BINDER_SRC"/* "$STAGING_DIR/usr/include/binder/" 2>/dev/null || true
	fi
	if [ -d "$BINDER_BUILD/include/binder" ]; then
		cp -r "$BINDER_BUILD/include/binder"/* "$STAGING_DIR/usr/include/binder/" 2>/dev/null || true
	fi
	if [ -d "$UTILS_SRC" ]; then
		cp -r "$UTILS_SRC"/* "$STAGING_DIR/usr/include/utils/" 2>/dev/null || true
	fi
	if [ -d "$BINDER_BUILD/include/utils" ]; then
		cp -r "$BINDER_BUILD/include/utils"/* "$STAGING_DIR/usr/include/utils/" 2>/dev/null || true
	fi
	if [ -d "$CUTILS_SRC" ]; then
		cp -r "$CUTILS_SRC"/* "$STAGING_DIR/usr/include/cutils/" 2>/dev/null || true
	fi
	if [ -d "$CUTILS_SRC2" ]; then
		cp -r "$CUTILS_SRC2"/* "$STAGING_DIR/usr/include/cutils/" 2>/dev/null || true
	fi
	if [ -d "$BINDER_BUILD/include/cutils" ]; then
		cp -r "$BINDER_BUILD/include/cutils"/* "$STAGING_DIR/usr/include/cutils/" 2>/dev/null || true
	fi
	if [ -n "$KERNEL_AMLOGIC_DIR" ] && [ -d "$KERNEL_AMLOGIC_DIR" ]; then
		mkdir -p "$STAGING_DIR/usr/include/linux/amlogic"
		cp "$KERNEL_AMLOGIC_DIR"/*.h "$STAGING_DIR/usr/include/linux/amlogic/" 2>/dev/null || true
	fi
	# Re-copy hardware and system headers after clean
	local AUDIO_HAL_SRC="$PKGS_DIR/aml-audio-hal/sources/include"
	local AUDIO_HAL_BUILD="$BUILD/aml-audio-hal-amlogic-yocto-1.0"
	if [ ! -d "$AUDIO_HAL_BUILD" ]; then
		AUDIO_HAL_BUILD="$BUILD/aml-audio-hal-${PKG_VERSION}"
	fi
	if [ -d "$AUDIO_HAL_SRC/hardware" ]; then
		cp -r "$AUDIO_HAL_SRC/hardware"/* "$STAGING_DIR/usr/include/hardware/" 2>/dev/null || true
		info_msg "Re-copied hardware headers from aml-audio-hal sources"
	fi
	if [ -d "$AUDIO_HAL_SRC/system" ]; then
		cp -r "$AUDIO_HAL_SRC/system"/* "$STAGING_DIR/usr/include/system/" 2>/dev/null || true
		info_msg "Re-copied system headers from aml-audio-hal sources"
	fi
	if [ -d "$AUDIO_HAL_BUILD/include/hardware" ]; then
		cp -r "$AUDIO_HAL_BUILD/include/hardware"/* "$STAGING_DIR/usr/include/hardware/" 2>/dev/null || true
		info_msg "Re-copied hardware headers from aml-audio-hal build directory"
	fi
	if [ -d "$AUDIO_HAL_BUILD/include/system" ]; then
		cp -r "$AUDIO_HAL_BUILD/include/system"/* "$STAGING_DIR/usr/include/system/" 2>/dev/null || true
		info_msg "Re-copied system headers from aml-audio-hal build directory"
	fi
	# Re-copy ubootenv.h after clean using direct paths
	local UBOOTENV_H=""
	# Check known locations (same as above)
	if [ -f "$BUILD/linux/debian/headertmp/usr/include/ubootenv.h" ]; then
		UBOOTENV_H="$BUILD/linux/debian/headertmp/usr/include/ubootenv.h"
	elif [ -f "$BUILD/linux/common_drivers/include/uapi/amlogic/ubootenv.h" ]; then
		UBOOTENV_H="$BUILD/linux/common_drivers/include/uapi/amlogic/ubootenv.h"
	elif [ -f "$BUILD/linux/include/uapi/amlogic/ubootenv.h" ]; then
		UBOOTENV_H="$BUILD/linux/include/uapi/amlogic/ubootenv.h"
	fi
	
	# Re-copy ubootenv.h after clean from ported package
	local UBOOTENV_H_SRC="$PKGS_DIR/aml-ubootenv-dev/sources/include/ubootenv.h"
	if [ -f "$UBOOTENV_H_SRC" ]; then
		cp "$UBOOTENV_H_SRC" "$STAGING_DIR/usr/include/" 2>/dev/null || true
		info_msg "Re-copied ubootenv.h from ported aml-ubootenv-dev package"
	fi
	
	# Re-copy audio_if.h after clean
	if [ -f "$AUDIO_IF_H" ]; then
		cp "$AUDIO_IF_H" "$STAGING_DIR/usr/include/" 2>/dev/null || true
	fi
	if [ -f "$AUDIO_IF_H2" ]; then
		cp "$AUDIO_IF_H2" "$STAGING_DIR/usr/include/" 2>/dev/null || true
	fi
	
	# Re-copy libraries
	if [ -f "$BINDER_BUILD/libbinder.so" ]; then
		cp "$BINDER_BUILD/libbinder.so" "$STAGING_DIR/usr/lib/" 2>/dev/null || true
	fi
	if [ -f "$LIBLOG_BUILD/liblog.so" ]; then
		cp "$LIBLOG_BUILD/liblog.so" "$STAGING_DIR/usr/lib/" 2>/dev/null || true
	elif [ -f "$LIBLOG_BUILD/liblog.so.1.0.0" ]; then
		cp "$LIBLOG_BUILD/liblog.so.1.0.0" "$STAGING_DIR/usr/lib/liblog.so" 2>/dev/null || true
	fi
	if [ -f "$AUDIO_SERVICE_BUILD/libaudio_client.so" ]; then
		cp "$AUDIO_SERVICE_BUILD/libaudio_client.so" "$STAGING_DIR/usr/lib/" 2>/dev/null || true
	fi
	
	# Re-copy libamaudioutils.so and libubootenv.so after clean
	local AUDIO_UTILS_BUILD="$BUILD/aml-audio-utils-amlogic-yocto-1.0"
	if [ ! -d "$AUDIO_UTILS_BUILD" ]; then
		AUDIO_UTILS_BUILD="$BUILD/aml-audio-utils-${PKG_VERSION}"
	fi
	if [ -f "$AUDIO_UTILS_BUILD/libamaudioutils.so" ]; then
		cp "$AUDIO_UTILS_BUILD/libamaudioutils.so" "$STAGING_DIR/usr/lib/" 2>/dev/null || true
		info_msg "Re-copied libamaudioutils.so"
	fi
	local UBOOTENV_LIB="$PKGS_DIR/aml-ubootenv-dev/sources/lib/libubootenv.so"
	if [ -f "$UBOOTENV_LIB" ]; then
		cp "$UBOOTENV_LIB" "$STAGING_DIR/usr/lib/" 2>/dev/null || true
		info_msg "Re-copied libubootenv.so"
	fi
	
	# Remove -lz from LDFLAGS (system library, available at runtime)
	# Only process Makefile, skip tvserver.mk to avoid potential issues
	if [ -f "$PKG_BUILD_DIR/Makefile" ]; then
		# Use head to limit file size check for grep (prevent hanging on huge files)
		if head -n 1000 "$PKG_BUILD_DIR/Makefile" 2>/dev/null | grep -q "-lz"; then
			# Use sed instead of perl for better compatibility
			sed -i 's/\s*-lz\s*/ /g; s/\s*-lz$//g; s/-lz\s*//g' "$PKG_BUILD_DIR/Makefile" 2>/dev/null || true
			sed -i 's/  \+/ /g' "$PKG_BUILD_DIR/Makefile" 2>/dev/null || true
			info_msg "Removed -lz from Makefile (system library, available at runtime)"
		fi
		# Keep -lubootenv since we have libubootenv.so in staging
		# Only remove if library doesn't exist
		if [ ! -f "$STAGING_DIR/usr/lib/libubootenv.so" ] && head -n 1000 "$PKG_BUILD_DIR/Makefile" 2>/dev/null | grep -q "-lubootenv"; then
			sed -i 's/\s*-lubootenv\s*/ /g; s/\s*-lubootenv$//g; s/-lubootenv\s*//g' "$PKG_BUILD_DIR/Makefile" 2>/dev/null || true
			sed -i 's/  \+/ /g' "$PKG_BUILD_DIR/Makefile" 2>/dev/null || true
			info_msg "Removed -lubootenv from Makefile (library not available)"
		fi
	fi
	
	# Ensure -lubootenv and -lamaudioutils are in LDLIBS before building
	# This must be done after all library copying and Makefile modifications
	# Use head to limit file size check (prevent hanging on huge files)
	if [ -f "$STAGING_DIR/usr/lib/libubootenv.so" ]; then
		# Check if -lubootenv is already in any LDLIBS line
		if ! head -n 1000 "$PKG_BUILD_DIR/Makefile" 2>/dev/null | grep -q "\-lubootenv"; then
			# Find existing LDLIBS line and append to it, or create new one
			# Handle both := and += assignments
			if head -n 1000 "$PKG_BUILD_DIR/Makefile" 2>/dev/null | grep -q "^LDLIBS"; then
				# Append to existing LDLIBS line (find first occurrence and add to it)
				local LDLIBS_LINE=$(grep -n "^LDLIBS" "$PKG_BUILD_DIR/Makefile" 2>/dev/null | head -1 | cut -d: -f1)
				if [ -n "$LDLIBS_LINE" ]; then
					# Append -lubootenv to the end of the line
					sed -i "${LDLIBS_LINE}s|\$| -lubootenv|" "$PKG_BUILD_DIR/Makefile" 2>/dev/null || \
					echo "LDLIBS += -lubootenv" >> "$PKG_BUILD_DIR/Makefile"
				else
					echo "LDLIBS += -lubootenv" >> "$PKG_BUILD_DIR/Makefile"
				fi
				info_msg "Added -lubootenv to LDLIBS before build"
			else
				echo "LDLIBS += -lubootenv" >> "$PKG_BUILD_DIR/Makefile"
				info_msg "Added LDLIBS with -lubootenv before build"
			fi
		fi
	fi
	if [ -f "$STAGING_DIR/usr/lib/libamaudioutils.so" ]; then
		if ! head -n 1000 "$PKG_BUILD_DIR/Makefile" 2>/dev/null | grep -q "\-lamaudioutils"; then
			if head -n 1000 "$PKG_BUILD_DIR/Makefile" 2>/dev/null | grep -q "^LDLIBS"; then
				local LDLIBS_LINE=$(grep -n "^LDLIBS" "$PKG_BUILD_DIR/Makefile" 2>/dev/null | head -1 | cut -d: -f1)
				if [ -n "$LDLIBS_LINE" ]; then
					sed -i "${LDLIBS_LINE}s|\$| -lamaudioutils|" "$PKG_BUILD_DIR/Makefile" 2>/dev/null || \
					echo "LDLIBS += -lamaudioutils" >> "$PKG_BUILD_DIR/Makefile"
				else
					echo "LDLIBS += -lamaudioutils" >> "$PKG_BUILD_DIR/Makefile"
				fi
				info_msg "Added -lamaudioutils to LDLIBS before build"
			else
				echo "LDLIBS += -lamaudioutils" >> "$PKG_BUILD_DIR/Makefile"
				info_msg "Added -lamaudioutils to LDLIBS before build"
			fi
		fi
	fi
	
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
	if [ ! -f "$OUT_DIR/hdmiin-demo" ]; then
		error_msg "hdmiin-demo not found after build"
		BUILD_FAILED=1
	fi
	# tvtest is optional (not in BUILD_TARGETS by default)
	if [ ! -f "$OUT_DIR/tvtest" ]; then
		warning_msg "tvtest not found after build (optional, not in BUILD_TARGETS)"
	fi
	
	if [ "$BUILD_FAILED" = 1 ]; then
		error_msg "Build verification failed - some targets are missing"
		return 1
	fi
	
	# Manually install built binaries and libraries to package directory
	# (More reliable than relying on make install which may not use TARGET_DIR correctly)
	info_msg "Installing built binaries and libraries to package directory..."
	
	if [ -f "$OUT_DIR/libtv.so" ]; then
		install -m 755 -D "$OUT_DIR/libtv.so" "$pkgdir/usr/lib/libtv.so" || {
			error_msg "Failed to install libtv.so"
			return 1
		}
		info_msg "Installed libtv.so"
	else
		error_msg "libtv.so not found in $OUT_DIR"
		return 1
	fi
	
	if [ -f "$OUT_DIR/libtvclient.so" ]; then
		install -m 755 -D "$OUT_DIR/libtvclient.so" "$pkgdir/usr/lib/libtvclient.so" || {
			error_msg "Failed to install libtvclient.so"
			return 1
		}
		info_msg "Installed libtvclient.so"
	else
		error_msg "libtvclient.so not found in $OUT_DIR"
		return 1
	fi
	
	if [ -f "$OUT_DIR/tvservice" ]; then
		install -m 755 -D "$OUT_DIR/tvservice" "$pkgdir/usr/bin/tvservice" || {
			error_msg "Failed to install tvservice"
			return 1
		}
		info_msg "Installed tvservice"
	else
		error_msg "tvservice not found in $OUT_DIR"
		return 1
	fi
	
	if [ -f "$OUT_DIR/hdmiin-demo" ]; then
		install -m 755 -D "$OUT_DIR/hdmiin-demo" "$pkgdir/usr/bin/hdmiin-demo" || {
			error_msg "Failed to install hdmiin-demo"
			return 1
		}
		info_msg "Installed hdmiin-demo"
	else
		error_msg "hdmiin-demo not found in $OUT_DIR"
		return 1
	fi
	
	# tvtest is not in BUILD_TARGETS, so it's not built - skip installation
	if [ -f "$OUT_DIR/tvtest" ]; then
		install -m 755 -D "$OUT_DIR/tvtest" "$pkgdir/usr/bin/tvtest" || {
			warning_msg "Failed to install tvtest (optional)"
		}
		info_msg "Installed tvtest (optional)"
	fi
	
	# Verify installation (tvtest is not built, so we don't check for it)
	if [ ! -f "$pkgdir/usr/lib/libtv.so" ] || [ ! -f "$pkgdir/usr/lib/libtvclient.so" ] || \
	   [ ! -f "$pkgdir/usr/bin/tvservice" ] || [ ! -f "$pkgdir/usr/bin/hdmiin-demo" ]; then
		error_msg "Installation verification failed - some files are missing in package directory"
		error_msg "Checking build outputs in $OUT_DIR:"
		ls -la "$OUT_DIR"/*.so "$OUT_DIR"/tvservice 2>/dev/null || true
		error_msg "Checking package directory $pkgdir:"
		find "$pkgdir" -type f 2>/dev/null | head -20 || true
		return 1
	fi
	
	# Install tvconfig files from Yocto sources to /etc/tvconfig/
	local TVCONFIG_SRC="$PKGS_DIR/$PKG_NAME/sources/tvconfig"
	if [ -d "$TVCONFIG_SRC" ]; then
		info_msg "Installing tvconfig files to /etc/tvconfig/..."
		mkdir -p "$pkgdir/etc/tvconfig"
		
		# Copy all tvconfig subdirectories and files
		# This includes PQ/, tvconfig/panel/, tvconfig/audio/, etc.
		cp -r "$TVCONFIG_SRC"/* "$pkgdir/etc/tvconfig/" || {
			error_msg "Failed to copy tvconfig files to package directory"
			return 1
		}
		info_msg "tvconfig files installed to $pkgdir/etc/tvconfig/"
	else
		warning_msg "tvconfig source directory not found: $TVCONFIG_SRC"
		warning_msg "tvconfig files will not be included in the package"
		warning_msg "Please ensure unpack() function has copied files from Yocto"
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
