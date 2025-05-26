#!/bin/sh

set -euo pipefail

# ────────────── 🔧 Configuration ──────────────

FRAMEWORK_NAME="CloudFramework"
SCHEME_NAME="CloudFramework"
SIMULATOR_ARCHIVE_PATH="build/ios-simulator.xcarchive"
XCFRAMEWORK_OUTPUT="build/$FRAMEWORK_NAME.xcframework"

SIGNED_ARCHIVE_PATH="${CI_ARCHIVE_PATH:-}"
PROJECT_PATH="${CI_PRIMARY_REPOSITORY_PATH}"
CI_TAG="${CI_TAG:-}"
DEST_BRANCH="${GITHUB_BRANCH:-main}"
PUBLIC_REPO_NAME="${GITHUB_REPO_NAME:?}"
PUBLIC_REPO_DIR="spm-repo"
GITHUB_USER="${GITHUB_USERNAME:?}"
GITHUB_EMAIL="${GITHUB_EMAIL:?}"
GITHUB_TOKEN="${GITHUB_TOKEN:?}"

PUBLIC_REPO_URL="https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${PUBLIC_REPO_NAME}.git"

# ────────────── 🚨 Validations ──────────────

echo "🔍 CI_ARCHIVE_PATH: $SIGNED_ARCHIVE_PATH"
if [ ! -d "$SIGNED_ARCHIVE_PATH" ]; then
  echo "❌ CI_ARCHIVE_PATH not found or invalid"
  exit 1
fi

if [ -z "$CI_TAG" ]; then
  echo "❌ CI_TAG not set. Ensure this build is triggered by a Git tag."
  exit 1
fi

# ────────────── 📦 Locate iOS Framework ──────────────

IOS_FRAMEWORK_PATH="$SIGNED_ARCHIVE_PATH/Products/Library/Frameworks/$FRAMEWORK_NAME.framework"
if [ ! -d "$IOS_FRAMEWORK_PATH" ]; then
  echo "❌ iOS framework not found at $IOS_FRAMEWORK_PATH"
  exit 1
fi
echo "✅ Found iOS framework"

# ────────────── 🖥️ Build Simulator Framework ──────────────

echo "📦 Building iOS Simulator archive..."
cd "$PROJECT_PATH"

xcodebuild archive \
  -scheme "$SCHEME_NAME" \
  -destination "generic/platform=iOS Simulator" \
  -archivePath "$SIMULATOR_ARCHIVE_PATH" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES

SIMULATOR_FRAMEWORK_PATH="$SIMULATOR_ARCHIVE_PATH/Products/Library/Frameworks/$FRAMEWORK_NAME.framework"
if [ ! -d "$SIMULATOR_FRAMEWORK_PATH" ]; then
  echo "❌ Simulator framework not found at $SIMULATOR_FRAMEWORK_PATH"
  exit 1
fi
echo "✅ Built iOS Simulator framework"

# ────────────── 🧬 Create XCFramework ──────────────

echo "🔗 Creating XCFramework..."
rm -rf "$XCFRAMEWORK_OUTPUT"

xcodebuild -create-xcframework \
  -framework "$IOS_FRAMEWORK_PATH" \
  -framework "$SIMULATOR_FRAMEWORK_PATH" \
  -output "$XCFRAMEWORK_OUTPUT"

echo "✅ XCFramework created at $XCFRAMEWORK_OUTPUT"

# ────────────── 🌐 Clone SPM Repo ──────────────

echo "📥 Cloning SwiftPM repo..."
git clone "$PUBLIC_REPO_URL" "$PUBLIC_REPO_DIR"
cd "$PUBLIC_REPO_DIR"

# Check if the repo is empty
if [ -z "$(git rev-parse --verify HEAD 2>/dev/null)" ]; then
  echo "🆕 Empty repo. Creating initial commit on '$DEST_BRANCH'..."
  git checkout -b "$DEST_BRANCH"
  touch .gitkeep
  git add .gitkeep
  git commit -m "Initial commit"
  git push origin "$DEST_BRANCH"
else
  git checkout "$DEST_BRANCH"
fi

# ────────────── 📁 Copy XCFramework ──────────────

echo "📁 Copying XCFramework to repo root..."
rm -rf "$FRAMEWORK_NAME.xcframework"
cp -R "../$XCFRAMEWORK_OUTPUT" ./

# ────────────── ✍️ Write Package.swift ──────────────

echo "📄 Updating Package.swift..."

cat > Package.swift <<EOF
// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "$FRAMEWORK_NAME",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "$FRAMEWORK_NAME",
            targets: ["$FRAMEWORK_NAME"])
    ],
    dependencies: [],
    targets: [
        .binaryTarget(
            name: "$FRAMEWORK_NAME",
            path: "$FRAMEWORK_NAME.xcframework"
        )
    ],
    swiftLanguageVersions: [.v5]
)
EOF

# ────────────── 🚀 Commit and Push ──────────────

echo "📤 Committing and pushing..."
git config user.name "$GITHUB_USER"
git config user.email "$GITHUB_EMAIL"

git add "$FRAMEWORK_NAME.xcframework" Package.swift
git commit -m "Update static framework v${CI_TAG}"
git push origin "$DEST_BRANCH"

# ────────────── 🏷️ Tag Push ──────────────

echo "🏷️ Pushing tag: $CI_TAG"
# 🏷️ Safely re-create tag
if git rev-parse "$CI_TAG" >/dev/null 2>&1; then
  echo "⚠️ Local tag '$CI_TAG' already exists. Deleting it..."
  git tag -d "$CI_TAG"
fi

echo "🏷️ Creating and pushing tag '$CI_TAG'..."
git tag "$CI_TAG"
git push origin "$CI_TAG"


echo "✅ Done. $FRAMEWORK_NAME.xcframework pushed and tagged as $CI_TAG"

# ────────────── 🚀 Create GitHub Release ──────────────

echo "📦 Creating GitHub release for tag $CI_TAG..."

REPO_API="https://api.github.com/repos/${GITHUB_USERNAME}/${PUBLIC_REPO_NAME}"
RELEASE_DATA=$(cat <<EOF
{
  "tag_name": "$CI_TAG",
  "target_commitish": "$DEST_BRANCH",
  "name": "$CI_TAG",
  "body": "Release of CloudFramework $CI_TAG",
  "draft": false,
  "prerelease": false
}
EOF
)

RESPONSE=$(curl -sSL -X POST "$REPO_API/releases" \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  -d "$RELEASE_DATA")

UPLOAD_URL=$(echo "$RESPONSE" | grep upload_url | cut -d '"' -f 4 | cut -d '{' -f 1)

if [ -z "$UPLOAD_URL" ]; then
  echo "⚠️ Failed to create GitHub release. Response:"
  echo "$RESPONSE"
  exit 1
fi

echo "✅ GitHub release created: $CI_TAG"

echo "🗜️ Zipping XCFramework for GitHub asset upload..."

cd "$PROJECT_PATH/build"
zip -r -X CloudFramework.xcframework.zip CloudFramework.xcframework
cd "$PROJECT_PATH"

echo "📤 Uploading asset to release..."

curl -sSL -X POST "$UPLOAD_URL?name=CloudFramework.xcframework.zip" \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Content-Type: application/zip" \
  --data-binary @"build/CloudFramework.xcframework.zip"

echo "✅ Asset uploaded to release"

