#!/bin/bash
# Quick build script for individual packages
# Usage: ./quick-build-pkg.sh <package-name>
# Example: ./quick-build-pkg.sh android-binder
#          ./quick-build-pkg.sh aml-tvserver-streambox
#
# This script uses the same environment variables as 'make debs' but only builds
# the specified package without building u-boot, kernel, or other packages.

set -e -o pipefail

PACKAGE_NAME="$1"

if [ -z "$PACKAGE_NAME" ]; then
    echo "Usage: $0 <package-name>"
    echo ""
    echo "Examples:"
    echo "  $0 android-binder"
    echo "  $0 aml-audio-utils"
    echo "  $0 aml-tvserver-streambox"
    exit 1
fi

# Check if environment is already set up
if [ -z "$DISTRIBUTION" ] || [ -z "$DISTRIB_RELEASE" ] || [ -z "$KHADAS_BOARD" ]; then
    echo "Setting up environment (same as 'make debs')..."
    # Use the same environment setup as make debs
    source setenv.sh -q -s KHADAS_BOARD=TVPRO LINUX=5.15 UBOOT=2019.01 DISTRIBUTION=Ubuntu DISTRIB_RELEASE=noble DISTRIB_RELEASE_VERSION=24.04 DISTRIB_TYPE=server DISTRIB_ARCH=arm64 INSTALL_TYPE=EMMC COMPRESS_IMAGE=no
else
    echo "Using existing environment:"
    echo "  KHADAS_BOARD=$KHADAS_BOARD"
    echo "  DISTRIBUTION=$DISTRIBUTION"
    echo "  DISTRIB_RELEASE=$DISTRIB_RELEASE"
    echo "  DISTRIB_ARCH=$DISTRIB_ARCH"
fi

# Source build system (same as make debs)
source config/config
source config/boards/${KHADAS_BOARD}.conf
source config/functions/functions

# Check if package exists
if [ ! -f "$PKGS_DIR/$PACKAGE_NAME/package.mk" ]; then
    error_msg "Package '$PACKAGE_NAME' not found!"
    error_msg "Expected package.mk at: $PKGS_DIR/$PACKAGE_NAME/package.mk"
    exit 1
fi

# Prepare build environment (only if not already done)
# Check if toolchains are prepared by checking for a common toolchain directory
if [ ! -d "$BUILD/gcc-linaro-aarch64-linux-gnu-7.3.1-2018.05" ] && \
   [ ! -d "$BUILD/gcc-arm-aarch64-none-linux-gnu-12.2.rel1" ] && \
   [ ! -d "$BUILD/gcc-arm-aarch64-none-linux-gnu-mainline-12.2.rel1" ]; then
    echo "Preparing build environment (this may take a while on first run)..."
    prepare_host
    prepare_toolchains
    prepare_packages
else
    echo "Build environment already prepared, skipping prepare steps..."
    # Still need to prepare packages to ensure package list is loaded
    prepare_packages
fi

# Build the package
echo ""
echo "=========================================="
echo "Building package: $PACKAGE_NAME"
echo "=========================================="
echo ""

build_package "${PACKAGE_NAME}:target"

echo ""
echo "=========================================="
echo "Package built successfully!"
echo "=========================================="
echo ""
echo "Output location:"
echo "  $BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/${PACKAGE_NAME}/"
echo ""
echo "To view the .deb file:"
echo "  ls -lh $BUILD_DEBS/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/${PACKAGE_NAME}/*.deb"
echo ""

