#!/bin/sh
set -euo pipefail

validate_inputs() {
  echo "🔍 CI_ARCHIVE_PATH: $SIGNED_ARCHIVE_PATH"
  if [ ! -d "$SIGNED_ARCHIVE_PATH" ]; then
    echo "❌ CI_ARCHIVE_PATH not found or invalid"
    exit 1
  fi

  if [ -z "$CI_TAG" ]; then
    echo "❌ CI_TAG not set. Ensure this build is triggered by a Git tag."
    exit 1
  fi

  IOS_FRAMEWORK_PATH="$SIGNED_ARCHIVE_PATH/Products/Library/Frameworks/$FRAMEWORK_NAME.framework"
  if [ ! -d "$IOS_FRAMEWORK_PATH" ]; then
    echo "❌ iOS framework not found at $IOS_FRAMEWORK_PATH"
    exit 1
  fi
  echo "✅ Found iOS framework"
}

build_simulator_framework() {
  echo "📦 Building iOS Simulator archive..."
  cd "$PROJECT_PATH"
  xcodebuild archive     -scheme "$SCHEME_NAME"     -destination "generic/platform=iOS Simulator"     -archivePath "$SIMULATOR_ARCHIVE_PATH"     SKIP_INSTALL=NO     BUILD_LIBRARY_FOR_DISTRIBUTION=YES
  cd - >/dev/null

  SIMULATOR_FRAMEWORK_PATH="$SIMULATOR_ARCHIVE_PATH/Products/Library/Frameworks/$FRAMEWORK_NAME.framework"
  if [ ! -d "$SIMULATOR_FRAMEWORK_PATH" ]; then
    echo "❌ Simulator framework not found at $SIMULATOR_FRAMEWORK_PATH"
    exit 1
  fi
  echo "✅ Built iOS Simulator framework"
}

create_xcframework() {
  echo "🔗 Creating XCFramework..."
  rm -rf "$XCFRAMEWORK_OUTPUT"
  xcodebuild -create-xcframework     -framework "$IOS_FRAMEWORK_PATH"     -framework "$SIMULATOR_FRAMEWORK_PATH"     -output "$XCFRAMEWORK_OUTPUT"
  echo "✅ XCFramework created at $XCFRAMEWORK_OUTPUT"
}

prepare_spm_repo() {
  echo "📥 Cloning SwiftPM repo..."
  git clone "$PUBLIC_REPO_URL" "$PUBLIC_REPO_DIR"
  cd "$PUBLIC_REPO_DIR"

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

  echo "📁 Copying XCFramework to repo root..."
  rm -rf "$FRAMEWORK_NAME.xcframework"
  cp -R "../$XCFRAMEWORK_OUTPUT" ./

  echo "📄 Updating Package.swift..."
  cat > Package.swift <<EOF
// swift-tools-version: 5.9
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
  cd - >/dev/null
}

commit_and_tag_push() {
  echo "📤 Committing and pushing..."
  cd "$PUBLIC_REPO_DIR"
  git config user.name "$GITHUB_USER"
  git config user.email "$GITHUB_EMAIL"
  git add "$FRAMEWORK_NAME.xcframework" Package.swift
  git commit -m "Update static framework v${CI_TAG}"
  git push origin "$DEST_BRANCH"

  if git rev-parse "$CI_TAG" >/dev/null 2>&1; then
    echo "⚠️ Local tag '$CI_TAG' already exists. Deleting it..."
    git tag -d "$CI_TAG"
  fi

  echo "🏷️ Creating and force-pushing tag '$CI_TAG'..."
  git tag "$CI_TAG"
  git push --force origin "$CI_TAG"
  cd - >/dev/null
}

create_github_release() {
  echo "📦 Creating GitHub release for tag $CI_TAG..."
  REPO_API="https://api.github.com/repos/${GITHUB_USER}/${PUBLIC_REPO_NAME}"
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

  RESPONSE=$(curl -sSL -X POST "$REPO_API/releases"     -H "Authorization: token ${GITHUB_TOKEN}"     -H "Accept: application/vnd.github+json"     -d "$RELEASE_DATA")

  UPLOAD_URL=$(echo "$RESPONSE" | grep upload_url | cut -d '"' -f 4 | cut -d '{' -f 1)
  if [ -z "$UPLOAD_URL" ]; then
    echo "⚠️ Failed to create GitHub release. Response:"
    echo "$RESPONSE"
    exit 1
  fi

  echo "🗜️ Zipping XCFramework for GitHub asset upload..."
  cd "$PROJECT_PATH/build"
  zip -r -X "${FRAMEWORK_NAME}.xcframework.zip" "${FRAMEWORK_NAME}.xcframework"
  cd - >/dev/null

  echo "📤 Uploading asset to release..."
  curl -sSL -X POST "$UPLOAD_URL?name=${FRAMEWORK_NAME}.xcframework.zip"     -H "Authorization: token ${GITHUB_TOKEN}"     -H "Content-Type: application/zip"     --data-binary @"$PROJECT_PATH/build/${FRAMEWORK_NAME}.xcframework.zip"

  echo "✅ Asset uploaded to release"
}
