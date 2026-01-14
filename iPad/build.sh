#!/bin/bash
# Build script for Sample iPad app
# Usage:
#   ./build.sh clean     - Clean the build
#   ./build.sh build     - Build the project
#   ./build.sh rebuild   - Clean and build (recommended)
#   ./build.sh run       - Build and run on connected iPad device
#   ./build.sh           - Build the project (default)

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_FILE="${PROJECT_DIR}/Sample/Sample.xcodeproj"
SCHEME="Sample"
SDK="iphoneos"
CONFIGURATION="Debug"
ARCH="arm64"

ACTION="${1:-build}"

do_clean() {
    echo "Cleaning build..."
    xcodebuild \
        -project "${PROJECT_FILE}" \
        -scheme "${SCHEME}" \
        -configuration "${CONFIGURATION}" \
        -sdk "${SDK}" \
        -destination "generic/platform=iOS" \
        clean
    echo "Clean completed."
}

do_build() {
    echo "Building for ${SDK}..."
    xcodebuild \
        -project "${PROJECT_FILE}" \
        -scheme "${SCHEME}" \
        -configuration "${CONFIGURATION}" \
        -sdk "${SDK}" \
        -destination "generic/platform=iOS" \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        build
    echo "Build completed."
}

# Find connected iOS device (iPad)
find_connected_device() {
    local device_id
    
    # Use xcrun xctrace list devices (compatible with xcodebuild)
    # Look for iPad devices in the Devices section, exclude simulators
    local devices
    devices=$(xcrun xctrace list devices 2>/dev/null | awk '/^== Devices ==/ {flag=1; next} /^== / && flag {flag=0} flag' | grep -i "iPad" | grep -v "Simulator" || true)
    
    if [ -n "$devices" ]; then
        # Extract device ID (UUID format: 00008120-000524281A080032)
        # Format: "iPad (26.1) (00008120-000524281A080032)"
        # Extract the UUID from parentheses at the end of the line
        device_id=$(echo "$devices" | head -1 | grep -oE '\([0-9A-Fa-f-]+\)' | tail -1 | tr -d '()')
    fi
    
    if [ -z "$device_id" ]; then
        return 1
    fi
    
    echo "$device_id"
}

# Get devicectl identifier from UDID (or return as-is if already an identifier)
get_devicectl_identifier() {
    local device_id="$1"
    
    # Try to get device info using the provided ID
    # This will work with both UDID and devicectl identifier
    local info_output
    info_output=$(xcrun devicectl device info details --device "$device_id" --json-output /tmp/devicectl_info.json 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -f /tmp/devicectl_info.json ]; then
        # Extract identifier from JSON (devicectl identifier, not UDID)
        local identifier
        identifier=$(python3 -c "import json; data = json.load(open('/tmp/devicectl_info.json')); print(data['result']['identifier'])" 2>/dev/null)
        if [ -n "$identifier" ]; then
            echo "$identifier"
            return 0
        fi
    fi
    
    # If we can't get the identifier, return the original ID
    echo "$device_id"
}

do_run() {
    local device_id="$2"  # Optional device ID argument
    local xcode_device_id  # Device ID for xcodebuild (UDID format)
    local devicectl_device_id  # Device ID for devicectl (identifier format)
    
    if [ -n "$device_id" ]; then
        # Device ID provided as argument
        echo "Using provided device ID: ${device_id}"
        xcode_device_id="$device_id"
        devicectl_device_id=$(get_devicectl_identifier "$device_id")
    else
        # Auto-detect device
        echo "Checking for connected iPad device..."
        xcode_device_id=$(find_connected_device)
        
        if [ -z "$xcode_device_id" ]; then
            echo "Error: No connected iPad device found."
            echo "Please connect an iPad device and ensure it is trusted,"
            echo "or provide a device ID as an argument: ./build.sh run <device_id>"
            exit 1
        fi
        
        echo "Found iPad device: ${xcode_device_id}"
        devicectl_device_id=$(get_devicectl_identifier "$xcode_device_id")
    fi
    
    echo "Building for device (xcodebuild uses: ${xcode_device_id})..."
    echo "Note: Xcode will use automatic code signing (configured in project settings)."
    
    # Build for the connected device
    # Note: Code signing is handled automatically by Xcode's Automatic Signing
    # The project is configured with CODE_SIGN_STYLE = Automatic and DEVELOPMENT_TEAM
    # Xcode will use the Apple Development certificate and provisioning profile
    xcodebuild \
        -project "${PROJECT_FILE}" \
        -scheme "${SCHEME}" \
        -configuration "${CONFIGURATION}" \
        -sdk "${SDK}" \
        -destination "id=${xcode_device_id}" \
        build
    
    if [ $? -ne 0 ]; then
        echo "Build failed."
        exit 1
    fi
    
    echo "Build succeeded. Installing on device (devicectl uses: ${devicectl_device_id})..."
    
    # Get the path to the built app
    local built_app_path
    built_app_path=$(xcodebuild -project "${PROJECT_FILE}" -scheme "${SCHEME}" -configuration "${CONFIGURATION}" -sdk "${SDK}" -destination "id=${xcode_device_id}" -showBuildSettings 2>/dev/null | grep "BUILT_PRODUCTS_DIR" | head -1 | sed 's/.*= *//')
    
    if [ -z "$built_app_path" ]; then
        echo "Error: Could not determine built app path."
        exit 1
    fi
    
    local app_bundle="${built_app_path}/${SCHEME}.app"
    
    if [ ! -d "$app_bundle" ]; then
        echo "Error: App bundle not found at ${app_bundle}"
        exit 1
    fi
    
    echo "Installing ${app_bundle} on device..."
    xcrun devicectl device install app --device "${devicectl_device_id}" "${app_bundle}"
    
    if [ $? -ne 0 ]; then
        echo "Installation failed."
        exit 1
    fi
    
    echo "Installation completed successfully."
    
    # Get bundle identifier for launching the app
    # Use exact match pattern to avoid matching DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER
    local bundle_id
    bundle_id=$(xcodebuild -project "${PROJECT_FILE}" -scheme "${SCHEME}" -configuration "${CONFIGURATION}" -sdk "${SDK}" -destination "id=${xcode_device_id}" -showBuildSettings 2>/dev/null | grep "^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER[[:space:]]*=" | head -1 | sed 's/.*=[[:space:]]*//' | xargs)
    
    if [ -z "$bundle_id" ]; then
        echo "Warning: Could not determine bundle identifier. App installed but not launched."
        echo "The app should now be installed on your iPad."
        return 0
    fi
    
    echo "Launching app (bundle ID: ${bundle_id})..."
    xcrun devicectl device process launch --device "${devicectl_device_id}" "${bundle_id}" 2>&1
    
    if [ $? -eq 0 ]; then
        echo "App launched successfully."
    else
        echo "Warning: App installed but launch failed. You can launch it manually from your iPad."
    fi
}

case "${ACTION}" in
    clean)
        do_clean
        ;;
    build)
        do_build
        ;;
    rebuild)
        do_clean
        do_build
        ;;
    run)
        do_run
        ;;
    *)
        echo "Usage: $0 [clean|build|rebuild|run [device_id]]"
        echo "  clean   - Clean the build"
        echo "  build   - Build the project (default)"
        echo "  rebuild - Clean and build (recommended)"
        echo "  run [device_id] - Build and run on connected iPad device"
        echo "                    (device_id is optional: UDID or devicectl identifier)"
        exit 1
        ;;
esac
