#!/bin/bash
# Bash 3.2 compatible. Worker mode is private to these test runners.
if [ "${BASH_SOURCE[0]}" = "$0" ] && [ "${1:-}" = "--worker" ]; then
  shift
  status_file=$1
  log_file=$2
  shift 2
  set +e
  "$@" 2>&1 | tee "$log_file"
  codes=("${PIPESTATUS[@]}")
  printf '%s %s\n' "${codes[0]}" "${codes[1]}" > "$status_file.tmp"
  mv "$status_file.tmp" "$status_file"
  [ "${codes[0]}" -eq 0 ] || exit "${codes[0]}"
  [ "${codes[1]}" -eq 0 ] || exit 74
  exit 0
fi

# TSV values are percent-escaped data, never shell code. Decode %25 last.
oc_escape() {
  local value=$1
  value=${value//%/%25}
  value=${value//$'\t'/%09}
  value=${value//$'\r'/%0D}
  value=${value//$'\n'/%0A}
  printf '%s' "$value"
}
oc_field() { printf '%s\t%s\n' "$1" "$(oc_escape "$2")"; }
oc_event() {
  printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$((SECONDS - OC_START))" "$1" "$2" "$(oc_escape "${3:-}")" >> "$OC_RUN/events.tsv"
}
oc_state() {
  {
    oc_field format occlient-test-v1
    oc_field run "$OC_RUN"
    oc_field kind "$OC_KIND"
    oc_field phase "$OC_PHASE"
    oc_field outcome "$OC_REASON"
    oc_field exit_status "${OC_EXIT:-pending}"
    oc_field test_command_exit "${OC_TEST_COMMAND_EXIT:-not_run}"
    oc_field test_phase_exit "${OC_TEST_PHASE_EXIT:-not_run}"
    oc_field acceptance_exit "${OC_EXIT:-pending}"
    oc_field acceptance_status "${OC_ACCEPTANCE:-pending}"
    oc_field elapsed_seconds "$((SECONDS - OC_START))"
    oc_field destination "${SIM_DEST:-unknown}"
    oc_field derived_data "${DERIVED_DATA:-unknown}"
    oc_field developer_dir "${DEVELOPER_DIR:-inherited}"
    oc_field result_bundle "$OC_BUNDLE"
    oc_field bundle_presence "$([ -d "$OC_BUNDLE" ] && printf present || printf absent)"
    oc_field bundle_parse "${OC_BUNDLE_PARSE:-not_attempted}"
    oc_field bundle_test_result "${OC_BUNDLE_RESULT:-unknown}"
    oc_field verification "${OC_VERIFICATION:-incomplete}"
  } > "$OC_RUN/state.tsv.tmp"
  mv "$OC_RUN/state.tsv.tmp" "$OC_RUN/state.tsv"
}
oc_stop_child() {
  if [ -n "${OC_PID:-}" ]; then
    # Monitor mode gives this one worker its own process group, including tee.
    # Do not inspect, signal, or sample any unrelated process.
    kill -TERM -- "-$OC_PID" 2>/dev/null || true
    kill -KILL -- "-$OC_PID" 2>/dev/null || true
    wait "$OC_PID" 2>/dev/null || true
    OC_PID=
  fi
}
oc_signal() {
  OC_REASON=interrupt
  oc_event "$OC_PHASE" interrupt "$1"
  oc_stop_child
  exit "$2"
}
oc_finish() {
  local code=$?
  trap - EXIT INT TERM HUP
  oc_stop_child
  OC_EXIT=$code
  if [ "$code" -eq 0 ] && [ "$OC_VERIFICATION" = passed ]; then OC_ACCEPTANCE=passed; else OC_ACCEPTANCE=failed; fi
  if [ "$OC_PHASE_ACTIVE" = 1 ]; then
    if [ "$OC_PHASE" = test ]; then OC_TEST_COMMAND_EXIT=unknown; OC_TEST_PHASE_EXIT=$code; fi
    {
      oc_field command_exit unknown
      oc_field tee_exit unknown
      oc_field wrapper_exit "$code"
      oc_field duration_seconds "$((SECONDS - OC_PHASE_START))"
    } > "$OC_RUN/$OC_PHASE.status.tsv"
    oc_event "$OC_PHASE" end "interrupted_or_aborted; wrapper_exit=$code; raw_exit=unknown"
  fi
  if [ "$OC_REASON" = running ]; then
    if [ "$code" -eq 0 ]; then OC_REASON=completed; else OC_REASON=failed; fi
  fi
  OC_PHASE=total
  oc_event total end "outcome=$OC_REASON; exit=$code"
  oc_state
  printf '\nTest run: %s\nExit: %s; outcome: %s; bundle: %s / %s; verification: %s\n' \
    "$OC_RUN" "$code" "$OC_REASON" "$OC_BUNDLE_PARSE" "$OC_BUNDLE_RESULT" "$OC_VERIFICATION"
  exit "$code"
}
# Resolve existing symlinks and lexical . / .. without creating directories.
oc_resolve_dir() {
  local rest=$1 part resolved
  case "$rest" in /*) resolved=/;; *) resolved=$(pwd -P);; esac
  while [ -n "$rest" ]; do
    part=${rest%%/*}
    if [ "$rest" = "$part" ]; then rest=; else rest=${rest#*/}; fi
    case "$part" in
      ''|.) continue;;
      ..) resolved=${resolved%/*}; [ -n "$resolved" ] || resolved=/;;
      *)
        resolved=${resolved%/}/$part
        if [ -e "$resolved" ] || [ -L "$resolved" ]; then
          [ -d "$resolved" ] || return 1
          resolved=$(cd "$resolved" && pwd -P) || return 1
        fi
        ;;
    esac
  done
  printf '%s\n' "$resolved"
}
oc_output_root() {
  local repo root relative tracked owner
  repo=$(cd "$REPO_ROOT" && pwd -P) || return 73
  root=$(oc_resolve_dir "${OPENCODE_TEST_OUTPUT_ROOT:-$repo/.occlient/test-runs}") || {
    printf 'Output root must be a directory path.\n' >&2; return 73;
  }
  case "$root" in "$repo/.occlient"|"$repo/.occlient/"*) ;; *)
    printf 'Output root must resolve inside this repo .occlient directory.\n' >&2; return 73;;
  esac
  relative=${root#"$repo/"}
  owner=$(git -C "$repo" rev-parse --show-toplevel) || return 73
  [ "$owner" = "$repo" ] || return 73
  tracked=$(git -C "$repo" ls-files -- ':(literal).occlient') || return 73
  if [ -n "$tracked" ] || ! git -C "$repo" check-ignore -q -- "$relative/"; then
    printf 'Output root must be Git-ignored, with no tracked files under .occlient.\n' >&2
    return 73
  fi
  mkdir -p "$root" || return 73
  # Catch nested repositories and recheck physical containment after creation.
  [ "$(cd "$root" && pwd -P)" = "$root" ] || return 73
  owner=$(git -C "$root" rev-parse --show-toplevel) || return 73
  [ "$owner" = "$repo" ] || { printf 'Nested repository output root rejected.\n' >&2; return 73; }
  printf '%s\n' "$root"
}
oc_init() {
  OC_KIND=$1
  OC_START=$SECONDS
  OC_HELPER="$REPO_ROOT/scripts/lib_test_observability.sh"
  local root
  root=$(oc_output_root) || exit 73
  OC_RUN=$(mktemp -d "$root/$OC_KIND-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")
  OC_BUNDLE="$OC_RUN/test.xcresult"
  OC_PHASE=total OC_REASON=running OC_PID= OC_PHASE_ACTIVE=0
  OC_BUNDLE_PARSE=not_attempted OC_BUNDLE_RESULT=unknown OC_VERIFICATION=incomplete
  OC_TEST_COMMAND_EXIT=not_run OC_TEST_PHASE_EXIT=not_run OC_ACCEPTANCE=pending
  trap oc_finish EXIT
  trap 'oc_signal INT 130' INT
  trap 'oc_signal TERM 143' TERM
  trap 'oc_signal HUP 129' HUP
  printf 'utc\telapsed_seconds\tphase\tevent\tdetail\n' > "$OC_RUN/events.tsv"
  oc_event total start
  oc_state
  printf 'Test artifacts: %s\n' "$OC_RUN"
  OC_TIMEOUT=${OPENCODE_TEST_PHASE_TIMEOUT_SECONDS:-0}
  case "$OC_TIMEOUT" in *[!0-9]*|'') printf 'Invalid phase timeout: use integer seconds (0 disables).\n' >&2; exit 64;; esac
  if [ "$OC_TIMEOUT" -ne 0 ]; then
    # timeout already serves lib_simulator's preflight. macOS and GNU variants
    # both support the signal/kill-after options; macOS has no --version flag.
    command -v timeout >/dev/null 2>&1 || { printf 'timeout required for optional phase deadlines.\n' >&2; exit 69; }
  fi
}
oc_phase() {
  local phase=$1 limit=$2 rc raw=unknown tee_code=unknown
  shift 2
  OC_PHASE=$phase OC_PHASE_ACTIVE=1
  OC_PHASE_START=$SECONDS
  oc_event "$phase" start
  oc_state
  # A single owned process group keeps terminal and externally sent interrupts
  # bounded to this phase. All command arguments remain an argv array.
  set -m
  if [ "$limit" -gt 0 ]; then
    timeout --signal=TERM --kill-after=5s "${limit}s" \
      bash "$OC_HELPER" --worker "$OC_RUN/$phase.codes" "$OC_RUN/$phase.log" "$@" &
  else
    bash "$OC_HELPER" --worker "$OC_RUN/$phase.codes" "$OC_RUN/$phase.log" "$@" &
  fi
  OC_PID=$!
  set +m
  if wait "$OC_PID"; then rc=0; else rc=$?; fi
  OC_PID=
  if [ -f "$OC_RUN/$phase.codes" ]; then
    read -r raw tee_code < "$OC_RUN/$phase.codes"
  elif [ "$limit" -gt 0 ] && { [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; }; then
    OC_REASON=timeout
    oc_event "$phase" timeout "limit_seconds=$limit; wrapper_exit=$rc"
  fi
  {
    oc_field command_exit "$raw"
    oc_field tee_exit "$tee_code"
    oc_field wrapper_exit "$rc"
    oc_field duration_seconds "$((SECONDS - OC_PHASE_START))"
  } > "$OC_RUN/$phase.status.tsv"
  if [ "$phase" = test ]; then OC_TEST_COMMAND_EXIT=$raw; OC_TEST_PHASE_EXIT=$rc; fi
  oc_event "$phase" end "wrapper_exit=$rc; command_exit=$raw; tee_exit=$tee_code"
  OC_PHASE_ACTIVE=0
  oc_state
  return "$rc"
}
oc_preflight() {
  # Source the unchanged simulator library in an isolated Bash. Transfer only
  # its two public outputs as Bash %q assignments, not arbitrary stdout.
  oc_phase preflight "$OC_TIMEOUT" bash -euo pipefail -c \
    'REPO_ROOT=$1; source "$1/scripts/lib_simulator.sh"; printf "SIM_DEST=%q\nSIM_UDID=%q\n" "$SIM_DEST" "$SIM_UDID" > "$2"' \
    bash "$REPO_ROOT" "$OC_RUN/simulator.vars"
  source "$OC_RUN/simulator.vars"
}
oc_inspect_bundle() {
  local saved_reason=$OC_REASON
  [ -d "$OC_BUNDLE" ] || { OC_BUNDLE_PARSE=missing; return 0; }
  # Diagnostic only: inspect exit/status separately; never infer from log text.
  if oc_phase result 15 bash -c \
    'xcrun xcresulttool get test-results summary --path "$1" > "$2"' \
    bash "$OC_BUNDLE" "$OC_RUN/result-summary.json"; then
    oc_parse_summary
  else
    OC_BUNDLE_PARSE=unreadable
  fi
  # Result inspection timeout must not overwrite the test runner outcome.
  OC_REASON=$saved_reason
}
oc_parse_summary() {
  # Xcode 27 xcresulttool test-results summary uses top-level "result".
  if OC_BUNDLE_RESULT=$(plutil -extract result raw -o - "$OC_RUN/result-summary.json" 2> "$OC_RUN/result-parse.log"); then
    OC_BUNDLE_PARSE=parsed
  else
    OC_BUNDLE_PARSE=unrecognized_summary
    OC_BUNDLE_RESULT=unknown
  fi
}
oc_accept_test() {
  local phase_exit=$1
  # Preserve test/tee/timeout failures. Evidence failures only replace success.
  [ "$phase_exit" -eq 0 ] || return "$phase_exit"
  if [ "$OC_BUNDLE_PARSE" = parsed ] && [ "$OC_BUNDLE_RESULT" = Passed ]; then
    OC_VERIFICATION=passed
    return 0
  fi
  return 65
}
