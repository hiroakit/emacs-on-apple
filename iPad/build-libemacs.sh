#!/bin/bash
#
# Build libemacs.a for iPadOS/iOS
# This creates a static library containing Emacs core object files
# that can be linked into an iOS app.
#
# Prerequisites:
#   - globals.h must exist (run './iPad/build-host-tools.sh --globals' first)
#   - libgnu.a must be built for iOS (run './iPad/build-libgnu.sh' first)
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GNUEMACS_DIR="$PROJECT_DIR/GnuEmacs"
SRC_DIR="$GNUEMACS_DIR/src"

cd "$SRC_DIR"

# Check if globals.h exists
if [[ ! -f "globals.h" ]]; then
    echo "Error: globals.h not found." >&2
    echo "Please run: ./iPad/build-host-tools.sh --globals" >&2
    exit 1
fi

# Check if libgnu.a exists
if [[ ! -f "../lib/libgnu.a" ]]; then
    echo "Error: libgnu.a not found." >&2
    echo "Please run: ./iPad/build-libgnu.sh" >&2
    exit 1
fi

# Prevent globals.h from being regenerated (which would use iOS make-docfile)
# Touch gl-stamp to mark globals.h as up-to-date
if [[ -f "globals.h" ]] && [[ ! -f "gl-stamp" ]]; then
    echo "  Creating gl-stamp to prevent globals.h regeneration..."
    touch gl-stamp
fi

# Get number of CPU cores (fallback to 4 if sysctl fails)
NPROC=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo "4")

echo "Building Emacs object files..."

# Strategy: Use make to build object files by leveraging its dependency system
# We'll build object files needed for temacs, but stop before linking
echo "  Building core object files (base_obj)..."

# Use make's variable expansion to get the actual list
# Build base_obj by asking make to build the files it needs
echo "  Building base_obj files (this may take a while)..."
set +e
# Try to build base_obj files by using a dummy target that depends on them
make -j"$NPROC" -f - <<'MAKEFILE' base_obj_files 2>&1 | grep -E "(CC|Building|Error|error)" | tail -30 || true
include Makefile
base_obj_files: $(base_obj)
	@echo "Built base_obj files"
MAKEFILE
set -e

# Build remaining ALLOBJS (otherobj, etc.)
echo "  Building remaining object files (ALLOBJS)..."
set +e
# Build ALLOBJS by creating a dummy target
make -j"$NPROC" -f - <<'MAKEFILE' all_obj_files 2>&1 | grep -E "(CC|Building|Error|error|undefined)" | tail -30 || true
include Makefile
all_obj_files: $(ALLOBJS)
	@echo "Built ALLOBJS files"
MAKEFILE
set -e

echo ""
echo "Creating libemacs.a static library..."

# Extract the actual object files that were built
# Look for .o files in the current directory
BUILT_OBJS=$(find . -maxdepth 1 -name "*.o" -type f | sort | tr '\n' ' ')

if [[ -z "$BUILT_OBJS" ]]; then
    echo "Error: No .o files found. Build may have failed." >&2
    echo ""
    echo "Troubleshooting:" >&2
    echo "  1. Check if globals.h exists and is valid" >&2
    echo "  2. Check if libgnu.a exists" >&2
    echo "  3. Try building a single object file manually:" >&2
    echo "     cd $SRC_DIR && make dispnew.o" >&2
    exit 1
fi

OBJ_COUNT=$(echo $BUILT_OBJS | wc -w | tr -d ' ')
echo "  Found $OBJ_COUNT object files"

if [[ $OBJ_COUNT -lt 20 ]]; then
    echo "  Warning: Only $OBJ_COUNT object files found. Expected more." >&2
    echo "  Some files may have failed to build (check errors above)." >&2
    echo "  Continuing anyway..." >&2
fi

echo "  Creating libemacs.a..."

# Create libemacs.a from all built object files
ar rcs libemacs.a $BUILT_OBJS 2>&1 || {
    echo "Error: Failed to create libemacs.a" >&2
    exit 1
}

# Also include libgnu.a's contents if needed (or link it separately)
echo "  Created libemacs.a"
echo ""
echo "Success! libemacs.a has been created."
echo "  Location: $SRC_DIR/libemacs.a"
echo "  Size: $(ls -lh libemacs.a | awk '{print $5}')"
echo ""
echo "Note: You'll also need to link libgnu.a separately:"
echo "  Location: $GNUEMACS_DIR/lib/libgnu.a"
echo ""
echo "Next steps:"
echo "  1. Link both libemacs.a and lib/libgnu.a into your iOS app"
echo "  2. Provide Emacs initialization code (loadup.el, etc.)"
echo "  3. Implement iOS-specific entry point (don't run temacs directly)"
