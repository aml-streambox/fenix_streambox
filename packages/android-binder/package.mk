PKG_NAME="android-binder"
PKG_VERSION="amlogic-yocto-1.0"
PKG_SHA256=""
PKG_SOURCE_DIR=""
PKG_SITE=""
PKG_URL=""
PKG_ARCH="arm aarch64"
PKG_LICENSE="Apache-2.0"
PKG_SHORTDESC="Android Binder IPC Framework (Amlogic version)"

PKG_NEED_BUILD="YES"

make_target() {
	local pkgdir="$BUILD_IMAGES/.tmp/${PKG_NAME}_${VERSION}_${DISTRIB_ARCH}"
	rm -rf $pkgdir
	mkdir -p $pkgdir/DEBIAN
	mkdir -p $pkgdir/usr/lib
	mkdir -p $pkgdir/usr/bin
	mkdir -p $pkgdir/usr/include/binder
	mkdir -p $pkgdir/usr/include/utils
	mkdir -p $pkgdir/lib/systemd/system
	mkdir -p $pkgdir/etc/init.d

	# Set up control file
	cat <<-EOF > $pkgdir/DEBIAN/control
Package: ${PKG_NAME}
Version: ${VERSION}
Architecture: ${DISTRIB_ARCH}
Maintainer: Khadas <hello@khadas.com>
Depends: systemd
Section: libs
Priority: optional
Description: Android Binder IPC Framework
 ${PKG_SHORTDESC}
 Amlogic version with Makefile build system.
 Provides libbinder.so, servicemanager, and systemd services.
EOF

	# Build the package using the Makefile in the source
	# PKG_BUILD is set by build_package function: BUILD/${PKG_NAME}-${PKG_VERSION}
	local PKG_BUILD_DIR="${BUILD}/${PKG_NAME}-${PKG_VERSION}"
	cd "$PKG_BUILD_DIR"
	if [ ! -f Makefile ]; then
		error_msg "Makefile not found in $PKG_BUILD_DIR"
		error_msg "Contents of $PKG_BUILD_DIR:"
		ls -la "$PKG_BUILD_DIR" || true
		return 1
	fi

	# Set build environment variables as expected by the Makefile
	export OUT_DIR="$PKG_BUILD_DIR"
	export STAGING_DIR="$PKG_BUILD_DIR/staging"
	export TARGET_DIR="$pkgdir"
	export STRIP="${CROSS_COMPILE}strip"

	# Create staging directory
	mkdir -p "$STAGING_DIR/usr/lib"
	mkdir -p "$STAGING_DIR/usr/bin"
	mkdir -p "$STAGING_DIR/usr/include/binder"
	mkdir -p "$STAGING_DIR/usr/include/utils"

	# Create output directories for object files (required by Makefile)
	mkdir -p "$OUT_DIR/binder" "$OUT_DIR/utils" "$OUT_DIR/cutils" "$OUT_DIR/servicemgr"

	# Ensure kernel binder headers are accessible
	# The Makefile includes from STAGING_DIR/usr/include, so we need to set up kernel headers
	# or ensure system headers are accessible via -I flags (Makefile handles this)

	# Build libbinder.so and servicemanager
	info_msg "Building ${PKG_NAME}..."
	make clean 2>/dev/null || true
	make all || {
		error_msg "Build failed"
		return 1
	}

	# Install libraries
	if [ -f "$OUT_DIR/libbinder.so" ]; then
		install -m 644 "$OUT_DIR/libbinder.so" "${pkgdir}/usr/lib/"
		${STRIP} "${pkgdir}/usr/lib/libbinder.so" 2>/dev/null || true
	else
		error_msg "libbinder.so not found after build"
		return 1
	fi

	# Install servicemanager binary
	if [ -f "$OUT_DIR/servicemanager" ]; then
		install -m 755 "$OUT_DIR/servicemanager" "${pkgdir}/usr/bin/"
		${STRIP} "${pkgdir}/usr/bin/servicemanager" 2>/dev/null || true
	else
		error_msg "servicemanager not found after build"
		return 1
	fi

	# Install headers
	if [ -d "$PKG_BUILD_DIR/include/binder" ]; then
		install -m 644 "$PKG_BUILD_DIR/include/binder"/* "${pkgdir}/usr/include/binder/" 2>/dev/null || true
	fi
	if [ -d "$PKG_BUILD_DIR/include/utils" ]; then
		install -m 644 "$PKG_BUILD_DIR/include/utils"/* "${pkgdir}/usr/include/utils/" 2>/dev/null || true
	fi

	# Install systemd service files
	if [ -f "$PKG_DIR/files/binder.service" ]; then
		install -m 644 "$PKG_DIR/files/binder.service" "${pkgdir}/lib/systemd/system/"
	fi
	if [ -f "$PKG_DIR/files/dev-binderfs.mount" ]; then
		install -m 644 "$PKG_DIR/files/dev-binderfs.mount" "${pkgdir}/lib/systemd/system/"
	fi

	# Install binder.sh setup script
	if [ -f "$PKG_DIR/files/binder.sh" ]; then
		install -m 755 "$PKG_DIR/files/binder.sh" "${pkgdir}/usr/bin/"
	fi

	# Install init.d script (for sysvinit compatibility)
	if [ -f "$PKG_DIR/files/binder.init" ]; then
		install -m 755 "$PKG_DIR/files/binder.init" "${pkgdir}/etc/init.d/binder"
	fi

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
