#!/bin/bash
# Shared simulator pinning + preflight for test runners (sourced, not executed).
# Requires: REPO_ROOT set by the caller.
# Sets: SIM_DEST ('platform=iOS Simulator,id=<UDID>'), SIM_UDID.
#
# Practices adapted from voiceflow_ios/docs/test.md:
#   - one pinned simulator per repo (UDID in .occlient/simulator-udid);
#     concurrent xcodebuild work from other repos must use its own device;
#   - 15s bounded `simctl io screenshot` preflight: a wedged simulator fails
#     fast with guidance instead of hanging xcodebuild for 10 minutes.

OC_STATE_DIR="${OC_STATE_DIR:-$REPO_ROOT/.occlient}"
OC_UDID_FILE="$OC_STATE_DIR/simulator-udid"
OC_DEST_OVERRIDE="${OPENCODE_TEST_DESTINATION:-}"

mkdir -p "$OC_STATE_DIR"

# --- Machine load warning (warn only) ---------------------------------------
CPUS="$(sysctl -n hw.ncpu)"
LOAD1="$(sysctl -n vm.loadavg | awk -F'[ ]+' '{print $2}')"
if awk -v l="$LOAD1" -v c="$CPUS" 'BEGIN { exit !(l > c) }'; then
  echo "warn: machine load $LOAD1 exceeds $CPUS cores; test latency will be high (other xcodebuild work?)"
fi

# --- Simulator pinning --------------------------------------------------------
# One pinned simulator per repo (UDID in .occlient/simulator-udid); concurrent
# xcodebuild work from other repos must use its own device. A pin that can no
# longer boot — deleted runtime, erased device — is discarded and the next
# available iPhone is pinned in its place, so a runtime cleanup never wedges
# the runner.

# --- Simulator picking --------------------------------------------------------
# The iPhone lines of a device list, minus a UDID to skip.
# $1: the device state to ask for (booted / available).
# $2: a UDID to skip — one that just failed to boot.
#
# The list is captured before it is filtered. Piping the list into `grep -q`
# or `head` closes the pipe early, and under `pipefail` the writer's SIGPIPE
# becomes the pipeline's status — which reads as "the device is missing".
oc_list_iphones() {
  local state="$1" skip="${2:-}" lines
  lines="$(xcrun simctl list devices "$state" 2>/dev/null || true)"
  if [ -n "$skip" ]; then
    lines="$(printf '%s\n' "$lines" | grep -v "$skip" || true)"
  fi
  printf '%s\n' "$lines" | grep -E '^[[:space:]]+iPhone' || true
}

# A UDID counts as booted only when the device list says so: the UDID can
# appear on the line of a device that is shut down.
oc_device_booted() {
  local line
  while IFS= read -r line; do
    case "$line" in
      *"$1"*"(Booted)"*) return 0 ;;
    esac
  done <<EOF
$(xcrun simctl list devices booted 2>/dev/null || true)
EOF
  return 1
}

# A device listed as unavailable (runtime deleted) is as useless as a missing
# one: the marker travels on the same line as the UDID.
oc_device_usable() {
  local line found=0
  while IFS= read -r line; do
    case "$line" in
      *"$1"*)
        found=1
        case "$line" in
          *unavailable*) return 1 ;;
        esac
        ;;
    esac
  done <<EOF
$(xcrun simctl list devices 2>/dev/null || true)
EOF
  [ "$found" -eq 1 ]
}

oc_pick_simulator() {
  # $1 = UDID to exclude (a pin that just failed to boot), or empty.
  # Prefer a booted iPhone: no boot cost. The skip applies to both lists —
  # the device that just failed to boot must never be picked again.
  SIM_UDID="$(oc_list_iphones booted "$1" | grep '(Booted)' | grep -oE '[0-9A-F-]{36}' | head -1 || true)"
  if [ -z "$SIM_UDID" ]; then
    SIM_UDID="$(oc_list_iphones available "$1" | grep -oE '[0-9A-F-]{36}' | head -1 || true)"
  fi
  if [ -z "$SIM_UDID" ]; then
    echo "error: no available iPhone simulator; run: xcrun simctl create iPhone ..." >&2
    return 1
  fi
}

if [ -n "$OC_DEST_OVERRIDE" ]; then
  SIM_DEST="$OC_DEST_OVERRIDE"
  SIM_UDID="${SIM_DEST##*,id=}"
else
  SIM_UDID=""
  if [ -f "$OC_UDID_FILE" ]; then
    SIM_UDID="$(cat "$OC_UDID_FILE" 2>/dev/null || true)"
    if [ -n "$SIM_UDID" ] && ! oc_device_usable "$SIM_UDID"; then
      SIM_UDID=""  # device gone or unbootable; re-pin below
    fi
  fi
  if [ -z "$SIM_UDID" ]; then
    oc_pick_simulator || exit 1
    echo "$SIM_UDID" > "$OC_UDID_FILE"
    echo "pinning simulator $SIM_UDID (first boot, slow)"
    xcrun simctl boot "$SIM_UDID"
  fi
  if ! oc_device_booted "$SIM_UDID"; then
    echo "booting pinned simulator $SIM_UDID"
    if ! xcrun simctl boot "$SIM_UDID"; then
      echo "warn: pinned simulator $SIM_UDID did not boot; re-pinning" >&2
      oc_pick_simulator "$SIM_UDID" || exit 1
      echo "$SIM_UDID" > "$OC_UDID_FILE"
      xcrun simctl boot "$SIM_UDID"
    fi
  fi
  SIM_DEST="platform=iOS Simulator,id=$SIM_UDID"
fi

# --- Preflight: 15s bounded screenshot probe ---------------------------------
PROBE_PNG="$(mktemp -t occlient-sim-probe).png"
if ! timeout 15 xcrun simctl io "$SIM_UDID" screenshot "$PROBE_PNG" >/dev/null 2>&1; then
  echo "error: simulator unresponsive within 15s (wedged?)." >&2
  echo "fixes, in order:" >&2
  echo "  1. stop concurrent xcodebuild work, wait for load to drop" >&2
  echo "  2. xcrun simctl shutdown $SIM_UDID and rerun this script" >&2
  echo "  3. if concurrency is the norm, point another repo at a different simulator (OPENCODE_TEST_DESTINATION)" >&2
  rm -f "$PROBE_PNG"
  exit 1
fi
rm -f "$PROBE_PNG"
