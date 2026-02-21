#!/usr/bin/env bash
set -euo pipefail

# Package NexusCommand as a .app bundle from SwiftPM build.
# Adapted from macos-spm-app-packaging template.

CONF=${1:-release}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

APP_NAME="NexusCommand"
BUNDLE_ID="com.nexuscommand"
MACOS_MIN_VERSION="15.0"
MENU_BAR_APP="1"
SIGNING_MODE=${SIGNING_MODE:-adhoc}
APP_IDENTITY=${APP_IDENTITY:-}

if [[ -f "$ROOT/version.env" ]]; then
    source "$ROOT/version.env"
else
    MARKETING_VERSION=${MARKETING_VERSION:-1.0.0}
    BUILD_NUMBER=${BUILD_NUMBER:-1}
fi

ARCH_LIST=(${ARCHES:-$(uname -m)})

# Build
for ARCH in "${ARCH_LIST[@]}"; do
    echo "Building for $ARCH ($CONF)..."
    swift build -c "$CONF" --arch "$ARCH"
done

# Create app bundle
APP="$ROOT/${APP_NAME}.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Info.plist
LSUI_VALUE="false"
[[ "$MENU_BAR_APP" == "1" ]] && LSUI_VALUE="true"

BUILD_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>Nexus Command</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>${MACOS_MIN_VERSION}</string>
    <key>LSUIElement</key><${LSUI_VALUE}/>
    <key>CFBundleIconFile</key><string>Icon</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>BuildTimestamp</key><string>${BUILD_TIMESTAMP}</string>
    <key>GitCommit</key><string>${GIT_COMMIT}</string>
</dict>
</plist>
PLIST

# Copy binary
build_product_path() {
    local name="$1" arch="$2"
    echo ".build/${arch}-apple-macosx/$CONF/$name"
}

if [[ ${#ARCH_LIST[@]} -gt 1 ]]; then
    BINS=()
    for ARCH in "${ARCH_LIST[@]}"; do
        BINS+=("$(build_product_path "$APP_NAME" "$ARCH")")
    done
    lipo -create "${BINS[@]}" -output "$APP/Contents/MacOS/$APP_NAME"
else
    cp "$(build_product_path "$APP_NAME" "${ARCH_LIST[0]}")" "$APP/Contents/MacOS/$APP_NAME"
fi
chmod +x "$APP/Contents/MacOS/$APP_NAME"

# Copy icon
if [[ -f "$ROOT/Sources/$APP_NAME/Resources/Icon.icns" ]]; then
    cp "$ROOT/Sources/$APP_NAME/Resources/Icon.icns" "$APP/Contents/Resources/Icon.icns"
fi

# Copy SwiftPM resource bundles (including compiled metal libs)
PREFERRED_BUILD_DIR="$(dirname "$(build_product_path "$APP_NAME" "${ARCH_LIST[0]}")")"
shopt -s nullglob
SWIFTPM_BUNDLES=("${PREFERRED_BUILD_DIR}/"*.bundle)
shopt -u nullglob
if [[ ${#SWIFTPM_BUNDLES[@]} -gt 0 ]]; then
    for bundle in "${SWIFTPM_BUNDLES[@]}"; do
        cp -R "$bundle" "$APP/Contents/Resources/"
    done
fi

# Copy Metal library if present
METALLIB="${PREFERRED_BUILD_DIR}/default.metallib"
if [[ -f "$METALLIB" ]]; then
    cp "$METALLIB" "$APP/Contents/Resources/"
fi

# Clean extended attributes
chmod -R u+w "$APP"
xattr -cr "$APP"
find "$APP" -name '._*' -delete

# Entitlements
APP_ENTITLEMENTS="$ROOT/NexusCommand.entitlements"
if [[ ! -f "$APP_ENTITLEMENTS" ]]; then
    APP_ENTITLEMENTS="$ROOT/.build/entitlements/${APP_NAME}.entitlements"
    mkdir -p "$(dirname "$APP_ENTITLEMENTS")"
    cat > "$APP_ENTITLEMENTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict></dict></plist>
PLIST
fi

# Sign
if [[ "$SIGNING_MODE" == "adhoc" || -z "$APP_IDENTITY" ]]; then
    codesign --force --sign "-" --entitlements "$APP_ENTITLEMENTS" "$APP"
else
    codesign --force --timestamp --options runtime --sign "$APP_IDENTITY" --entitlements "$APP_ENTITLEMENTS" "$APP"
fi

echo "Created $APP"
