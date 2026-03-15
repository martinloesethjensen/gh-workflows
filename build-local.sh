#!/usr/bin/env bash
# build-local.sh — build an unsigned iOS IPA and/or a macOS DMG locally
# Usage: ./build-local.sh [options]
#
# Options:
#   -s, --scheme      Xcode scheme (required)
#   -b, --bundle-id   Bundle identifier (required)
#   -n, --name        App name used in output filenames (required)
#   -v, --version     Version string, e.g. 1.2.0 (default: reads from xcodebuild)
#   -o, --output      Output directory (default: ./build-output)
#       --ios         Build iOS IPA only
#       --macos       Build macOS DMG only
#       --min-ios     Minimum iOS version (default: 16.0)
#   -h, --help        Show this help

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
SCHEME=""
BUNDLE_ID=""
APP_NAME=""
VERSION=""
OUTPUT_DIR="./build-output"
BUILD_IOS=true
BUILD_MACOS=true
MIN_IOS="16.0"

# ── Argument parsing ──────────────────────────────────────────────────────────
usage() {
  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--scheme)     SCHEME="$2";     shift 2 ;;
    -b|--bundle-id)  BUNDLE_ID="$2";  shift 2 ;;
    -n|--name)       APP_NAME="$2";   shift 2 ;;
    -v|--version)    VERSION="$2";    shift 2 ;;
    -o|--output)     OUTPUT_DIR="$2"; shift 2 ;;
    --ios)           BUILD_IOS=true;  BUILD_MACOS=false; shift ;;
    --macos)         BUILD_IOS=false; BUILD_MACOS=true;  shift ;;
    --min-ios)       MIN_IOS="$2";    shift 2 ;;
    -h|--help)       usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# ── Validation ────────────────────────────────────────────────────────────────
errors=0
for var in SCHEME BUNDLE_ID APP_NAME; do
  if [[ -z "${!var}" ]]; then
    echo "Error: --$(echo "$var" | tr '[:upper:]' '[:lower:]' | tr '_' '-') is required"
    errors=$((errors + 1))
  fi
done
[[ $errors -gt 0 ]] && exit 1

# ── Resolve version ───────────────────────────────────────────────────────────
if [[ -z "$VERSION" ]]; then
  VERSION=$(xcodebuild -scheme "$SCHEME" -showBuildSettings 2>/dev/null \
    | awk '/^\s*MARKETING_VERSION =/ { print $3; exit }')
  if [[ -z "$VERSION" ]]; then
    echo "Error: could not read MARKETING_VERSION from project. Pass -v <version> explicitly."
    exit 1
  fi
  echo "Version read from project: $VERSION"
fi

# ── Setup ─────────────────────────────────────────────────────────────────────
BUILD_ROOT="$(mktemp -d)"
mkdir -p "$OUTPUT_DIR"
trap 'rm -rf "$BUILD_ROOT"' EXIT

echo ""
echo "═══════════════════════════════════════════"
echo "  Scheme:  $SCHEME"
echo "  App:     $APP_NAME"
echo "  Bundle:  $BUNDLE_ID"
echo "  Version: $VERSION"
echo "  Output:  $OUTPUT_DIR"
echo "═══════════════════════════════════════════"

# ── iOS IPA ───────────────────────────────────────────────────────────────────
build_ipa() {
  echo ""
  echo "▶ Building iOS IPA…"

  ARCHIVE="$BUILD_ROOT/ios/${APP_NAME}.xcarchive"

  xcodebuild archive \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE" \
    IPHONEOS_DEPLOYMENT_TARGET="$MIN_IOS" \
    MARKETING_VERSION="$VERSION" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    SKIP_INSTALL=NO \
    | xcpretty 2>/dev/null || true  # xcpretty optional; falls back to raw output

  APP_PATH=$(find "${ARCHIVE}/Products" -name "*.app" | head -n 1)
  if [[ -z "$APP_PATH" ]]; then
    echo "Error: no .app found in archive at ${ARCHIVE}/Products"
    exit 1
  fi

  PAYLOAD_DIR="$BUILD_ROOT/ios/Payload"
  IPA_NAME="${APP_NAME}-${VERSION}.ipa"
  IPA_PATH="${OUTPUT_DIR}/${IPA_NAME}"

  mkdir -p "$PAYLOAD_DIR"
  cp -r "$APP_PATH" "$PAYLOAD_DIR/"
  (cd "$BUILD_ROOT/ios" && zip -qr "$IPA_PATH" Payload/)

  IPA_SIZE=$(stat -f%z "$IPA_PATH")
  echo "✓ IPA: ${IPA_PATH} ($(( IPA_SIZE / 1024 )) KB)"
}

# ── macOS DMG ─────────────────────────────────────────────────────────────────
build_dmg() {
  echo ""
  echo "▶ Building macOS DMG…"

  ARCHIVE="$BUILD_ROOT/macos/${APP_NAME}.xcarchive"

  xcodebuild archive \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE" \
    MARKETING_VERSION="$VERSION" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    SKIP_INSTALL=NO \
    | xcpretty 2>/dev/null || true

  APP_PATH=$(find "${ARCHIVE}/Products" -name "*.app" | head -n 1)
  if [[ -z "$APP_PATH" ]]; then
    echo "Error: no .app found in archive at ${ARCHIVE}/Products"
    exit 1
  fi

  DMG_STAGE="$BUILD_ROOT/macos/dmg-stage"
  DMG_NAME="${APP_NAME}-${VERSION}.dmg"
  DMG_PATH="${OUTPUT_DIR}/${DMG_NAME}"

  mkdir -p "$DMG_STAGE"
  cp -r "$APP_PATH" "$DMG_STAGE/"
  # Symlink to /Applications so users can drag-and-drop
  ln -s /Applications "$DMG_STAGE/Applications"

  hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$DMG_STAGE" \
    -ov \
    -format UDZO \
    "$DMG_PATH" \
    > /dev/null

  DMG_SIZE=$(stat -f%z "$DMG_PATH")
  echo "✓ DMG: ${DMG_PATH} ($(( DMG_SIZE / 1024 )) KB)"
}

# ── Run ───────────────────────────────────────────────────────────────────────
$BUILD_IOS  && build_ipa
$BUILD_MACOS && build_dmg

echo ""
echo "Done. Output in ${OUTPUT_DIR}/"
ls -lh "$OUTPUT_DIR/"
