#!/bin/bash
# Existing overrides: OPENCODE_TEST_DESTINATION, OPENCODE_TEST_DERIVED_DATA,
# OPENCODE_TEST_REBUILD, OPENCODE_TEST_ONLY.
# Added: OPENCODE_TEST_OUTPUT_ROOT, OPENCODE_TEST_PHASE_TIMEOUT_SECONDS (default 0).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/scripts/lib_test_observability.sh"
oc_init unit
oc_preflight

PROJECT="$REPO_ROOT/OpenCodeClient/OpenCodeClient.xcodeproj"
SCHEME="OpenCodeClient"
TEST_TARGET="OpenCodeClientTests"
DERIVED_DATA="${OPENCODE_TEST_DERIVED_DATA:-$REPO_ROOT/.occlient/DerivedData}"
REBUILD="${OPENCODE_TEST_REBUILD:-0}"
ONLY="${OPENCODE_TEST_ONLY:-}"
BUILD_ARGS=(-project "$PROJECT" -scheme "$SCHEME" -destination "$SIM_DEST" -derivedDataPath "$DERIVED_DATA")
if [ -n "$ONLY" ]; then BUILD_ARGS+=(-only-testing:"$ONLY"); fi
oc_phase build "$OC_TIMEOUT" bash -e -c \
  'if [ "$1" = 1 ]; then echo "OPENCODE_TEST_REBUILD=1: removing previous products"; rm -rf "$2/Build/Products"; fi; shift 2; exec xcodebuild build-for-testing "$@"' \
  bash "$REBUILD" "$DERIVED_DATA" "${BUILD_ARGS[@]}"

TEST_ARGS=(-project "$PROJECT" -scheme "$SCHEME" -destination "$SIM_DEST" -derivedDataPath "$DERIVED_DATA")
if [ -n "$ONLY" ]; then TEST_ARGS+=(-only-testing:"$ONLY"); else TEST_ARGS+=(-only-testing:"$TEST_TARGET"); fi
if oc_phase test "$OC_TIMEOUT" xcodebuild test-without-building "${TEST_ARGS[@]}" -resultBundlePath "$OC_BUNDLE"; then TEST_EXIT=0; else TEST_EXIT=$?; fi
oc_inspect_bundle
oc_accept_test "$TEST_EXIT"
