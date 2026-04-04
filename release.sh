#!/bin/bash
set -euo pipefail

MOD_DIR="factorio-auto-foundation-undergrounds"
INFO="$MOD_DIR/info.json"
MODS_DIR="/mnt/c/Users/t/AppData/Roaming/Factorio/mods"

# Parse name and version from info.json
MOD_NAME=$(grep '"name"' "$INFO" | sed 's/.*: "\(.*\)".*/\1/')
VERSION=$(grep '"version"' "$INFO" | sed 's/.*: "\(.*\)".*/\1/')

# Bump patch version
IFS='.' read -r major minor patch <<< "$VERSION"
NEW_VERSION="${major}.${minor}.$((patch + 1))"

# Update info.json
sed -i "s/\"version\": \"${VERSION}\"/\"version\": \"${NEW_VERSION}\"/" "$INFO"
echo "Bumped ${VERSION} -> ${NEW_VERSION}"

# Build zip with correct internal folder structure
RELEASE_NAME="${MOD_NAME}_${NEW_VERSION}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cp -r "$MOD_DIR" "$TMP/$RELEASE_NAME"
rm -rf "$TMP/$RELEASE_NAME/.git"
(cd "$TMP" && zip -qr "${RELEASE_NAME}.zip" "$RELEASE_NAME/")

# Remove all existing versions of this mod from the mods directory
# Don't have perms to do this from inside WSL - just delete the old one manually
# rm -f "${MODS_DIR}/${MOD_NAME}_"*.zip
# find "${MODS_DIR}" -maxdepth 1 -name "${MOD_NAME}_*" -type l -delete

# Install
cp "$TMP/${RELEASE_NAME}.zip" "$MODS_DIR/"
echo "Installed ${RELEASE_NAME}.zip -> $MODS_DIR"
