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
# This must be done before any make commands that might trigger globals.h regeneration
if [[ -f "globals.h" ]]; then
    if [[ ! -f "gl-stamp" ]]; then
        echo "  Creating gl-stamp to prevent globals.h regeneration..."
        touch gl-stamp
    else
        # Ensure gl-stamp is up-to-date to prevent regeneration during build
        touch gl-stamp
    fi
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

# Get base_obj list from Makefile to ensure all are included
echo "  Extracting base_obj list from Makefile..."
BASE_OBJ_LIST=$(make -f - <<'MAKEFILE_END' show_base_obj 2>/dev/null | tr ' ' '\n' | grep '\.o$' | sort
include Makefile
show_base_obj:
	@echo "$(base_obj)" | tr ' ' '\n' | grep '\.o$$'
MAKEFILE_END
)

if [[ -z "$BASE_OBJ_LIST" ]]; then
    echo "Error: Could not extract base_obj list from Makefile." >&2
    exit 1
fi

BASE_OBJ_COUNT=$(echo "$BASE_OBJ_LIST" | wc -l | tr -d ' ')
echo "  Expected base_obj files: $BASE_OBJ_COUNT"

# Check which base_obj files exist
MISSING_BASE_OBJS=()
for obj in $BASE_OBJ_LIST; do
    if [[ ! -f "$obj" ]]; then
        MISSING_BASE_OBJS+=("$obj")
    fi
done

if [[ ${#MISSING_BASE_OBJS[@]} -gt 0 ]]; then
    echo "  Warning: ${#MISSING_BASE_OBJS[@]} base_obj files are missing:" >&2
    printf "    %s\n" "${MISSING_BASE_OBJS[@]}" >&2
    echo "  Attempting to build missing files..." >&2
    # Ensure gl-stamp is up-to-date before building individual files
    # This prevents make from attempting to regenerate globals.h (which would use iOS make-docfile)
    if [[ -f "globals.h" ]]; then
        touch gl-stamp
    fi
    # Try to build missing base_obj files individually
    for obj in "${MISSING_BASE_OBJS[@]}"; do
        base="${obj%.o}"
        echo "    Building $obj..."
        make "$obj" 2>&1 | tail -5 || echo "      Failed to build $obj" >&2
    done
    # Re-check
    MISSING_BASE_OBJS=()
    for obj in $BASE_OBJ_LIST; do
        if [[ ! -f "$obj" ]]; then
            MISSING_BASE_OBJS+=("$obj")
        fi
    done
    if [[ ${#MISSING_BASE_OBJS[@]} -gt 0 ]]; then
        echo "  Error: Still missing ${#MISSING_BASE_OBJS[@]} base_obj files:" >&2
        printf "    %s\n" "${MISSING_BASE_OBJS[@]}" >&2
        echo "  Please build them manually before running this script." >&2
        exit 1
    fi
fi

# Build list of all object files to include:
# 1. All base_obj files (required)
# 2. Other .o files in the directory (optional, but include them)
OTHER_OBJS=""
for obj_file in *.o; do
    [[ ! -f "$obj_file" ]] && continue
    # Skip if it's already in base_obj
    if echo "$BASE_OBJ_LIST" | grep -q "^${obj_file}$"; then
        continue
    fi
    OTHER_OBJS="${OTHER_OBJS}${obj_file} "
done

# Combine base_obj and other objs
ALL_OBJS="$BASE_OBJ_LIST $OTHER_OBJS"
# Remove duplicates and convert to space-separated list (remove extra spaces)
ALL_OBJS=$(echo "$ALL_OBJS" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ')

OBJ_COUNT=$(echo $ALL_OBJS | wc -w | tr -d ' ')
BASE_OBJ_COUNT_INCLUDED=$(echo "$BASE_OBJ_LIST" | wc -l | tr -d ' ')
echo "  Including $BASE_OBJ_COUNT_INCLUDED base_obj files"
if [[ $OBJ_COUNT -gt $BASE_OBJ_COUNT_INCLUDED ]]; then
    OTHER_COUNT=$((OBJ_COUNT - BASE_OBJ_COUNT_INCLUDED))
    echo "  Including $OTHER_COUNT additional object files"
fi

echo "  Creating libemacs.a..."

# Create libemacs.a from all object files
ar rcs libemacs.a $ALL_OBJS 2>&1 || {
    echo "Error: Failed to create libemacs.a" >&2
    exit 1
}

# Verify that all base_obj are included
VERIFY_COUNT=$(ar -t libemacs.a 2>/dev/null | grep -v '^__' | wc -l | tr -d ' ')
if [[ $VERIFY_COUNT -lt $BASE_OBJ_COUNT_INCLUDED ]]; then
    echo "  Warning: libemacs.a contains only $VERIFY_COUNT files, expected at least $BASE_OBJ_COUNT_INCLUDED base_obj files." >&2
else
    echo "  Verified: libemacs.a contains $VERIFY_COUNT object files (including $BASE_OBJ_COUNT_INCLUDED base_obj files)"
fi

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
