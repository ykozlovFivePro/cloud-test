#!/bin/sh

set -euo pipefail

# ────────────── 🔧 General Configuration ──────────────

FRAMEWORK_NAME="CloudFramework"
SCHEME_NAME="$FRAMEWORK_NAME"

SIGNED_ARCHIVE_PATH="${CI_ARCHIVE_PATH:-}"
PROJECT_PATH="${CI_PRIMARY_REPOSITORY_PATH}"
CI_TAG="${CI_TAG:-}"

SIMULATOR_ARCHIVE_PATH="build/ios-simulator.xcarchive"
XCFRAMEWORK_OUTPUT="build/$FRAMEWORK_NAME.xcframework"

# ────────────── 📄 Info.plist Configuration ──────────────

INFO_PLIST_RELATIVE_PATH="$FRAMEWORK_NAME/Info.plist"
PLIST_FILE="$PROJECT_PATH/$INFO_PLIST_RELATIVE_PATH"

# ────────────── 🌐 GitHub Configuration ──────────────

DEST_BRANCH="${GITHUB_BRANCH:-main}"
PUBLIC_REPO_NAME="${GITHUB_REPO_NAME:?}"
PUBLIC_REPO_DIR="spm-repo"

GITHUB_USER="${GITHUB_USERNAME:?}"
GITHUB_EMAIL="${GITHUB_EMAIL:?}"
GITHUB_TOKEN="${GITHUB_TOKEN:?}"

PUBLIC_REPO_URL="https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${PUBLIC_REPO_NAME}.git"
