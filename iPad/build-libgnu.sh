#!/bin/bash
# Build script for libgnu.a for iPadOS/iOS
#
# Usage:
#   ./build-libgnu.sh [--debug] [--install]
#
# Options:
#   --debug    Build with debug symbols (-g flag)
#   --install  Install libgnu.a and headers to iPad/Sample/libgnu/
#
# Output:
#   libgnu.a will be created in GnuEmacs/lib/
#   If --install is specified, files will be copied to iPad/Sample/libgnu/

set -e

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GNUEMACS_DIR="$REPO_ROOT/GnuEmacs"
PATCH_FILE="$SCRIPT_DIR/patches/configure-ac-ios-support.patch"

# Check options
DEBUG_BUILD=false
INSTALL=false
for arg in "$@"; do
    case "$arg" in
        --debug)
            DEBUG_BUILD=true
            ;;
        --install)
            INSTALL=true
            ;;
    esac
done

# Check if GnuEmacs directory exists
if [[ ! -d "$GNUEMACS_DIR" ]]; then
    echo "Error: GnuEmacs directory not found at $GNUEMACS_DIR" >&2
    exit 1
fi

# Check if patch file exists
if [[ ! -f "$PATCH_FILE" ]]; then
    echo "Error: Patch file not found at $PATCH_FILE" >&2
    exit 1
fi

# Get iOS SDK path
SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)
if [[ -z "$SDK_PATH" ]]; then
    echo "Error: iOS SDK not found. Make sure Xcode is installed." >&2
    exit 1
fi

echo "Building libgnu.a for iPadOS/iOS"
echo "SDK Path: $SDK_PATH"
if [[ "$DEBUG_BUILD" == "true" ]]; then
    echo "Build type: Debug (with debug symbols)"
else
    echo "Build type: Release (optimized)"
fi
echo ""

# Change to GnuEmacs directory
cd "$GNUEMACS_DIR"

# Apply patch if not already applied
if ! git apply --check "$PATCH_FILE" 2>/dev/null; then
    echo "Patch already applied or patch check failed, attempting to apply..."
fi
git apply "$PATCH_FILE" 2>/dev/null || true

# Clean previous build
echo "Cleaning previous build..."
make distclean 2>/dev/null || true

# Prepare CFLAGS
CFLAGS_BASE="-arch arm64 -isysroot $SDK_PATH -target arm64-apple-ios -miphoneos-version-min=18.5"

if [[ "$DEBUG_BUILD" == "true" ]]; then
    # Debug build: no optimization, with debug symbols
    CFLAGS="$CFLAGS_BASE -O0 -g"
else
    # Release build: optimized (default optimization level from configure)
    CFLAGS="$CFLAGS_BASE"
fi

# Run configure
echo "Running configure..."
./configure \
    --host=aarch64-apple-ios \
    --without-ns \
    CC=clang \
    CFLAGS="$CFLAGS" \
    LDFLAGS="-arch arm64 -isysroot $SDK_PATH -miphoneos-version-min=18.5"

# Build libgnu.a
echo "Building libgnu.a..."
cd lib
make libgnu.a

# Verify the build
echo ""
echo "Verifying build..."
file libgnu.a
ls -lh libgnu.a

# Check build version
echo ""
echo "Checking build version..."
ar -x libgnu.a md5.o 2>/dev/null
otool -l md5.o | grep -A 5 "LC_BUILD_VERSION" || true
rm -f md5.o

echo ""
echo "Build complete! libgnu.a is located at:"
echo "$(pwd)/libgnu.a"

# Install step
if [[ "$INSTALL" == "true" ]]; then
    echo ""
    echo "Installing libgnu.a and headers to iPad/Sample/libgnu/..."
    
    INSTALL_DIR="$REPO_ROOT/iPad/Sample/libgnu"
    INSTALL_INCLUDE_DIR="$INSTALL_DIR/include"
    
    # Create directories if they don't exist
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$INSTALL_INCLUDE_DIR"
    
    # Copy libgnu.a
    cp -f "$(pwd)/libgnu.a" "$INSTALL_DIR/libgnu.a"
    echo "  Copied libgnu.a -> $INSTALL_DIR/libgnu.a"
    
    # Copy header files that are commonly needed
    # These are the headers currently in iPad/Sample/libgnu/include/
    # Note: We copy from the lib directory where they are generated
    HEADER_FILES=(
        "md5.h"
        "sha1.h"
        "sha256.h"
        "sha512.h"
        "stdbit.h"
        "stdckdint.h"
        "stdint.h"
        "limits.h"
        "intprops-internal.h"
        "timespec.h"
        "arg-nonnull.h"
    )
    
    LIB_DIR="$(pwd)"
    GNUEMACS_LIB_DIR="$GNUEMACS_DIR/lib"
    
    for header in "${HEADER_FILES[@]}"; do
        # Try multiple locations where headers might be
        SOURCE_FILE=""
        if [[ -f "$LIB_DIR/$header" ]]; then
            SOURCE_FILE="$LIB_DIR/$header"
        elif [[ -f "$LIB_DIR/include/$header" ]]; then
            SOURCE_FILE="$LIB_DIR/include/$header"
        elif [[ -f "$GNUEMACS_LIB_DIR/$header" ]]; then
            SOURCE_FILE="$GNUEMACS_LIB_DIR/$header"
        elif [[ -f "$GNUEMACS_LIB_DIR/include/$header" ]]; then
            SOURCE_FILE="$GNUEMACS_LIB_DIR/include/$header"
        fi
        
        if [[ -n "$SOURCE_FILE" ]]; then
            cp -f "$SOURCE_FILE" "$INSTALL_INCLUDE_DIR/$header"
            echo "  Copied $header -> $INSTALL_INCLUDE_DIR/$header"
        else
            echo "  Warning: $header not found (searched in $LIB_DIR, $LIB_DIR/include, $GNUEMACS_LIB_DIR, $GNUEMACS_LIB_DIR/include)"
        fi
    done
    
    echo ""
    echo "Installation complete!"
    echo "  Library: $INSTALL_DIR/libgnu.a"
    echo "  Headers: $INSTALL_INCLUDE_DIR/"
fi
