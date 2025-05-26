#!/bin/sh

set -euo pipefail

# 🏷️ Get version from Xcode Cloud environment variable
if [ -z "${CI_TAG:-}" ]; then
  echo "❌ CI_TAG not set. Make sure this workflow is triggered by a tag."
  exit 1
fi

# 📂 Get root of the repo from Xcode Cloud environment
REPO_PATH="${CI_PRIMARY_REPOSITORY_PATH:-.}"

# 📄 Path to the framework's Info.plist
PLIST_FILE="$REPO_PATH/CloudFramework/Info.plist"

if [ ! -f "$PLIST_FILE" ]; then
  echo "❌ Info.plist not found at $PLIST_FILE"
  exit 1
fi

echo "🛠️ Setting VersionTag = $CI_TAG in $PLIST_FILE"

/usr/libexec/PlistBuddy -c "Set :VersionTag $CI_TAG" "$PLIST_FILE" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Add :VersionTag string $CI_TAG" "$PLIST_FILE"

echo
