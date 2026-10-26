#!/bin/bash
# Sourced by test runners. Read-only: never deletes files or starts a simulator.
oc_storage_preflight() {
  local minimum=${OPENCODE_MIN_FREE_GIB:-10} target probe report available
  case "$minimum" in
    ''|*[!0-9]*) printf 'Invalid OPENCODE_MIN_FREE_GIB: use 1-999 GiB.\n' >&2; return 64;;
  esac
  if [ "${#minimum}" -gt 3 ] || [ "$((10#$minimum))" -lt 1 ]; then
    printf 'Invalid OPENCODE_MIN_FREE_GIB: use 1-999 GiB.\n' >&2
    return 64
  fi
  minimum=$((10#$minimum))
  for target in "$REPO_ROOT" "${OPENCODE_TEST_DERIVED_DATA:-$REPO_ROOT/.occlient/DerivedData}" \
    "${OPENCODE_TEST_OUTPUT_ROOT:-$REPO_ROOT/.occlient/test-runs}"; do
    # Check the correct volume even when the requested directory doesn't exist.
    probe=$target
    while [ ! -d "$probe" ]; do
      probe=$(dirname "$probe")
    done
    if ! report=$(df -Pk "$probe"); then
      printf 'Cannot check disk space for %s; refusing to start tests.\n' "$target" >&2
      return 73
    fi
    available=$(printf '%s\n' "$report" | awk 'NR == 2 {print $4}')
    case "$available" in
      ''|*[!0-9]*) printf 'Cannot parse available disk space for %s.\n' "$target" >&2; return 73;;
    esac
    if [ "$available" -lt "$((minimum * 1048576))" ]; then
      printf 'Low disk space for %s: %s KiB free; require %s GiB before tests.\n' \
        "$target" "$available" "$minimum" >&2
      printf 'Reuse .occlient/DerivedData; reclaim only confirmed-inactive compiler caches. See docs/tests.md (Disk space). No files were deleted.\n' >&2
      return 73
    fi
  done
}
