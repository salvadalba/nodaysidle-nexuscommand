#!/usr/bin/env bash
set -euo pipefail

# Build a signed DMG for NexusCommand distribution.
# Usage: Scripts/build-dmg.sh [release|debug]
# Requires: create-dmg (brew install create-dmg) or hdiutil

CONF=${1:-release}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

APP_NAME="NexusCommand"
DMG_NAME="${APP_NAME}.dmg"
APP_BUNDLE="${ROOT}/${APP_NAME}.app"
DMG_DIR="${ROOT}/.build/dmg"
DMG_OUTPUT="${ROOT}/${DMG_NAME}"
SIGNING_IDENTITY=${APP_IDENTITY:-}

# Ensure app bundle exists
if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "ERROR: ${APP_BUNDLE} not found. Run Scripts/package_app.sh first."
    exit 1
fi

# Clean staging
rm -rf "$DMG_DIR" "$DMG_OUTPUT"
mkdir -p "$DMG_DIR"

# Copy app and create Applications symlink
cp -R "$APP_BUNDLE" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

# Create DMG with hdiutil
TEMP_DMG="${ROOT}/.build/${APP_NAME}_temp.dmg"
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDZO \
    "$TEMP_DMG"

mv "$TEMP_DMG" "$DMG_OUTPUT"

# Sign the DMG if identity is available
if [[ -n "$SIGNING_IDENTITY" ]]; then
    echo "Signing DMG with identity: $SIGNING_IDENTITY"
    codesign --force --sign "$SIGNING_IDENTITY" "$DMG_OUTPUT"

    # Notarize if credentials available
    if [[ -n "${APPLE_ID:-}" && -n "${TEAM_ID:-}" ]]; then
        echo "Submitting DMG for notarization..."
        xcrun notarytool submit "$DMG_OUTPUT" \
            --apple-id "$APPLE_ID" \
            --team-id "$TEAM_ID" \
            --keychain-profile "notarization" \
            --wait

        echo "Stapling notarization ticket..."
        xcrun stapler staple "$DMG_OUTPUT"
    fi
fi

# Verify
DMG_SIZE=$(du -h "$DMG_OUTPUT" | cut -f1)
echo ""
echo "=== DMG Created ==="
echo "  Path: $DMG_OUTPUT"
echo "  Size: $DMG_SIZE"
echo ""

# Verify signature if signed
if [[ -n "$SIGNING_IDENTITY" ]]; then
    codesign --verify --verbose "$DMG_OUTPUT" && echo "  Signature: Valid" || echo "  Signature: INVALID"
    spctl --assess --type open --context context:primary-signature "$DMG_OUTPUT" 2>&1 && echo "  Gatekeeper: Accepted" || echo "  Gatekeeper: Check failed (may need notarization)"
fi

echo "Done."
