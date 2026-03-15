#!/usr/bin/env bash
# tag-release.sh — bump version, create and push a git tag
# Usage: ./tag-release.sh <major|minor|patch> [--scheme <scheme>] [--dry-run]

set -euo pipefail

# ── Args ──────────────────────────────────────────────────────────────────────
BUMP=""
SCHEME=""
DRY_RUN=false

usage() {
  echo "Usage: $0 <major|minor|patch> [--scheme <xcode-scheme>] [--dry-run]"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    major|minor|patch) BUMP="$1"; shift ;;
    --scheme) SCHEME="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown argument: $1"; usage ;;
  esac
done

[[ -z "$BUMP" ]] && usage

# ── Latest tag from GitHub ────────────────────────────────────────────────────
echo "Fetching latest tag from GitHub…"
LATEST_TAG=$(gh release list --limit 1 --json tagName --jq '.[0].tagName' 2>/dev/null || true)

if [[ -z "$LATEST_TAG" ]]; then
  # Fall back to git tags if no GitHub releases exist yet
  LATEST_TAG=$(git tag --list 'v*' --sort=-version:refname | head -n 1)
fi

if [[ -z "$LATEST_TAG" ]]; then
  echo "No existing tags found — starting from v0.0.0"
  CURRENT="0.0.0"
else
  echo "Latest tag: ${LATEST_TAG}"
  CURRENT="${LATEST_TAG#v}"
fi

# ── Xcode version (optional cross-check) ─────────────────────────────────────
XCODE_VERSION=""
if [[ -n "$SCHEME" ]]; then
  XCODE_VERSION=$(xcodebuild -scheme "$SCHEME" -showBuildSettings 2>/dev/null \
    | awk '/^\s*MARKETING_VERSION =/ { print $3; exit }')
fi

if [[ -z "$SCHEME" ]]; then
  # Try to auto-detect from any .xcodeproj or .xcworkspace in cwd
  XCODE_VERSION=$(xcodebuild -showBuildSettings 2>/dev/null \
    | awk '/^\s*MARKETING_VERSION =/ { print $3; exit }' || true)
fi

# ── Compute next version ──────────────────────────────────────────────────────
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"
MAJOR=${MAJOR:-0}; MINOR=${MINOR:-0}; PATCH=${PATCH:-0}

case "$BUMP" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
esac

NEXT="${MAJOR}.${MINOR}.${PATCH}"
NEW_TAG="v${NEXT}"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "  Current tag:      ${LATEST_TAG:-none}"
if [[ -n "$XCODE_VERSION" ]]; then
  if [[ "$XCODE_VERSION" != "$CURRENT" ]]; then
    echo "  Xcode version:    ${XCODE_VERSION}  ⚠️  differs from latest tag (${CURRENT})"
  else
    echo "  Xcode version:    ${XCODE_VERSION}  ✓ matches latest tag"
  fi
fi
echo "  Bump:             ${BUMP}"
echo "  New tag:          ${NEW_TAG}"
echo ""

if $DRY_RUN; then
  echo "Dry run — no tag created."
  exit 0
fi

read -r -p "Create and push ${NEW_TAG}? [y/N] " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

git tag "$NEW_TAG"
git push origin "$NEW_TAG"
echo "✓ Tagged and pushed ${NEW_TAG}"
