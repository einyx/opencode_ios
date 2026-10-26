#!/bin/bash
# Offline disk-pressure regression checks; never launches Xcode or deletes caches.
set -euo pipefail
SOURCE=$(cd "$(dirname "$0")/../.." && pwd -P)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/occlient-storage-tests-XXXXXX")
REPO_ROOT=$WORK
if [ -f "$SOURCE/scripts/lib_storage.sh" ]; then source "$SOURCE/scripts/lib_storage.sh"; fi
declare -F oc_storage_preflight >/dev/null || { echo 'FAIL: storage preflight is missing'; exit 1; }

# Model df's POSIX output, including a mount point with spaces.
df() {
  [ "${MOCK_DF_FAIL:-0}" = 0 ] || return 1
  printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
  printf '/dev/test 999999999 100 %s 50%% /a volume\n' "${MOCK_FREE_KIB:-20971520}"
}
check() {
  local name=$1 expected=$2 status=0
  oc_storage_preflight > "$WORK/output" 2>&1 || status=$?
  [ "$status" -eq "$expected" ] || { cat "$WORK/output"; echo "FAIL: $name ($status != $expected)"; exit 1; }
  echo "PASS: $name"
}
unset OPENCODE_MIN_FREE_GIB OPENCODE_TEST_OUTPUT_ROOT OPENCODE_TEST_DERIVED_DATA || true
check 'sufficient space' 0
MOCK_FREE_KIB=10485759
check 'below 10 GiB fails before build' 73
grep -q 'Low disk space' "$WORK/output"
MOCK_FREE_KIB=10485760
check 'exactly 10 GiB passes' 0
OPENCODE_MIN_FREE_GIB=15
check 'custom reserve is enforced' 73
OPENCODE_MIN_FREE_GIB=invalid
check 'invalid reserve rejected' 64
OPENCODE_MIN_FREE_GIB=0
check 'zero reserve rejected' 64
unset OPENCODE_MIN_FREE_GIB
MOCK_FREE_KIB=not-a-number
check 'unreadable free-space output fails closed' 73
MOCK_DF_FAIL=1
check 'df failure fails closed' 73
unset MOCK_DF_FAIL
MOCK_FREE_KIB=20971520
OPENCODE_TEST_DERIVED_DATA="$WORK/not created/DerivedData"
OPENCODE_TEST_OUTPUT_ROOT="$WORK/not created/results"
check 'nonexistent custom paths check existing ancestors' 0
[ ! -e "$WORK/not created" ] || { echo 'FAIL: preflight created output directories'; exit 1; }

# A custom build volume can be full even while the repo volume has space.
mkdir "$WORK/build volume"
OPENCODE_TEST_DERIVED_DATA="$WORK/build volume/new/DerivedData"
df() {
  printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
  case "$*" in
    *'build volume'*) printf '/dev/build 999999999 100 1000 99%% /build\n';;
    *) printf '/dev/repo 999999999 100 20971520 50%% /repo\n';;
  esac
}
check 'custom DerivedData volume checked' 73
unset OPENCODE_TEST_DERIVED_DATA
OPENCODE_TEST_OUTPUT_ROOT="$WORK/build volume/results"
check 'custom result volume checked' 73
echo "All storage preflight tests passed. Fixtures: $WORK"
