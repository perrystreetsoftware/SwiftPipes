#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/SwiftPipes.app" >&2
  exit 1
fi

APP_PATH="$1"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: '$APP_PATH' not found or is not a directory." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$SCRIPT_DIR/SwiftPipes.xcodeproj"

VERSION=$(xcodebuild -project "$PROJECT" -scheme SwiftPipes -showBuildSettings 2>/dev/null \
  | awk '/MARKETING_VERSION =/ { print $3; exit }')

if [[ -z "$VERSION" ]]; then
  echo "Error: Could not read MARKETING_VERSION from project." >&2
  exit 1
fi

DMG_NAME="SwiftPipes-${VERSION}.dmg"

echo "Building $DMG_NAME from $APP_PATH..."

create-dmg \
  --volname "SwiftPipes" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "SwiftPipes.app" 150 185 \
  --hide-extension "SwiftPipes.app" \
  --app-drop-link 450 185 \
  "$DMG_NAME" \
  "$APP_PATH"

echo "Done: $DMG_NAME"
