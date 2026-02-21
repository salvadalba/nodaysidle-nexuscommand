#!/usr/bin/env bash
set -euo pipefail

# Dev loop: build, package, and run NexusCommand.
# Usage: Scripts/compile_and_run.sh [debug|release]

CONF=${1:-debug}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP_NAME="NexusCommand"

# Kill existing instance
pkill -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
sleep 0.5

# Package
SIGNING_MODE=adhoc "$ROOT/Scripts/package_app.sh" "$CONF"

# Launch
echo "Launching ${APP_NAME}..."
open "$ROOT/${APP_NAME}.app"
