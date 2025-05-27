#!/bin/sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/ci_config.sh"
. "$SCRIPT_DIR/ci_utils.sh"

validate_inputs
build_simulator_framework
create_xcframework
prepare_spm_repo
commit_and_tag_push
create_github_release

echo "✅ Done. $FRAMEWORK_NAME.xcframework published as $CI_TAG"
