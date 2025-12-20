# Helper function to set fixed cross-compiler path for ARM64 (VIM4 board only)
detect_cross_compiler() {
	# Fixed toolchain paths for ARM64 - try multiple compilers to find one that works
	# Prioritize newer GCC 12.2 for better C++17 support
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

PKG_NAME="aml-audio-service"
PKG_VERSION="1.0-amlogic-yocto"
PKG_SHA256=""
PKG_SOURCE_DIR=""
PKG_SITE=""
PKG_URL=""
PKG_ARCH="aarch64"
PKG_LICENSE="AMLOGIC"
PKG_SHORTDESC="Amlogic Audio Service daemon and client library"

PKG_NEED_BUILD="YES"

make_target() {
	local pkgdir="$BUILD_IMAGES/.tmp/${PKG_NAME}_${VERSION}_${DISTRIB_ARCH}"
	# Overwrite by recreating directory structure
	mkdir -p $pkgdir/DEBIAN
	mkdir -p $pkgdir/usr/lib
	mkdir -p $pkgdir/usr/bin
	mkdir -p $pkgdir/usr/include
	mkdir -p $pkgdir/lib/systemd/system

	# Set up control file
	cat <<-EOF > $pkgdir/DEBIAN/control
Package: ${PKG_NAME}
Version: ${VERSION}
Architecture: ${DISTRIB_ARCH}
Maintainer: Khadas <hello@khadas.com>
Depends: aml-audio-utils, android-binder, libboost-system1.83.0, libgrpc++1.51t64, libprotobuf32t64, libgrpc29t64, libabsl20220623t64
Section: libs
Priority: optional
Description: Amlogic Audio Service
 ${PKG_SHORTDESC}
 Provides audio_server daemon and libaudio_client.so library.
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
	
	# Create staging directory
	mkdir -p "$STAGING_DIR/usr/lib"
	mkdir -p "$STAGING_DIR/usr/include/hardware"
	mkdir -p "$STAGING_DIR/usr/include/system"
	mkdir -p "$STAGING_DIR/usr/include/binder"
	mkdir -p "$STAGING_DIR/usr/include/IpcBuffer"
	mkdir -p "$STAGING_DIR/usr/include/cutils"
	mkdir -p "$STAGING_DIR/usr/include/utils"
	
	# Copy hardware headers (needed for hardware/hardware.h, hardware/audio.h, hardware/audio_effect.h)
	local HAL_SRC="$PKGS_DIR/aml-audio-hal/sources/include/hardware"
	if [ -d "$HAL_SRC" ]; then
		cp -r "$HAL_SRC"/* "$STAGING_DIR/usr/include/hardware/" 2>/dev/null || true
		info_msg "Copied hardware headers from aml-audio-hal sources"
	fi
	
	# Copy system headers (needed for system/audio.h)
	local SYSTEM_SRC="$PKGS_DIR/aml-audio-hal/sources/include/system"
	if [ -d "$SYSTEM_SRC" ]; then
		cp -r "$SYSTEM_SRC"/* "$STAGING_DIR/usr/include/system/" 2>/dev/null || true
		info_msg "Copied system headers from aml-audio-hal sources"
	fi
	
	# Copy binder headers (needed for binder/*.h when use_binder=y)
	local BINDER_SRC="$PKGS_DIR/android-binder/sources/include/binder"
	if [ -d "$BINDER_SRC" ]; then
		cp -r "$BINDER_SRC"/* "$STAGING_DIR/usr/include/binder/" 2>/dev/null || true
		info_msg "Copied binder headers from android-binder sources"
	fi
	
	# Copy IpcBuffer headers (needed for IpcBuffer/*.h)
	local IPC_SRC="$PKGS_DIR/aml-audio-utils/sources/include/IpcBuffer"
	if [ -d "$IPC_SRC" ]; then
		cp -r "$IPC_SRC"/* "$STAGING_DIR/usr/include/IpcBuffer/" 2>/dev/null || true
		info_msg "Copied IpcBuffer headers from aml-audio-utils sources"
	fi
	
	# Copy cutils headers (needed for cutils/log.h and other cutils headers)
	local CUTILS_SRC="$PKGS_DIR/android-binder/sources/include/cutils"
	if [ -d "$CUTILS_SRC" ]; then
		cp -r "$CUTILS_SRC"/* "$STAGING_DIR/usr/include/cutils/" 2>/dev/null || true
	fi
	# Also check android-liblog for cutils headers
	local CUTILS_SRC2="$PKGS_DIR/android-liblog/sources/include/cutils"
	if [ -d "$CUTILS_SRC2" ]; then
		cp -r "$CUTILS_SRC2"/* "$STAGING_DIR/usr/include/cutils/" 2>/dev/null || true
	fi
	if [ -d "$STAGING_DIR/usr/include/cutils" ] && [ -n "$(ls -A "$STAGING_DIR/usr/include/cutils" 2>/dev/null)" ]; then
		info_msg "Copied cutils headers"
	fi
	
	# Copy utils headers (needed for utils/RefBase.h, utils/StrongPointer.h, etc.)
	local UTILS_SRC="$PKGS_DIR/android-binder/sources/include/utils"
	if [ -d "$UTILS_SRC" ]; then
		cp -r "$UTILS_SRC"/* "$STAGING_DIR/usr/include/utils/" 2>/dev/null || true
		info_msg "Copied utils headers from android-binder sources"
	fi
	
	# Copy Virtualx_v4.h from aml-audio-hal (needed for effect_tool.c)
	local VIRTUALX_SRC="$PKGS_DIR/aml-audio-hal/sources/include/Virtualx_v4.h"
	if [ -f "$VIRTUALX_SRC" ]; then
		cp "$VIRTUALX_SRC" "$STAGING_DIR/usr/include/" 2>/dev/null || true
		info_msg "Copied Virtualx_v4.h from aml-audio-hal sources"
	fi
	# Also check build directory
	local VIRTUALX_BUILD="$BUILD/aml-audio-hal-${PKG_VERSION}/include/Virtualx_v4.h"
	if [ ! -f "$STAGING_DIR/usr/include/Virtualx_v4.h" ] && [ -f "$VIRTUALX_BUILD" ]; then
		cp "$VIRTUALX_BUILD" "$STAGING_DIR/usr/include/" 2>/dev/null || true
		info_msg "Copied Virtualx_v4.h from aml-audio-hal build directory"
	fi
	
	# Set up HOST_DIR for protoc and grpc_cpp_plugin
	local TEMP_HOST_DIR="$PKG_BUILD_DIR/host_tools"
	mkdir -p "$TEMP_HOST_DIR/bin"
	mkdir -p "$TEMP_HOST_DIR/lib"
	mkdir -p "$TEMP_HOST_DIR/include"
	export HOST_DIR="$TEMP_HOST_DIR"
	
	# Find and set up protoc
	local PROTOC_FOUND=false
	# Check protobuf-compiler package
	local PROTOBUF_COMPILER_DEB=$(find "$BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/protobuf-compiler" -name "*.deb" 2>/dev/null | head -1)
	if [ -n "$PROTOBUF_COMPILER_DEB" ] && [ -f "$PROTOBUF_COMPILER_DEB" ]; then
		local PROTOBUF_EXTRACT_DIR="$PKG_BUILD_DIR/staging_protobuf"
		mkdir -p "$PROTOBUF_EXTRACT_DIR"
		if dpkg-deb -x "$PROTOBUF_COMPILER_DEB" "$PROTOBUF_EXTRACT_DIR" 2>/dev/null; then
			if [ -f "$PROTOBUF_EXTRACT_DIR/usr/bin/protoc" ]; then
				cp "$PROTOBUF_EXTRACT_DIR/usr/bin/protoc" "$HOST_DIR/bin/" 2>/dev/null || true
				chmod 755 "$HOST_DIR/bin/protoc" 2>/dev/null || true
				PROTOC_FOUND=true
				info_msg "Found protoc in protobuf-compiler package"
			fi
			# Copy protobuf headers
			if [ -d "$PROTOBUF_EXTRACT_DIR/usr/include/google" ]; then
				cp -r "$PROTOBUF_EXTRACT_DIR/usr/include/google" "$HOST_DIR/include/" 2>/dev/null || true
			fi
		fi
	fi
	
	if [ "$PROTOC_FOUND" = false ]; then
		# Check PKGS_DIR
		local PKG_DIR="$PKGS_DIR/protobuf-compiler"
		if [ -f "$PKG_DIR/sources/usr/bin/protoc" ]; then
			cp "$PKG_DIR/sources/usr/bin/protoc" "$HOST_DIR/bin/" 2>/dev/null || true
			chmod 755 "$HOST_DIR/bin/protoc" 2>/dev/null || true
			PROTOC_FOUND=true
			info_msg "Found protoc in protobuf-compiler sources"
		fi
		if [ -d "$PKG_DIR/sources/usr/include/google" ]; then
			cp -r "$PKG_DIR/sources/usr/include/google" "$HOST_DIR/include/" 2>/dev/null || true
		fi
	fi
	
	if [ "$PROTOC_FOUND" = false ]; then
		error_msg "protoc not found. Please build protobuf-compiler package first."
		return 1
	fi
	
	# Get libprotoc.so.32 and libprotobuf.so.32 for protoc runtime
	local PROTOC_LIBS_FOUND=false
	local PROTOC_LIBS_DIR=""
	# Check libprotobuf32t64 package
	local LIBPROTOBUF32T64_DEB=$(find "$BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/libprotobuf32t64" -name "*.deb" 2>/dev/null | head -1)
	if [ -n "$LIBPROTOBUF32T64_DEB" ] && [ -f "$LIBPROTOBUF32T64_DEB" ]; then
		local PROTOC_LIBS_EXTRACT_DIR="$PKG_BUILD_DIR/staging_protoc_libs"
		mkdir -p "$PROTOC_LIBS_EXTRACT_DIR"
		if dpkg-deb -x "$LIBPROTOBUF32T64_DEB" "$PROTOC_LIBS_EXTRACT_DIR" 2>/dev/null; then
			# Look for libprotoc.so* and libprotobuf.so* in x86_64-linux-gnu (host arch)
			if [ -d "$PROTOC_LIBS_EXTRACT_DIR/usr/lib/x86_64-linux-gnu" ]; then
				find "$PROTOC_LIBS_EXTRACT_DIR/usr/lib/x86_64-linux-gnu" \( -name "libprotoc.so*" -o -name "libprotobuf.so*" \) 2>/dev/null | while read lib; do
					if [ -e "$lib" ]; then
						cp -L "$lib" "$HOST_DIR/lib/" 2>/dev/null || cp "$lib" "$HOST_DIR/lib/" 2>/dev/null || true
					fi
				done
				PROTOC_LIBS_FOUND=true
			fi
		fi
	fi
	
	if [ "$PROTOC_LIBS_FOUND" = false ]; then
		# Check PKGS_DIR
		local PKG_DIR="$PKGS_DIR/libprotobuf32t64"
		if [ -d "$PKG_DIR/sources/usr/lib/x86_64-linux-gnu" ]; then
			find "$PKG_DIR/sources/usr/lib/x86_64-linux-gnu" \( -name "libprotoc.so*" -o -name "libprotobuf.so*" \) 2>/dev/null | while read lib; do
				if [ -e "$lib" ]; then
					cp -L "$lib" "$HOST_DIR/lib/" 2>/dev/null || cp "$lib" "$HOST_DIR/lib/" 2>/dev/null || true
				fi
			done
		fi
	fi
	
	# Set LD_LIBRARY_PATH for protoc
	if [ -d "$HOST_DIR/lib" ] && [ -n "$(ls -A "$HOST_DIR/lib" 2>/dev/null)" ]; then
		export LD_LIBRARY_PATH="${HOST_DIR}/lib:${LD_LIBRARY_PATH}"
		info_msg "Set LD_LIBRARY_PATH for protoc: $LD_LIBRARY_PATH"
	fi
	
	# Find and set up grpc_cpp_plugin
	local GRPC_PLUGIN_FOUND=false
	# First check for system-provided binary (from protobuf-compiler-grpc package)
	if command -v grpc_cpp_plugin >/dev/null 2>&1; then
		local SYSTEM_PLUGIN=$(command -v grpc_cpp_plugin)
		cp "$SYSTEM_PLUGIN" "$HOST_DIR/bin/grpc_cpp_plugin" 2>/dev/null || true
		chmod 755 "$HOST_DIR/bin/grpc_cpp_plugin" 2>/dev/null || true
		GRPC_PLUGIN_FOUND=true
		info_msg "Found grpc_cpp_plugin in system (protobuf-compiler-grpc package)"
	fi
	
	if [ "$GRPC_PLUGIN_FOUND" = false ]; then
		# Try to automatically install protobuf-compiler-grpc if not found
		info_msg "grpc_cpp_plugin not found, attempting to install protobuf-compiler-grpc..."
		if command -v sudo >/dev/null 2>&1; then
			if sudo apt-get update >/dev/null 2>&1 && sudo apt-get install -y --no-install-recommends protobuf-compiler-grpc >/dev/null 2>&1; then
				if command -v grpc_cpp_plugin >/dev/null 2>&1; then
					local SYSTEM_PLUGIN=$(command -v grpc_cpp_plugin)
					cp "$SYSTEM_PLUGIN" "$HOST_DIR/bin/grpc_cpp_plugin" 2>/dev/null || true
					chmod 755 "$HOST_DIR/bin/grpc_cpp_plugin" 2>/dev/null || true
					GRPC_PLUGIN_FOUND=true
					info_msg "Successfully installed and found grpc_cpp_plugin from protobuf-compiler-grpc package"
				fi
			fi
		fi
	fi
	
	if [ "$GRPC_PLUGIN_FOUND" = false ]; then
		# Check libgrpc-dev package
		local GRPC_DEB=$(find "$BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/libgrpc-dev" -name "*.deb" 2>/dev/null | head -1)
		if [ -n "$GRPC_DEB" ] && [ -f "$GRPC_DEB" ]; then
			local GRPC_EXTRACT_DIR="$PKG_BUILD_DIR/staging_grpc"
			mkdir -p "$GRPC_EXTRACT_DIR"
			if dpkg-deb -x "$GRPC_DEB" "$GRPC_EXTRACT_DIR" 2>/dev/null; then
				if [ -f "$GRPC_EXTRACT_DIR/usr/bin/grpc_cpp_plugin" ]; then
					cp "$GRPC_EXTRACT_DIR/usr/bin/grpc_cpp_plugin" "$HOST_DIR/bin/" 2>/dev/null || true
					chmod 755 "$HOST_DIR/bin/grpc_cpp_plugin" 2>/dev/null || true
					GRPC_PLUGIN_FOUND=true
					info_msg "Found grpc_cpp_plugin in libgrpc-dev package"
				fi
			fi
		fi
	fi
	
	if [ "$GRPC_PLUGIN_FOUND" = false ]; then
		# Check PKGS_DIR (fallback for legacy support)
		local PKG_DIR="$PKGS_DIR/libgrpc-dev"
		if [ -f "$PKG_DIR/sources/usr/bin/grpc_cpp_plugin" ]; then
			cp "$PKG_DIR/sources/usr/bin/grpc_cpp_plugin" "$HOST_DIR/bin/" 2>/dev/null || true
			chmod 755 "$HOST_DIR/bin/grpc_cpp_plugin" 2>/dev/null || true
			GRPC_PLUGIN_FOUND=true
			info_msg "Found grpc_cpp_plugin in libgrpc-dev sources"
		fi
	fi
	
	if [ "$GRPC_PLUGIN_FOUND" = false ]; then
		error_msg "grpc_cpp_plugin not found. Please ensure protobuf-compiler-grpc is installed or libgrpc-dev package is built."
		return 1
	fi
	
	# Get Boost headers
	local BOOST_STAGING_DIR="$BUILD/staging/libboost1.83-dev"
	mkdir -p "$BOOST_STAGING_DIR"
	local BOOST_DEB=$(find "$BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/libboost1.83-dev" -name "*.deb" 2>/dev/null | head -1)
	if [ -n "$BOOST_DEB" ] && [ -f "$BOOST_DEB" ]; then
		if [ ! -d "$BOOST_STAGING_DIR/usr/include/boost" ]; then
			dpkg-deb -x "$BOOST_DEB" "$BOOST_STAGING_DIR" 2>/dev/null
		fi
	fi
	
	local INCLUDES=""
	if [ -d "$BOOST_STAGING_DIR/usr/include" ]; then
		INCLUDES="-I$BOOST_STAGING_DIR/usr/include"
	fi
	local PKG_DIR_BOOST="$PKGS_DIR/libboost1.83-dev"
	if [ -d "$PKG_DIR_BOOST/sources/usr/include" ]; then
		INCLUDES="$INCLUDES -I$PKG_DIR_BOOST/sources/usr/include"
	fi
	
	# Get gRPC C++ headers (grpcpp)
	local GRPC_CPP_STAGING_DIR="$BUILD/staging/libgrpc++-dev"
	mkdir -p "$GRPC_CPP_STAGING_DIR"
	local GRPC_CPP_DEB=$(find "$BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/libgrpc++-dev" -name "*.deb" 2>/dev/null | head -1)
	if [ -n "$GRPC_CPP_DEB" ] && [ -f "$GRPC_CPP_DEB" ]; then
		if [ ! -d "$GRPC_CPP_STAGING_DIR/usr/include/grpcpp" ]; then
			dpkg-deb -x "$GRPC_CPP_DEB" "$GRPC_CPP_STAGING_DIR" 2>/dev/null
		fi
	fi
	
	if [ -d "$GRPC_CPP_STAGING_DIR/usr/include" ]; then
		INCLUDES="$INCLUDES -I$GRPC_CPP_STAGING_DIR/usr/include"
	fi
	local PKG_DIR_GRPC_CPP="$PKGS_DIR/libgrpc++-dev"
	if [ -d "$PKG_DIR_GRPC_CPP/sources/usr/include" ]; then
		INCLUDES="$INCLUDES -I$PKG_DIR_GRPC_CPP/sources/usr/include"
	fi
	
	# Get aml-audio-utils headers and libraries
	local AUDIO_UTILS_BUILD="$BUILD/aml-audio-utils-${PKG_VERSION}"
	if [ ! -d "$AUDIO_UTILS_BUILD" ]; then
		AUDIO_UTILS_BUILD="$BUILD/aml-audio-utils-amlogic-yocto-1.0"
	fi
	if [ -d "$AUDIO_UTILS_BUILD/staging/usr/include" ]; then
		INCLUDES="$INCLUDES -I$AUDIO_UTILS_BUILD/staging/usr/include"
	fi
	if [ -d "$AUDIO_UTILS_BUILD/include" ]; then
		INCLUDES="$INCLUDES -I$AUDIO_UTILS_BUILD/include"
	fi
	
	# Add staging include path for hardware headers
	INCLUDES="$INCLUDES -I$STAGING_DIR/usr/include"
	local AUDIO_UTILS_LIB=""
	if [ -f "$AUDIO_UTILS_BUILD/libamaudioutils.so" ]; then
		AUDIO_UTILS_LIB="-L$AUDIO_UTILS_BUILD"
	elif [ -d "$AUDIO_UTILS_BUILD/staging/usr/lib" ]; then
		AUDIO_UTILS_LIB="-L$AUDIO_UTILS_BUILD/staging/usr/lib"
	fi
	
	# Get android-binder libraries
	local BINDER_BUILD="$BUILD/android-binder-${PKG_VERSION}"
	if [ ! -d "$BINDER_BUILD" ]; then
		BINDER_BUILD="$BUILD/android-binder-amlogic-yocto-1.0"
	fi
	local BINDER_LIB=""
	if [ -d "$BINDER_BUILD/lib" ]; then
		BINDER_LIB="-L$BINDER_BUILD/lib"
	elif [ -f "$BINDER_BUILD/libbinder.so" ]; then
		BINDER_LIB="-L$BINDER_BUILD"
	fi
	
	# Get android-liblog libraries
	# Prefer build directory over package to avoid glibc version mismatches
	local LIBLOG_BUILD="$BUILD/android-liblog-${PKG_VERSION}"
	if [ ! -d "$LIBLOG_BUILD" ]; then
		LIBLOG_BUILD="$BUILD/android-liblog-amlogic-yocto-1.0"
	fi
	local LIBLOG_LIB=""
	# Prefer build directory (built with same toolchain) over package
	if [ -d "$LIBLOG_BUILD/lib" ] && [ -f "$LIBLOG_BUILD/lib/liblog.so" ]; then
		LIBLOG_LIB="-L$LIBLOG_BUILD/lib"
		# Copy to staging for linking
		cp "$LIBLOG_BUILD/lib/liblog.so"* "$STAGING_DIR/usr/lib/" 2>/dev/null || true
		info_msg "Using liblog.so from build directory (same toolchain)"
	elif [ -f "$LIBLOG_BUILD/liblog.so" ]; then
		LIBLOG_LIB="-L$LIBLOG_BUILD"
		# Copy to staging for linking
		cp "$LIBLOG_BUILD/liblog.so"* "$STAGING_DIR/usr/lib/" 2>/dev/null || true
		info_msg "Using liblog.so from build directory root (same toolchain)"
	else
		# Fallback to built package
		local LIBLOG_DEB=$(find "$BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/android-liblog" -name "*.deb" 2>/dev/null | head -1)
		if [ -n "$LIBLOG_DEB" ] && [ -f "$LIBLOG_DEB" ]; then
			local LIBLOG_STAGING_DIR="$BUILD/staging/android-liblog"
			mkdir -p "$LIBLOG_STAGING_DIR"
			if [ ! -d "$LIBLOG_STAGING_DIR/usr/lib" ]; then
				dpkg-deb -x "$LIBLOG_DEB" "$LIBLOG_STAGING_DIR" 2>/dev/null
			fi
			if [ -d "$LIBLOG_STAGING_DIR/usr/lib" ]; then
				LIBLOG_LIB="-L$LIBLOG_STAGING_DIR/usr/lib"
				# Copy to staging for linking
				cp "$LIBLOG_STAGING_DIR/usr/lib/liblog.so"* "$STAGING_DIR/usr/lib/" 2>/dev/null || true
				warning_msg "Using liblog.so from package (may have glibc version mismatch)"
			fi
		fi
	fi
	
	# Patch Makefile to use cross-compiler and set use_binder=y
	if ! grep -q "^CC[[:space:]]*:=" "$PKG_BUILD_DIR/Makefile" 2>/dev/null; then
		local CC_ESC=$(echo "$CC" | sed 's/[[\.*^$()+?{|]/\\&/g')
		local CXX_ESC=$(echo "$CXX" | sed 's/[[\.*^$()+?{|]/\\&/g')
		sed -i "1i CC := ${CC_ESC}\nCXX := ${CXX_ESC}\nuse_binder := y" "$PKG_BUILD_DIR/Makefile"
		info_msg "Added CC=${CC}, CXX=${CXX}, and use_binder=y to Makefile"
	else
		local CC_ESC=$(echo "$CC" | sed 's/[[\.*^$()+?{|]/\\&/g')
		local CXX_ESC=$(echo "$CXX" | sed 's/[[\.*^$()+?{|]/\\&/g')
		sed -i "s|^CC[[:space:]]*:=.*|CC := ${CC_ESC}|" "$PKG_BUILD_DIR/Makefile"
		sed -i "s|^CXX[[:space:]]*:=.*|CXX := ${CXX_ESC}|" "$PKG_BUILD_DIR/Makefile"
		if ! grep -q "^use_binder[[:space:]]*:=" "$PKG_BUILD_DIR/Makefile" 2>/dev/null; then
			sed -i "/^CXX[[:space:]]*:=/a use_binder := y" "$PKG_BUILD_DIR/Makefile"
		else
			sed -i "s|^use_binder[[:space:]]*:=.*|use_binder := y|" "$PKG_BUILD_DIR/Makefile"
		fi
		info_msg "Updated CC=${CC}, CXX=${CXX}, and use_binder=y in Makefile"
	fi
	
	# Patch Makefile .cpp rule command to use $(CXX) instead of $(CC) for C++ compilation
	# Change $(CC) to $(CXX) in command lines that have CXXFLAGS (indicates C++ compilation)
	# Use single quotes to prevent shell expansion, and escape $ in replacement
	sed -i 's|^\([[:space:]]*\)\$(CC) -c \$(CFLAGS) \$(CXXFLAGS)|\1$$(CXX) -c $$(CFLAGS) $$(CXXFLAGS)|' "$PKG_BUILD_DIR/Makefile" 2>/dev/null || true
	
	# Patch Makefile to replace -lgrpc++_unsecure with -lgrpc++
	if grep -q "lgrpc++_unsecure" "$PKG_BUILD_DIR/Makefile" 2>/dev/null; then
		sed -i 's/-lgrpc++_unsecure/-lgrpc++/g' "$PKG_BUILD_DIR/Makefile"
		info_msg "Patched Makefile to use -lgrpc++ instead of -lgrpc++_unsecure"
	fi
	
	# Remove -lboost_system from linker flags (boost::interprocess is header-only)
	# Use perl for more reliable pattern matching
	if grep -q "-lboost_system" "$PKG_BUILD_DIR/Makefile" 2>/dev/null; then
		# Use perl to remove -lboost_system with proper word boundary matching
		perl -i -pe 's/\s+-lboost_system\s+/ /g; s/\s+-lboost_system$//g; s/-lboost_system\s+//g' "$PKG_BUILD_DIR/Makefile" 2>/dev/null || \
		sed -i 's/\s*-lboost_system\s*/ /g' "$PKG_BUILD_DIR/Makefile"
		# Clean up any double spaces
		sed -i 's/  \+/ /g' "$PKG_BUILD_DIR/Makefile"
		info_msg "Removed -lboost_system from Makefile (boost::interprocess is header-only)"
	fi
	
	# Patch Makefile to set LD_LIBRARY_PATH for protoc commands
	if [ -n "$LD_LIBRARY_PATH" ]; then
		sed -i "s|\$(PROTOC)|\$(PROTOC) env LD_LIBRARY_PATH=\"${LD_LIBRARY_PATH}\" |g" "$PKG_BUILD_DIR/Makefile" 2>/dev/null || \
		sed -i "s|protoc |env LD_LIBRARY_PATH=\"${LD_LIBRARY_PATH}\" protoc |g" "$PKG_BUILD_DIR/Makefile" 2>/dev/null || true
		info_msg "Patched Makefile to set LD_LIBRARY_PATH for protoc"
	fi
	
	# Patch Makefile to add include paths
	if [ -n "$INCLUDES" ]; then
		# Find CFLAGS line and add includes
		if grep -q "^CFLAGS" "$PKG_BUILD_DIR/Makefile" 2>/dev/null; then
			sed -i "s|^CFLAGS +=|CFLAGS += $INCLUDES |" "$PKG_BUILD_DIR/Makefile"
			info_msg "Added include paths to CFLAGS: $INCLUDES"
		fi
	fi
	
	# Fix pattern rules to use VPATH (remove src/ prefix so VPATH can find files in subdirectories)
	# The Makefile uses $(notdir) which strips paths, so objects are built as
	# $(AML_BUILD_DIR)/main_audio_service_binder.o from src/binder/main_audio_service_binder.cpp
	# VPATH will find the source in src/binder/ if we use %.cpp instead of src/%.cpp
	# Also fix the command to use $(CXX) correctly (replace $$(CXX) with $(CXX))
	if grep -q "^\$(AML_BUILD_DIR)/%.o: src/%.cpp" "$PKG_BUILD_DIR/Makefile" 2>/dev/null; then
		sed -i "s|^\$(AML_BUILD_DIR)/%.o: src/%.cpp|\$(AML_BUILD_DIR)/%.o: %.cpp|" "$PKG_BUILD_DIR/Makefile"
		info_msg "Fixed pattern rule for .cpp files to use VPATH"
	fi
	# Fix the .cpp pattern rule command: hardcode CXX and CXXFLAGS values
	# Since pattern rules don't inherit variables reliably, hardcode the actual values
	# Get the actual CXX path from the Makefile or use the detected one
	local CXX_VALUE=$(grep "^CXX[[:space:]]*:=" "$PKG_BUILD_DIR/Makefile" 2>/dev/null | head -1 | sed 's/^CXX[[:space:]]*:=[[:space:]]*//')
	if [ -z "$CXX_VALUE" ]; then
		CXX_VALUE="$CXX"
	fi
	# Update CXXFLAGS to use C++17 for designated initializers support (GCC 7.3.1 supports C++17)
	if grep -q "std=c++14" "$PKG_BUILD_DIR/Makefile" 2>/dev/null; then
		sed -i 's/-std=c++14/-std=c++17/g' "$PKG_BUILD_DIR/Makefile"
		info_msg "Updated CXXFLAGS to use C++17 for designated initializers support"
	fi
	# Get CXXFLAGS from Makefile (after update)
	local CXXFLAGS_VALUE=$(grep "^CXXFLAGS" "$PKG_BUILD_DIR/Makefile" 2>/dev/null | head -1 | sed 's/^CXXFLAGS[[:space:]]*+=[[:space:]]*//')
	if [ -z "$CXXFLAGS_VALUE" ]; then
		CXXFLAGS_VALUE="-Wall -std=c++17"
	fi
	# Find the line number of the pattern rule and replace the next line
	local LINE_NUM=$(grep -n "^\$(AML_BUILD_DIR)/%.o: %.cpp" "$PKG_BUILD_DIR/Makefile" | cut -d: -f1)
	if [ -n "$LINE_NUM" ]; then
		# The command line is on the next line (LINE_NUM + 1)
		local NEXT_LINE=$((LINE_NUM + 1))
		# Build the replacement line with hardcoded values
		# Use $(CFLAGS) as a Make variable since it's already defined and complex
		local REPLACEMENT_LINE="	${CXX_VALUE} -c \$(CFLAGS) ${CXXFLAGS_VALUE} -o \$\@ \$\<"
		# Use sed to replace the specific line
		sed -i "${NEXT_LINE}s|.*|${REPLACEMENT_LINE}|" "$PKG_BUILD_DIR/Makefile"
		info_msg "Hardcoded CXX=${CXX_VALUE} and CXXFLAGS=${CXXFLAGS_VALUE} in pattern rule (line $NEXT_LINE)"
	else
		warning_msg "Could not find pattern rule for %.cpp, skipping hardcode fix"
	fi
	if grep -q "^\$(AML_BUILD_DIR)/%.o: src/%.c" "$PKG_BUILD_DIR/Makefile" 2>/dev/null; then
		sed -i "s|^\$(AML_BUILD_DIR)/%.o: src/%.c|\$(AML_BUILD_DIR)/%.o: %.c|" "$PKG_BUILD_DIR/Makefile"
		info_msg "Fixed pattern rule for .c files to use VPATH"
	fi
	
	# Set library paths for linking
	local LDFLAGS_EXTRA=""
	if [ -n "$AUDIO_UTILS_LIB" ]; then
		LDFLAGS_EXTRA="$LDFLAGS_EXTRA $AUDIO_UTILS_LIB"
	fi
	if [ -n "$BINDER_LIB" ]; then
		LDFLAGS_EXTRA="$LDFLAGS_EXTRA $BINDER_LIB"
	fi
	if [ -n "$LIBLOG_LIB" ]; then
		LDFLAGS_EXTRA="$LDFLAGS_EXTRA $LIBLOG_LIB"
	fi
	
	# Also add boost library path if needed
	local BOOST_STAGING_DIR="$BUILD/staging/libboost1.83-dev"
	if [ -d "$BOOST_STAGING_DIR/usr/lib" ]; then
		LDFLAGS_EXTRA="$LDFLAGS_EXTRA -L$BOOST_STAGING_DIR/usr/lib"
	fi
	
	# Patch Makefile to add library paths to LDFLAGS and SC_LDFLAGS
	# Library paths (-L flags) must come before library names (-l flags)
	if [ -n "$LDFLAGS_EXTRA" ]; then
		# Escape LDFLAGS_EXTRA for sed (escape $ and /)
		local LDFLAGS_ESC=$(echo "$LDFLAGS_EXTRA" | sed 's/[[\.*^$()+?{|]/\\&/g' | sed 's|/|\\/|g')
		# Add library paths to SC_LDFLAGS lines (used for audio_server linking)
		# Insert -L flags at the beginning of the SC_LDFLAGS line
		sed -i "/^SC_LDFLAGS/s|SC_LDFLAGS+=\\(.*\\)|SC_LDFLAGS+=$LDFLAGS_ESC \\1|" "$PKG_BUILD_DIR/Makefile"
		# Add library paths to LDFLAGS lines (used for libaudio_client.so linking)
		sed -i "/^LDFLAGS/s|LDFLAGS+=\\(.*\\)|LDFLAGS+=$LDFLAGS_ESC \\1|" "$PKG_BUILD_DIR/Makefile"
		info_msg "Added library paths to Makefile LDFLAGS: $LDFLAGS_EXTRA"
	fi
	
	# Remove -lboost_system from linker flags AFTER all LDFLAGS modifications
	# (boost::interprocess is header-only, no library needed)
	# Use simple sed to remove all occurrences
	if grep -q "lboost_system" "$PKG_BUILD_DIR/Makefile" 2>/dev/null; then
		sed -i 's/-lboost_system//g' "$PKG_BUILD_DIR/Makefile"
		# Clean up any double spaces that might result
		sed -i 's/  \+/ /g' "$PKG_BUILD_DIR/Makefile"
		info_msg "Removed -lboost_system from Makefile (boost::interprocess is header-only)"
	fi
	
	# Set use_binder=y for build
	export use_binder=y
	
	# Build
	info_msg "Running make with CC=${CC} CXX=${CXX} use_binder=y"
	make all CC="${CC}" CXX="${CXX}" use_binder=y || {
		error_msg "Build failed"
		return 1
	}
	
	# Install using Makefile's install target
	make install DESTDIR="$pkgdir" || {
		error_msg "Install failed"
		return 1
	}
	
	# Remove headers from package (they're only for build-time, not runtime)
	# Headers should be provided by dependency packages (aml-audio-hal, etc.)
	if [ -d "$pkgdir/usr/include" ]; then
		find "$pkgdir/usr/include" -type f -delete 2>/dev/null || true
		find "$pkgdir/usr/include" -type d -empty -delete 2>/dev/null || true
		info_msg "Removed headers from package (provided by dependencies)"
	fi
	
	# Install systemd service file
	if [ -f "$PKGS_DIR/$PKG_NAME/files/audioserver.service" ]; then
		install -m 644 "$PKGS_DIR/$PKG_NAME/files/audioserver.service" "$pkgdir/lib/systemd/system/" || true
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
