PKG_NAME="aml-audio-service"
PKG_VERSION="amlogic-yocto-1.0"
PKG_SHA256=""
PKG_SOURCE_DIR=""
PKG_SITE=""
PKG_URL=""
PKG_ARCH="arm aarch64"
PKG_LICENSE="AMLOGIC"
PKG_SHORTDESC="Amlogic Audio Service and Client Library"

PKG_NEED_BUILD="YES"

make_target() {
	local pkgdir="$BUILD_IMAGES/.tmp/${PKG_NAME}_${VERSION}_${DISTRIB_ARCH}"
	# Overwrite by recreating directory structure
	mkdir -p $pkgdir/DEBIAN
	mkdir -p $pkgdir/usr/lib
	mkdir -p $pkgdir/usr/bin
	mkdir -p $pkgdir/usr/include

	# Set up control file
	cat <<-EOF > $pkgdir/DEBIAN/control
Package: ${PKG_NAME}
Version: ${VERSION}
Architecture: ${DISTRIB_ARCH}
Maintainer: Khadas <hello@khadas.com>
Depends: aml-audio-utils, android-binder, libboost-system1.83.0, libgrpc++1.51t64, libprotobuf32t64, libgrpc29t64, libabsl20220623t64
Build-Depends: protobuf-compiler, libgrpc-dev
Section: libs
Priority: optional
Description: Amlogic Audio Service and Client Library
 ${PKG_SHORTDESC}
 Provides audio_server daemon, libaudio_client.so, and headers.
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
	export TARGET_DIR="$pkgdir"
	export STRIP="${CROSS_COMPILE}strip"
	
	# Need protoc and grpc_cpp_plugin for protobuf/gRPC code generation
	# The Makefile expects HOST_DIR to point to directory containing bin/ and include/
	# Use staged protobuf-compiler and libgrpc-dev packages
	local HOST_DIR=""
	local PROTOBUF_STAGING_DIR="$BUILD/staging/protobuf-compiler"
	local GRPC_STAGING_DIR="$BUILD/staging/libgrpc-dev"
	local TEMP_HOST_DIR="$PKG_BUILD_DIR/host_tools"
	
	# Extract protobuf-compiler package if needed
	if [ ! -f "$PROTOBUF_STAGING_DIR/usr/bin/protoc" ]; then
		local PROTOBUF_DEB=$(find "$BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/protobuf-compiler" -name "*.deb" 2>/dev/null | head -1)
		if [ -n "$PROTOBUF_DEB" ] && [ -f "$PROTOBUF_DEB" ]; then
			info_msg "Found protobuf-compiler package, extracting to staging..."
			mkdir -p "$PROTOBUF_STAGING_DIR"
			if dpkg-deb -x "$PROTOBUF_DEB" "$PROTOBUF_STAGING_DIR" 2>/dev/null; then
				info_msg "Successfully extracted protobuf-compiler to staging"
			else
				warning_msg "Failed to extract protobuf-compiler package"
			fi
		else
			error_msg "protobuf-compiler package not found. Please build it first."
			error_msg "Expected location: $BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/protobuf-compiler/"
			return 1
		fi
	fi
	
	# Extract libgrpc-dev package if needed
	if [ ! -f "$GRPC_STAGING_DIR/usr/bin/grpc_cpp_plugin" ]; then
		local GRPC_DEB=$(find "$BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/libgrpc-dev" -name "*.deb" 2>/dev/null | head -1)
		if [ -n "$GRPC_DEB" ] && [ -f "$GRPC_DEB" ]; then
			info_msg "Found libgrpc-dev package, extracting to staging..."
			mkdir -p "$GRPC_STAGING_DIR"
			if dpkg-deb -x "$GRPC_DEB" "$GRPC_STAGING_DIR" 2>/dev/null; then
				info_msg "Successfully extracted libgrpc-dev to staging"
			else
				warning_msg "Failed to extract libgrpc-dev package"
			fi
		else
			error_msg "libgrpc-dev package not found. Please build it first."
			error_msg "Expected location: $BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/libgrpc-dev/"
			return 1
		fi
	fi
	
	# Create unified HOST_DIR from staged packages
	mkdir -p "$TEMP_HOST_DIR/bin" "$TEMP_HOST_DIR/include" "$TEMP_HOST_DIR/lib"
	
	# Copy protoc from protobuf-compiler
	if [ -f "$PROTOBUF_STAGING_DIR/usr/bin/protoc" ]; then
		cp "$PROTOBUF_STAGING_DIR/usr/bin/protoc" "$TEMP_HOST_DIR/bin/" 2>/dev/null || true
		chmod 755 "$TEMP_HOST_DIR/bin/protoc" 2>/dev/null || true
	fi
	
	# Copy protoc shared libraries (libprotoc.so.32, libprotobuf.so.32, etc.)
	# protoc needs these at runtime
	# These libraries are typically in libprotobuf32t64 package, not protobuf-compiler
	# Try to extract from libprotobuf32t64 package if available
	local PROTOBUF_LIB_PKG="$PKGS_DIR/protobuf-compiler/sources/libprotobuf32t64_*.deb"
	local PROTOBUF_LIB_EXTRACT_DIR="$PKG_BUILD_DIR/temp_protobuf_lib"
	
	# Check if we need to extract libprotobuf32t64 package
	if [ ! -f "$TEMP_HOST_DIR/lib/libprotoc.so.32" ]; then
		# Try to find and extract from deb package in sources
		for deb_file in $PROTOBUF_LIB_PKG; do
			if [ -f "$deb_file" ]; then
				mkdir -p "$PROTOBUF_LIB_EXTRACT_DIR"
				dpkg-deb -x "$deb_file" "$PROTOBUF_LIB_EXTRACT_DIR" 2>/dev/null || true
				# Copy libraries
				if [ -d "$PROTOBUF_LIB_EXTRACT_DIR/usr/lib/x86_64-linux-gnu" ]; then
					find "$PROTOBUF_LIB_EXTRACT_DIR/usr/lib/x86_64-linux-gnu" \( -name "libprotoc.so*" -o -name "libprotobuf.so*" \) -type f 2>/dev/null | while read lib; do
						cp "$lib" "$TEMP_HOST_DIR/lib/" 2>/dev/null || true
					done
				fi
				if [ -d "$PROTOBUF_LIB_EXTRACT_DIR/usr/lib" ]; then
					find "$PROTOBUF_LIB_EXTRACT_DIR/usr/lib" \( -name "libprotoc.so*" -o -name "libprotobuf.so*" \) -type f 2>/dev/null | while read lib; do
						cp "$lib" "$TEMP_HOST_DIR/lib/" 2>/dev/null || true
					done
				fi
				# Cleanup
				find "$PROTOBUF_LIB_EXTRACT_DIR" -mindepth 1 -delete 2>/dev/null || true
				rmdir "$PROTOBUF_LIB_EXTRACT_DIR" 2>/dev/null || true
				if [ -f "$TEMP_HOST_DIR/lib/libprotoc.so.32" ]; then
					info_msg "Extracted protobuf libraries from libprotobuf32t64 package"
					break
				fi
			fi
		done
	fi
	
	# Try from staged package directory (from protobuf-compiler package)
	if [ -d "$PROTOBUF_STAGING_DIR/usr/lib" ]; then
		find "$PROTOBUF_STAGING_DIR/usr/lib" \( -name "libprotoc.so*" -o -name "libprotobuf.so*" \) -type f 2>/dev/null | while read lib; do
			cp "$lib" "$TEMP_HOST_DIR/lib/" 2>/dev/null || true
		done
	fi
	# Also check x86_64-linux-gnu subdirectory
	if [ -d "$PROTOBUF_STAGING_DIR/usr/lib/x86_64-linux-gnu" ]; then
		find "$PROTOBUF_STAGING_DIR/usr/lib/x86_64-linux-gnu" \( -name "libprotoc.so*" -o -name "libprotobuf.so*" \) -type f 2>/dev/null | while read lib; do
			cp "$lib" "$TEMP_HOST_DIR/lib/" 2>/dev/null || true
		done
	fi
	
	# Final check - if still not found, error (offline only, must be ported)
	if [ ! -f "$TEMP_HOST_DIR/lib/libprotoc.so.32" ]; then
		error_msg "libprotoc.so.32 not found in local sources"
		error_msg "Please port libprotobuf32t64 as a local package (offline build):"
		error_msg "  1. Download libprotobuf32t64_3.21.12-8.2ubuntu0.2_amd64.deb"
		error_msg "  2. Place it in packages/protobuf-compiler/sources/"
		error_msg "  3. Rebuild"
		return 1
	fi
	
	# Copy grpc plugins from libgrpc-dev
	if [ -d "$GRPC_STAGING_DIR/usr/bin" ]; then
		find "$GRPC_STAGING_DIR/usr/bin" -type f -name "*grpc*" -exec cp {} "$TEMP_HOST_DIR/bin/" \; 2>/dev/null || true
		find "$TEMP_HOST_DIR/bin" -type f -exec chmod 755 {} \; 2>/dev/null || true
	fi
	
	# Copy protobuf headers
	if [ -d "$PROTOBUF_STAGING_DIR/usr/include/google" ]; then
		cp -r "$PROTOBUF_STAGING_DIR/usr/include/google" "$TEMP_HOST_DIR/include/" 2>/dev/null || true
	fi
	
	# Copy grpc headers
	if [ -d "$GRPC_STAGING_DIR/usr/include/grpc" ]; then
		cp -r "$GRPC_STAGING_DIR/usr/include/grpc" "$TEMP_HOST_DIR/include/" 2>/dev/null || true
	fi
	if [ -d "$GRPC_STAGING_DIR/usr/include/grpc++" ]; then
		cp -r "$GRPC_STAGING_DIR/usr/include/grpc++" "$TEMP_HOST_DIR/include/" 2>/dev/null || true
	fi
	
	HOST_DIR="$TEMP_HOST_DIR"
	
	if [ ! -f "$HOST_DIR/bin/protoc" ]; then
		error_msg "protoc not found after extracting packages. Protobuf code generation will fail."
		return 1
	fi
	
	if [ ! -f "$HOST_DIR/bin/grpc_cpp_plugin" ]; then
		warning_msg "grpc_cpp_plugin not found at $HOST_DIR/bin/grpc_cpp_plugin"
		warning_msg "gRPC code generation may fail."
	fi
	
	info_msg "Using protoc and grpc tools from staged packages"
	
	export HOST_DIR="$HOST_DIR"
	
	# Set LD_LIBRARY_PATH so protoc can find its shared libraries
	# Include both our lib directory and system library paths as fallback
	local LD_LIB_PATH=""
	if [ -d "$TEMP_HOST_DIR/lib" ]; then
		LD_LIB_PATH="$TEMP_HOST_DIR/lib"
	fi
	# Add system library paths as fallback (for amd64 host)
	for sys_path in "/usr/lib/x86_64-linux-gnu" "/usr/lib" "/lib/x86_64-linux-gnu"; do
		if [ -d "$sys_path" ]; then
			if [ -n "$LD_LIB_PATH" ]; then
				LD_LIB_PATH="$LD_LIB_PATH:$sys_path"
			else
				LD_LIB_PATH="$sys_path"
			fi
		fi
	done
	if [ -n "$LD_LIB_PATH" ]; then
		export LD_LIBRARY_PATH="$LD_LIB_PATH:${LD_LIBRARY_PATH:-}"
		info_msg "Set LD_LIBRARY_PATH=$LD_LIBRARY_PATH for protoc runtime libraries"
	fi
	
	# Create build directory for generated files
	mkdir -p "$AML_BUILD_DIR/src"
	
	# Get include paths for dependencies
	local INCLUDES="-I./include -I. -I./src -I$AML_BUILD_DIR/src"
	
	# Add staging directories for dependencies
	if [ -d "$PKGS_DIR/aml-audio-utils/sources/include" ]; then
		INCLUDES="-I$PKGS_DIR/aml-audio-utils/sources/include $INCLUDES"
	fi
	if [ -d "$PKGS_DIR/android-binder/sources/include" ]; then
		INCLUDES="-I$PKGS_DIR/android-binder/sources/include $INCLUDES"
	fi
	
	# Add gRPC and protobuf includes from rootfs or system
	if [ -d "$ROOTFS_TEMP/usr/include" ]; then
		INCLUDES="-I$ROOTFS_TEMP/usr/include $INCLUDES"
	fi
	
	# Update Makefile CFLAGS to include all dependency paths
	# Add dependency include paths while preserving existing includes
	sed -i "s|-I\$(AML_BUILD_DIR)/src -I\$(AML_BUILD_DIR)|-I\$(AML_BUILD_DIR)/src -I\$(AML_BUILD_DIR) $INCLUDES|" "$PKG_BUILD_DIR/Makefile" 2>/dev/null || true
	
	# The Makefile uses HOST_DIR variable, which we've set above
	# PROTOC=$(HOST_DIR)/bin/protoc and GRPC_CPP_PLUGIN_PATH=$(HOST_DIR)/bin/grpc_cpp_plugin
	# These should work automatically with the exported HOST_DIR
	
	# Replace grpc++_unsecure with grpc++ (Debian provides regular grpc++, not unsecure variant)
	# The unsecure variant is typically just regular grpc++ without TLS/SSL, which should work
	sed -i 's/-lgrpc++_unsecure/-lgrpc++/g' "$PKG_BUILD_DIR/Makefile" 2>/dev/null || true
	
	# Add library paths for dependencies
	# Ensure we can find amamaudioutils, log, and other libraries
	local LIB_PATHS=""
	
	# Add paths for built packages (aml-audio-utils, android-binder)
	local AUDIO_UTILS_BUILD="$BUILD/aml-audio-utils-amlogic-yocto-1.0"
	if [ -d "$AUDIO_UTILS_BUILD" ]; then
		LIB_PATHS="-L$AUDIO_UTILS_BUILD $LIB_PATHS"
	fi
	
	local BINDER_BUILD="$BUILD/android-binder-amlogic-yocto-1.0"
	if [ -d "$BINDER_BUILD" ]; then
		LIB_PATHS="-L$BINDER_BUILD $LIB_PATHS"
	fi
	
	# Add rootfs library paths for Debian packages (grpc, protobuf, boost)
	if [ -d "$ROOTFS_TEMP/usr/lib" ]; then
		LIB_PATHS="-L$ROOTFS_TEMP/usr/lib $LIB_PATHS"
	fi
	
	# Update LDFLAGS to include library paths
	if [ -n "$LIB_PATHS" ]; then
		sed -i "s|SC_LDFLAGS+=-Wl,--no-as-needed|SC_LDFLAGS+=-Wl,--no-as-needed $LIB_PATHS|" "$PKG_BUILD_DIR/Makefile" 2>/dev/null || true
		sed -i "s|LDFLAGS+= -Wl,--no-as-needed|LDFLAGS+= -Wl,--no-as-needed $LIB_PATHS|" "$PKG_BUILD_DIR/Makefile" 2>/dev/null || true
	fi
	
	# Build
	info_msg "Building ${PKG_NAME}..."
	make clean 2>/dev/null || true
	# LD_LIBRARY_PATH should already be set above, but ensure it's exported
	# This ensures make and any subprocesses (like protoc) can find the libraries
	export LD_LIBRARY_PATH
	info_msg "Building with LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
	
	# Patch Makefile to explicitly set LD_LIBRARY_PATH when running protoc
	# This ensures protoc can find libprotoc.so.32 even if environment isn't inherited
	if [ -n "$LD_LIBRARY_PATH" ]; then
		# Replace PROTOC invocations to include LD_LIBRARY_PATH
		sed -i "s|\$(PROTOC)|env LD_LIBRARY_PATH=\"$LD_LIBRARY_PATH\" \$(PROTOC)|g" "$PKG_BUILD_DIR/Makefile" 2>/dev/null || true
		info_msg "Patched Makefile to set LD_LIBRARY_PATH for protoc commands"
	fi
	
	make all || {
		error_msg "Build failed"
		return 1
	}

	# Install audio_server binary
	if [ -f "$AML_BUILD_DIR/audio_server" ]; then
		install -m 755 "$AML_BUILD_DIR/audio_server" "${pkgdir}/usr/bin/"
		${STRIP} "${pkgdir}/usr/bin/audio_server" 2>/dev/null || true
	else
		warning_msg "audio_server not found after build"
	fi

	# Install libaudio_client.so
	if [ -f "$AML_BUILD_DIR/libaudio_client.so" ]; then
		install -m 644 "$AML_BUILD_DIR/libaudio_client.so" "${pkgdir}/usr/lib/"
		${STRIP} "${pkgdir}/usr/lib/libaudio_client.so" 2>/dev/null || true
	else
		error_msg "libaudio_client.so not found after build"
		return 1
	fi

	# Install headers
	if [ -f "$PKG_BUILD_DIR/include/audio_if.h" ]; then
		install -m 644 "$PKG_BUILD_DIR/include/audio_if.h" "${pkgdir}/usr/include/"
	fi
	if [ -f "$PKG_BUILD_DIR/include/audio_if_client.h" ]; then
		install -m 644 "$PKG_BUILD_DIR/include/audio_if_client.h" "${pkgdir}/usr/include/"
	fi
	if [ -f "$PKG_BUILD_DIR/include/audio_effect_if.h" ]; then
		install -m 644 "$PKG_BUILD_DIR/include/audio_effect_if.h" "${pkgdir}/usr/include/"
	fi
	if [ -f "$PKG_BUILD_DIR/include/audio_effect_params.h" ]; then
		install -m 644 "$PKG_BUILD_DIR/include/audio_effect_params.h" "${pkgdir}/usr/include/"
	fi

	# Install test binaries (optional, but included in original package)
	for test_bin in audio_client_test audio_client_test_ac3 halplay hal_capture hal_param hal_dump dap_setting speaker_delay digital_mode master_vol start_arc test_arc; do
		if [ -f "$AML_BUILD_DIR/$test_bin" ]; then
			install -m 755 "$AML_BUILD_DIR/$test_bin" "${pkgdir}/usr/bin/"
			${STRIP} "${pkgdir}/usr/bin/$test_bin" 2>/dev/null || true
		fi
	done

	# Install systemd service
	if [ -f "$PKGS_DIR/${PKG_NAME}/files/audioserver.service" ]; then
		mkdir -p "${pkgdir}/etc/systemd/system"
		install -m 644 "$PKGS_DIR/${PKG_NAME}/files/audioserver.service" "${pkgdir}/etc/systemd/system/"
		
		# Install systemd config
		mkdir -p "${pkgdir}/etc/systemd/system.conf.d"
		cat <<-EOF > "${pkgdir}/etc/systemd/system.conf.d/audioserver.conf"
[Manager]
DefaultEnvironment=AUDIO_SERVER_SOCKET=unix:///run/audio_socket
EOF
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

