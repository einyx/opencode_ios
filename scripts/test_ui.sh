#!/bin/bash
# Pinned simulator, incremental build, complete logs and per-run evidence.
# Existing overrides: OPENCODE_TEST_DESTINATION, OPENCODE_TEST_DERIVED_DATA,
# OPENCODE_TEST_REBUILD, OPENCODE_UI_TEST_ONLY, OPENCODE_UI_TEST_INCLUDE_LAUNCH.
# Added: OPENCODE_TEST_OUTPUT_ROOT, OPENCODE_TEST_PHASE_TIMEOUT_SECONDS (default 0).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/scripts/lib_test_observability.sh"
oc_init ui
oc_preflight

PROJECT="$REPO_ROOT/OpenCodeClient/OpenCodeClient.xcodeproj"
SCHEME="OpenCodeClient"
UI_TARGET="OpenCodeClientUITests"
DERIVED_DATA="${OPENCODE_TEST_DERIVED_DATA:-$REPO_ROOT/.occlient/DerivedData}"
REBUILD="${OPENCODE_TEST_REBUILD:-0}"
ONLY="${OPENCODE_UI_TEST_ONLY:-}"
INCLUDE_LAUNCH="${OPENCODE_UI_TEST_INCLUDE_LAUNCH:-0}"

BUILD_ARGS=(-project "$PROJECT" -scheme "$SCHEME" -destination "$SIM_DEST" -derivedDataPath "$DERIVED_DATA")
if [ -n "$ONLY" ]; then
  BUILD_ARGS+=(-only-testing:"$ONLY")
else
  BUILD_ARGS+=(-only-testing:"$UI_TARGET")
fi
# Keep rebuild semantics; include product removal in build phase timing/logs.
oc_phase build "$OC_TIMEOUT" bash -e -c \
  'if [ "$1" = 1 ]; then echo "OPENCODE_TEST_REBUILD=1: removing previous products"; rm -rf "$2/Build/Products"; fi; shift 2; exec xcodebuild build-for-testing "$@"' \
  bash "$REBUILD" "$DERIVED_DATA" "${BUILD_ARGS[@]}"

TEST_ARGS=(-project "$PROJECT" -scheme "$SCHEME" -destination "$SIM_DEST" -derivedDataPath "$DERIVED_DATA")
if [ -n "$ONLY" ]; then
  TEST_ARGS+=(-only-testing:"$ONLY")
else
  TEST_ARGS+=(-only-testing:"$UI_TARGET")
  if [ "$INCLUDE_LAUNCH" != 1 ]; then
    TEST_ARGS+=(-skip-testing:"$UI_TARGET/OpenCodeClientUITestsLaunchTests")
    TEST_ARGS+=(-skip-testing:"$UI_TARGET/OpenCodeClientUITests/testLaunchPerformance")
  fi
fi
if oc_phase test "$OC_TIMEOUT" xcodebuild test-without-building "${TEST_ARGS[@]}" -resultBundlePath "$OC_BUNDLE"; then TEST_EXIT=0; else TEST_EXIT=$?; fi
oc_inspect_bundle
oc_accept_test "$TEST_EXIT"
