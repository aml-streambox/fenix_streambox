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
	# protoc binary needs these at runtime - it dynamically links to libprotoc.so.32
	# Use libraries from the ported libprotobuf32t64 package (NO SYSTEM LIBRARIES!)
	local PROTOBUF_LIB_STAGING_DIR="$BUILD/staging/libprotobuf32t64"
	
	# Extract libprotobuf32t64 package if needed
	if [ ! -d "$PROTOBUF_LIB_STAGING_DIR/usr/lib" ] && [ ! -d "$PROTOBUF_LIB_STAGING_DIR/usr/lib/x86_64-linux-gnu" ]; then
		local PROTOBUF_LIB_DEB=$(find "$BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/libprotobuf32t64" -name "*.deb" 2>/dev/null | head -1)
		if [ -n "$PROTOBUF_LIB_DEB" ] && [ -f "$PROTOBUF_LIB_DEB" ]; then
			info_msg "Found libprotobuf32t64 package, extracting to staging..."
			mkdir -p "$PROTOBUF_LIB_STAGING_DIR"
			if dpkg-deb -x "$PROTOBUF_LIB_DEB" "$PROTOBUF_LIB_STAGING_DIR" 2>/dev/null; then
				info_msg "Successfully extracted libprotobuf32t64 to staging"
			else
				warning_msg "Failed to extract libprotobuf32t64 package"
			fi
		else
			# Try from sources directly
			if [ -d "$PKGS_DIR/libprotobuf32t64/sources/usr" ]; then
				info_msg "Using libprotobuf32t64 from sources directly..."
				mkdir -p "$PROTOBUF_LIB_STAGING_DIR"
				cp -r "$PKGS_DIR/libprotobuf32t64/sources/usr"/* "$PROTOBUF_LIB_STAGING_DIR/usr/" 2>/dev/null || true
			else
				error_msg "libprotobuf32t64 package not found. Please build it first."
				error_msg "Expected location: $BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/libprotobuf32t64/"
				error_msg "Or sources at: $PKGS_DIR/libprotobuf32t64/sources/usr/"
				return 1
			fi
		fi
	fi
	
	# Copy libraries from libprotobuf32t64 package
	if [ -d "$PROTOBUF_LIB_STAGING_DIR/usr/lib/x86_64-linux-gnu" ]; then
		find "$PROTOBUF_LIB_STAGING_DIR/usr/lib/x86_64-linux-gnu" \( -name "libprotoc.so*" -o -name "libprotobuf.so*" \) 2>/dev/null | while read lib; do
			if [ -e "$lib" ]; then
				cp -L "$lib" "$TEMP_HOST_DIR/lib/" 2>/dev/null || cp "$lib" "$TEMP_HOST_DIR/lib/" 2>/dev/null || true
			fi
		done
	fi
	if [ -d "$PROTOBUF_LIB_STAGING_DIR/usr/lib" ]; then
		find "$PROTOBUF_LIB_STAGING_DIR/usr/lib" \( -name "libprotoc.so*" -o -name "libprotobuf.so*" \) 2>/dev/null | while read lib; do
			if [ -e "$lib" ]; then
				cp -L "$lib" "$TEMP_HOST_DIR/lib/" 2>/dev/null || cp "$lib" "$TEMP_HOST_DIR/lib/" 2>/dev/null || true
			fi
		done
	fi
	
	# Verify libraries were copied (MUST be from ported package, NOT system)
	if [ ! -f "$TEMP_HOST_DIR/lib/libprotoc.so.32" ]; then
		error_msg "libprotoc.so.32 not found from ported libprotobuf32t64 package"
		error_msg "Please build libprotobuf32t64 package first:"
		error_msg "  1. Extract libprotobuf32t64_3.21.12-8.2ubuntu0.2_amd64.deb"
		error_msg "  2. Place contents in packages/libprotobuf32t64/sources/usr/"
		error_msg "  3. Build libprotobuf32t64 package"
		error_msg "  4. Rebuild aml-audio-service"
		return 1
	fi
	
	# Copy grpc plugins from libgrpc-dev
	# Try from staging directory first
	if [ -d "$GRPC_STAGING_DIR/usr/bin" ]; then
		find "$GRPC_STAGING_DIR/usr/bin" -type f -name "*grpc*" -exec cp {} "$TEMP_HOST_DIR/bin/" \; 2>/dev/null || true
		find "$TEMP_HOST_DIR/bin" -type f -exec chmod 755 {} \; 2>/dev/null || true
	fi
	# Also try from sources directly if not found
	if [ ! -f "$TEMP_HOST_DIR/bin/grpc_cpp_plugin" ] && [ -d "$PKGS_DIR/libgrpc-dev/sources/usr/bin" ]; then
		find "$PKGS_DIR/libgrpc-dev/sources/usr/bin" -type f -name "*grpc*" -exec cp {} "$TEMP_HOST_DIR/bin/" \; 2>/dev/null || true
		find "$TEMP_HOST_DIR/bin" -type f -exec chmod 755 {} \; 2>/dev/null || true
	fi
	# Also check lib/x86_64-linux-gnu/bin (some packages put binaries there)
	if [ ! -f "$TEMP_HOST_DIR/bin/grpc_cpp_plugin" ] && [ -d "$PKGS_DIR/libgrpc-dev/sources/usr/lib/x86_64-linux-gnu/bin" ]; then
		find "$PKGS_DIR/libgrpc-dev/sources/usr/lib/x86_64-linux-gnu/bin" -type f -name "*grpc*" -exec cp {} "$TEMP_HOST_DIR/bin/" \; 2>/dev/null || true
		find "$TEMP_HOST_DIR/bin" -type f -exec chmod 755 {} \; 2>/dev/null || true
	fi
	if [ ! -f "$TEMP_HOST_DIR/bin/grpc_cpp_plugin" ] && [ -d "$GRPC_STAGING_DIR/usr/lib/x86_64-linux-gnu/bin" ]; then
		find "$GRPC_STAGING_DIR/usr/lib/x86_64-linux-gnu/bin" -type f -name "*grpc*" -exec cp {} "$TEMP_HOST_DIR/bin/" \; 2>/dev/null || true
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
		error_msg "grpc_cpp_plugin not found at $HOST_DIR/bin/grpc_cpp_plugin"
		error_msg "gRPC code generation requires grpc_cpp_plugin binary."
		error_msg "The plugin is not included in libgrpc-dev package and must be obtained separately."
		error_msg "Please download grpc_cpp_plugin binary and place it in packages/libgrpc-dev/sources/usr/bin/"
		error_msg "Or extract it from a grpc source build and place it there."
		return 1
	fi
	
	info_msg "Using protoc and grpc tools from staged packages"
	
	export HOST_DIR="$HOST_DIR"
	
	# Set LD_LIBRARY_PATH so protoc can find its shared libraries
	# ONLY use ported package libraries - NO SYSTEM LIBRARIES!
	if [ -d "$TEMP_HOST_DIR/lib" ]; then
		export LD_LIBRARY_PATH="$TEMP_HOST_DIR/lib:${LD_LIBRARY_PATH:-}"
		info_msg "Set LD_LIBRARY_PATH=$LD_LIBRARY_PATH for protoc runtime libraries (ported packages only)"
	fi
	
	# Create build directory for generated files
	mkdir -p "$AML_BUILD_DIR/src"
	
	# Get include paths for dependencies
	local INCLUDES="-I./include -I. -I./src -I$AML_BUILD_DIR/src"
	
	# Add Boost headers (required for aml-audio-service)
	local BOOST_STAGING_DIR="$BUILD/staging/libboost1.83-dev"
	if [ ! -d "$BOOST_STAGING_DIR/usr/include" ]; then
		local BOOST_DEB=$(find "$BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/libboost1.83-dev" -name "*.deb" 2>/dev/null | head -1)
		if [ -n "$BOOST_DEB" ] && [ -f "$BOOST_DEB" ]; then
			info_msg "Found libboost1.83-dev package, extracting to staging..."
			mkdir -p "$BOOST_STAGING_DIR"
			if dpkg-deb -x "$BOOST_DEB" "$BOOST_STAGING_DIR" 2>/dev/null; then
				info_msg "Successfully extracted libboost1.83-dev to staging"
			fi
		fi
	fi
	if [ -d "$BOOST_STAGING_DIR/usr/include" ]; then
		INCLUDES="-I$BOOST_STAGING_DIR/usr/include $INCLUDES"
	fi
	# Also try from sources directly
	if [ -d "$PKGS_DIR/libboost1.83-dev/sources/usr/include" ]; then
		INCLUDES="-I$PKGS_DIR/libboost1.83-dev/sources/usr/include $INCLUDES"
	fi
	
	# Add staging directories for dependencies
	if [ -d "$PKGS_DIR/aml-audio-utils/sources/include" ]; then
		INCLUDES="-I$PKGS_DIR/aml-audio-utils/sources/include $INCLUDES"
	fi
	if [ -d "$PKGS_DIR/android-binder/sources/include" ]; then
		INCLUDES="-I$PKGS_DIR/android-binder/sources/include $INCLUDES"
	fi
	
	# Add gRPC headers (required for aml-audio-service)
	# NEVER use rootfs - always use packages!
	# Check for libgrpc++-dev package (provides grpcpp headers)
	local GRPCXX_STAGING_DIR="$BUILD/staging/libgrpc++-dev"
	if [ ! -d "$GRPCXX_STAGING_DIR/usr/include" ]; then
		local GRPCXX_DEB=$(find "$BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/libgrpc++-dev" -name "*.deb" 2>/dev/null | head -1)
		if [ -n "$GRPCXX_DEB" ] && [ -f "$GRPCXX_DEB" ]; then
			info_msg "Found libgrpc++-dev package, extracting to staging..."
			mkdir -p "$GRPCXX_STAGING_DIR"
			if dpkg-deb -x "$GRPCXX_DEB" "$GRPCXX_STAGING_DIR" 2>/dev/null; then
				info_msg "Successfully extracted libgrpc++-dev to staging"
			fi
		fi
	fi
	if [ -d "$GRPCXX_STAGING_DIR/usr/include" ]; then
		INCLUDES="-I$GRPCXX_STAGING_DIR/usr/include $INCLUDES"
	fi
	# Also check sources directly
	if [ -d "$PKGS_DIR/libgrpc++-dev/sources/usr/include" ]; then
		INCLUDES="-I$PKGS_DIR/libgrpc++-dev/sources/usr/include $INCLUDES"
	fi
	# Also check gRPC C headers from libgrpc-dev
	if [ -d "$GRPC_STAGING_DIR/usr/include" ]; then
		INCLUDES="-I$GRPC_STAGING_DIR/usr/include $INCLUDES"
	fi
	# Check sources directly (libgrpc-dev for C headers - grpcpp not included in libgrpc-dev)
	if [ -d "$PKGS_DIR/libgrpc-dev/sources/usr/include" ]; then
		INCLUDES="-I$PKGS_DIR/libgrpc-dev/sources/usr/include $INCLUDES"
	fi
	
	# Update Makefile CFLAGS to include all dependency paths
	# Add dependency include paths while preserving existing includes
	# Check if Boost include is already there to avoid duplicates
	local BOOST_INCLUDE_PATTERN="libboost1.83-dev"
	if ! grep -q "$BOOST_INCLUDE_PATTERN" "$PKG_BUILD_DIR/Makefile" 2>/dev/null; then
		# Append includes to the CFLAGS line
		# Use sed to append at the end of the CFLAGS line
		sed -i "/^CFLAGS +=/s|\$| $INCLUDES|" "$PKG_BUILD_DIR/Makefile" 2>/dev/null || true
	fi
	
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
	
	# NEVER use rootfs - only use packages!
	
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
	
	# Fix pattern rules - VPATH doesn't work reliably with implicit rules when using notdir
	# The Makefile uses notdir which strips src/ prefix, then tries to find files via VPATH
	# But VPATH doesn't work well with pattern rules, so we explicitly specify src/ in the rule
	# Replace the pattern rules to look in src/ directory for source files
	sed -i 's|^\$(AML_BUILD_DIR)/%.o: %.cpp|$(AML_BUILD_DIR)/%.o: src/%.cpp|' "$PKG_BUILD_DIR/Makefile" 2>/dev/null || true
	sed -i 's|^\$(AML_BUILD_DIR)/%.o: %.c|$(AML_BUILD_DIR)/%.o: src/%.c|' "$PKG_BUILD_DIR/Makefile" 2>/dev/null || true
	
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

