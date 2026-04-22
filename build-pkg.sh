#!/bin/bash
# Usage: ./build-pkg.sh <package-name> [--skip-prepare]
# Example: ./build-pkg.sh android-binder
#          ./build-pkg.sh android-binder --skip-prepare  # Skip prepare steps (requires them already done)

set -e -o pipefail

PACKAGE_NAME="$1"
SKIP_PREPARE="$2"

if [ -z "$PACKAGE_NAME" ]; then
    echo "Usage: $0 <package-name> [--skip-prepare]"
    exit 1
fi

# Set up environment
source setenv.sh -q -s KHADAS_BOARD=TVPRO LINUX=5.15 UBOOT=2019.01 DISTRIBUTION=Ubuntu DISTRIB_RELEASE=noble DISTRIB_RELEASE_VERSION=24.04 DISTRIB_TYPE=server DISTRIB_ARCH=arm64 INSTALL_TYPE=EMMC COMPRESS_IMAGE=no

# Source build system
source config/config
source config/boards/${KHADAS_BOARD}.conf
source config/functions/functions

# Prepare build environment (unless skipped)
if [ "$SKIP_PREPARE" != "--skip-prepare" ]; then
    echo "Preparing build environment (may require sudo)..."
    prepare_host || {
        echo "Warning: prepare_host failed. If dependencies are already installed,"
        echo "you can skip this step by running: $0 $PACKAGE_NAME --skip-prepare"
        exit 1
    }
    prepare_toolchains
    prepare_packages
else
    echo "Skipping prepare steps (assuming already done)..."
fi

# Build the package
echo "Building package: $PACKAGE_NAME"
build_package "${PACKAGE_NAME}:target"

echo ""
echo "Package built successfully!"
echo "Output: $BUILD_IMAGES/debs/$VERSION/$KHADAS_BOARD/${DISTRIBUTION}-${DISTRIB_RELEASE}/${PACKAGE_NAME}/"

