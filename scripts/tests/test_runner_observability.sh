#!/bin/bash
# Offline regression: actual runner scripts, fake Xcode/device commands.
# Only the final boundary tests use real Git, in a new temporary repository.
set -euo pipefail
SOURCE=$(cd "$(dirname "$0")/../.." && pwd -P)
FAKES="$SOURCE/scripts/tests/fakes"
BASE_PATH=$PATH
REAL_GIT=$(command -v git)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/occlient-runner-tests-XXXXXX")
WORK=$(cd "$WORK" && pwd -P)
REPO="$WORK/repo with spaces"
mkdir -p "$REPO/scripts" "$WORK/fakes"
for script in test_ui.sh test_unit.sh lib_test_observability.sh lib_simulator.sh; do
  cp "$SOURCE/scripts/$script" "$REPO/scripts/"
done
cp "$FAKES/"* "$WORK/fakes/"
chmod +x "$WORK/fakes/"*
# Prevent ambient Git/index/fixture settings from redirecting isolated tests.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES || true
for variable in ${!MOCK_@}; do unset "$variable"; done
export MOCK_SUMMARY_FIXTURE="$SOURCE/scripts/tests/fixtures/xcresult-summary-passed.json"
export PATH="$WORK/fakes:$BASE_PATH" TMPDIR="$WORK/"
export OC_STATE_DIR="$WORK/sim state"
export OPENCODE_TEST_OUTPUT_ROOT="$REPO/.occlient/results with spaces"
export MOCK_REPO="$REPO"
export OPENCODE_TEST_DERIVED_DATA="$WORK/derived data"
export OPENCODE_TEST_DESTINATION='platform=iOS Simulator,id=AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE'
export MOCK_CALLS="$WORK/calls" MOCK_PID="$WORK/pid"
unset OPENCODE_TEST_ONLY OPENCODE_UI_TEST_ONLY OPENCODE_UI_TEST_INCLUDE_LAUNCH OPENCODE_TEST_REBUILD OPENCODE_TEST_PHASE_TIMEOUT_SECONDS || true
count=0
fail() { printf 'FAIL: %s\nArtifacts: %s\n' "$*" "$WORK"; exit 1; }
has() { /usr/bin/grep -q -- "$2" "$1" || fail "$1 lacks $2"; }
run() {
  local name=$1 expected=$2 script=${3:-test_ui.sh} code=0
  : > "$MOCK_CALLS"
  : > "$MOCK_CALLS.build-for-testing"
  : > "$MOCK_CALLS.test-without-building"
  bash "$REPO/scripts/$script" > "$WORK/$name.stdout" 2>&1 || code=$?
  [ "$code" -eq "$expected" ] || fail "$name: exit $code, expected $expected"
  RUN=$(/usr/bin/sed -n 's/^Test artifacts: //p' "$WORK/$name.stdout")
  [ -f "$RUN/state.tsv" ] || fail "$name: missing state"
  has "$RUN/events.tsv" $'total\tend'
  count=$((count + 1))
  printf 'PASS %s (exit %s)\n' "$name" "$code"
}
arg_pair() {
  local file=$1 flag=$2 value=$3 previous= line
  while IFS= read -r line; do
    if [ "$previous" = "$flag" ] && [ "$line" = "$value" ]; then return 0; fi
    previous=$line
  done < "$file"
  fail "$file lacks argv pair: $flag / $value"
}
check_argv() {
  local file phase
  for phase in build-for-testing test-without-building; do
    file="$MOCK_CALLS.$phase"
    arg_pair "$file" -project "$REPO/OpenCodeClient/OpenCodeClient.xcodeproj"
    arg_pair "$file" -scheme OpenCodeClient
    arg_pair "$file" -destination "$OPENCODE_TEST_DESTINATION"
    arg_pair "$file" -derivedDataPath "$OPENCODE_TEST_DERIVED_DATA"
  done
  arg_pair "$MOCK_CALLS.test-without-building" -resultBundlePath "$RUN/test.xcresult"
  if /usr/bin/grep -q -- -resultBundlePath "$MOCK_CALLS.build-for-testing"; then fail 'test result path leaked into build argv'; fi
}
run success 0
SUCCESS_RUN=$RUN
has "$RUN/test.log" diagnostic-1$
has "$RUN/test.log" diagnostic-160$
has "$RUN/test.log" 'stderr retained'
has "$RUN/state.tsv" $'verification\tpassed'
has "$RUN/preflight.status.tsv" $'command_exit\t0'
for phase in preflight build test; do
  has "$RUN/events.tsv" "$phase"$'\tstart'
  has "$RUN/events.tsv" "$phase"$'\tend'
done
check_argv
has "$MOCK_CALLS.build-for-testing" 'only-testing:OpenCodeClientUITests'
has "$MOCK_CALLS.test-without-building" 'skip-testing:OpenCodeClientUITests/OpenCodeClientUITestsLaunchTests'
has "$MOCK_CALLS.test-without-building" 'skip-testing:OpenCodeClientUITests/OpenCodeClientUITests/testLaunchPerformance'
if /usr/bin/grep -q skip-testing "$MOCK_CALLS.build-for-testing"; then fail 'test skips leaked into build'; fi
awk -F '\t' '
  NR > 1 { if ($2 !~ /^[0-9]+$/ || $2 < prev) exit 1; prev=$2 }
  $3 == "preflight" && $4 == "start" {p=NR}
  $3 == "preflight" && $4 == "end" {q=NR}
  $3 == "build" && $4 == "start" {b=NR}
  $3 == "build" && $4 == "end" {c=NR}
  $3 == "test" && $4 == "start" {t=NR}
  $3 == "test" && $4 == "end" {u=NR}
  END { if (!(p < q && q < b && b < c && c < t && t < u)) exit 1 }
' "$RUN/events.tsv" || fail 'phase ordering or elapsed timestamps invalid'
has "$RUN/test.status.tsv" $'duration_seconds\t[0-9]'

export MOCK_TEST_EXIT=65
run nonzero 65
has "$RUN/test.status.tsv" $'command_exit\t65'
unset MOCK_TEST_EXIT
export MOCK_TEE_FAIL=1
run tee_failure 74
has "$RUN/preflight.status.tsv" $'command_exit\t0'
has "$RUN/preflight.status.tsv" $'tee_exit\t9'
unset MOCK_TEE_FAIL
export MOCK_TEE_TEST_FAIL=1
run test_tee_failure 74
has "$RUN/test.status.tsv" $'command_exit\t0'
has "$RUN/test.status.tsv" $'tee_exit\t9'
has "$RUN/test.log" diagnostic-160$
export MOCK_TEST_EXIT=65
run test_and_tee_failure 65
has "$RUN/test.status.tsv" $'command_exit\t65'
has "$RUN/test.status.tsv" $'tee_exit\t9'
unset MOCK_TEE_TEST_FAIL MOCK_TEST_EXIT
export MOCK_PREFLIGHT_FAIL=1
run preflight_failure 1
has "$RUN/state.tsv" $'outcome\tfailed'
has "$RUN/preflight.log" 'simulator unresponsive'
[ ! -e "$RUN/build.log" ] || fail 'build ran after preflight failure'
unset MOCK_PREFLIGHT_FAIL
for script in test_ui.sh test_unit.sh; do
  for failure in missing unreadable failed unknown_schema unknown_result; do
    case "$failure" in
      missing) export MOCK_NO_BUNDLE=1; expected_parse=missing;;
      unreadable) export MOCK_PARSE_FAIL=1; expected_parse=unreadable;;
      failed) export MOCK_RESULT=Failed; expected_parse=parsed;;
      unknown_schema) export MOCK_UNKNOWN_SCHEMA=1; expected_parse=unrecognized_summary;;
      unknown_result) export MOCK_RESULT=Skipped; expected_parse=parsed;;
    esac
    run "$script-$failure" 65 "$script"
    has "$RUN/state.tsv" "bundle_parse"$'\t'"$expected_parse"
    has "$RUN/state.tsv" $'verification\tincomplete'
    has "$RUN/state.tsv" $'test_command_exit\t0'
    has "$RUN/state.tsv" $'acceptance_exit\t65'
    has "$RUN/state.tsv" $'acceptance_status\tfailed'
    has "$RUN/test.status.tsv" $'command_exit\t0'
    has "$RUN/test.status.tsv" $'wrapper_exit\t0'
    check_argv
    unset MOCK_NO_BUNDLE MOCK_PARSE_FAIL MOCK_RESULT MOCK_UNKNOWN_SCHEMA
  done
  export MOCK_TEST_EXIT=42 MOCK_RESULT=Failed
  run "$script-original_nonzero" 42 "$script"
  has "$RUN/state.tsv" $'test_command_exit\t42'
  has "$RUN/state.tsv" $'acceptance_exit\t42'
  has "$RUN/test.status.tsv" $'command_exit\t42'
  unset MOCK_TEST_EXIT MOCK_RESULT
done
export MOCK_BUILD_EXIT=66
run build_failed 66
has "$RUN/build.status.tsv" $'command_exit\t66'
[ ! -e "$RUN/test.log" ] || fail 'test ran after build failure'
unset MOCK_BUILD_EXIT
export OPENCODE_UI_TEST_ONLY='OpenCodeClientUITests/Selected Suite'
run ui_only 0
check_argv
has "$MOCK_CALLS.build-for-testing" 'only-testing:OpenCodeClientUITests/Selected Suite'
has "$MOCK_CALLS.test-without-building" 'only-testing:OpenCodeClientUITests/Selected Suite'
if /usr/bin/grep -q skip-testing "$MOCK_CALLS"; then fail 'ONLY unexpectedly skipped launch'; fi
unset OPENCODE_UI_TEST_ONLY
export OPENCODE_UI_TEST_INCLUDE_LAUNCH=1
run include_launch 0
if /usr/bin/grep -q skip-testing "$MOCK_CALLS"; then fail 'include launch ignored'; fi
unset OPENCODE_UI_TEST_INCLUDE_LAUNCH
export OPENCODE_TEST_ONLY='OpenCodeClientTests/Selected Suite' OPENCODE_TEST_REBUILD=1
mkdir -p "$OPENCODE_TEST_DERIVED_DATA/Build/Products"
: > "$OPENCODE_TEST_DERIVED_DATA/Build/Products/old"
run unit_only_rebuild 0 test_unit.sh
[ ! -e "$OPENCODE_TEST_DERIVED_DATA/Build/Products/old" ] || fail 'rebuild failed'
check_argv
has "$MOCK_CALLS.build-for-testing" 'only-testing:OpenCodeClientTests/Selected Suite'
has "$MOCK_CALLS.test-without-building" 'only-testing:OpenCodeClientTests/Selected Suite'
unset OPENCODE_TEST_ONLY OPENCODE_TEST_REBUILD
run unit_default 0 test_unit.sh
check_argv
has "$MOCK_CALLS.test-without-building" 'only-testing:OpenCodeClientTests'
if /usr/bin/grep -q only-testing "$MOCK_CALLS.build-for-testing"; then fail 'unit default build unexpectedly narrowed'; fi
[ "$RUN" != "$SUCCESS_RUN" ] || fail 'run directories collided'

reject_root() {
  local name=$1 code=0
  : > "$MOCK_CALLS"
  bash "$REPO/scripts/test_ui.sh" > "$WORK/$name.stdout" 2>&1 || code=$?
  [ "$code" = 73 ] || fail "$name: expected root rejection 73, got $code"
  [ ! -s "$MOCK_CALLS" ] || fail "$name ran xcodebuild"
  if /usr/bin/grep -Eq 'Test artifacts:|diagnostic-|command-begin' "$WORK/$name.stdout"; then fail "$name emitted full logs"; fi
  count=$((count + 1))
  printf 'PASS %s (root rejected before logs)\n' "$name"
}
GOOD_ROOT=$OPENCODE_TEST_OUTPUT_ROOT
unset OPENCODE_TEST_OUTPUT_ROOT
run default_ignored_root 0
case "$RUN" in "$REPO/.occlient/test-runs/"*) ;; *) fail 'default root moved';; esac
export OPENCODE_TEST_OUTPUT_ROOT="$REPO/unignored output"
reject_root unignored_root
[ ! -e "$OPENCODE_TEST_OUTPUT_ROOT" ] || fail 'unignored root created'
export OPENCODE_TEST_OUTPUT_ROOT="$WORK/external output"
reject_root external_root
[ ! -e "$OPENCODE_TEST_OUTPUT_ROOT" ] || fail 'external root created'
export OPENCODE_TEST_OUTPUT_ROOT="$REPO/.occlient/../escaped output"
reject_root dotdot_escape
[ ! -e "$REPO/escaped output" ] || fail 'dotdot root created'
mkdir -p "$WORK/external dir"
ln -s "$WORK/external dir" "$REPO/.occlient/escape link"
export OPENCODE_TEST_OUTPUT_ROOT="$REPO/.occlient/escape link/new output"
reject_root symlink_escape
[ ! -e "$WORK/external dir/new output" ] || fail 'symlink escape created output'
export OPENCODE_TEST_OUTPUT_ROOT="$REPO/.occlient/unignored child" MOCK_UNIGNORED_OUTPUT=1
reject_root ignored_check_failure
[ ! -e "$OPENCODE_TEST_OUTPUT_ROOT" ] || fail 'unignored child created'
unset MOCK_UNIGNORED_OUTPUT
export MOCK_TRACKED_OUTPUT=1 OPENCODE_TEST_OUTPUT_ROOT="$REPO/.occlient/tracked child"
reject_root tracked_descendant
[ ! -e "$OPENCODE_TEST_OUTPUT_ROOT" ] || fail 'tracked child created'
unset MOCK_TRACKED_OUTPUT
: > "$REPO/.occlient/tracked file"
export OPENCODE_TEST_OUTPUT_ROOT="$REPO/.occlient/tracked file"
reject_root tracked_file_path
export MOCK_NESTED_REPO=1 OPENCODE_TEST_OUTPUT_ROOT="$REPO/.occlient/nested repo"
reject_root nested_repo
[ -z "$(ls -A "$OPENCODE_TEST_OUTPUT_ROOT")" ] || fail 'nested repo artifacts created'
unset MOCK_NESTED_REPO
export OPENCODE_TEST_OUTPUT_ROOT="$GOOD_ROOT/unused/../normalized output"
run normalized_ignored_root 0
case "$RUN" in "$GOOD_ROOT/normalized output/"*) ;; *) fail 'root not canonical';; esac
export OPENCODE_TEST_OUTPUT_ROOT="$GOOD_ROOT"
export OPENCODE_TEST_PHASE_TIMEOUT_SECONDS=1 MOCK_HANG=1
run timeout 124
has "$RUN/events.tsv" $'test\ttimeout'
has "$RUN/state.tsv" $'outcome\ttimeout'
has "$RUN/test.status.tsv" $'command_exit\tunknown'
has "$RUN/test.log" first-unfiltered-line
read -r child < "$MOCK_PID.child"
sleep 0.1
if kill -0 "$child" 2>/dev/null; then fail 'owned descendant survived timeout'; fi
unset OPENCODE_TEST_PHASE_TIMEOUT_SECONDS
: > "$MOCK_PID"
bash "$REPO/scripts/test_ui.sh" > "$WORK/interrupt.stdout" 2>&1 &
runner=$!
ready=0
for ((i=0;i<100;i++)); do
  if [ -s "$MOCK_PID" ] && /usr/bin/grep -q first-unfiltered-line "$WORK/interrupt.stdout"; then ready=1; break; fi
  sleep 0.05
done
[ "$ready" = 1 ] || fail 'output was not streamed before process exit'
kill -TERM "$runner"
code=0
wait "$runner" || code=$?
[ "$code" = 143 ] || fail "interrupt exit $code"
RUN=$(/usr/bin/sed -n 's/^Test artifacts: //p' "$WORK/interrupt.stdout")
has "$RUN/state.tsv" $'outcome\tinterrupt'
has "$RUN/events.tsv" $'test\tinterrupt'
has "$RUN/test.status.tsv" $'command_exit\tunknown'
read -r child < "$MOCK_PID.child"
sleep 0.1
if kill -0 "$child" 2>/dev/null; then fail 'owned descendant survived interrupt'; fi
count=$((count + 1))
printf 'PASS interrupt + realtime + descendant cleanup (exit 143)\n'
unset MOCK_HANG

# Real Git boundary regression, entirely within a disposable repository.
mkdir -p "$WORK/device-fakes"
for fake in xcodebuild xcrun tee sysctl; do cp "$WORK/fakes/$fake" "$WORK/device-fakes/"; done
export PATH="$WORK/device-fakes:$BASE_PATH"
REPO="$WORK/real git repo"
mkdir -p "$REPO/scripts"
for script in test_ui.sh test_unit.sh lib_test_observability.sh lib_simulator.sh; do
  cp "$SOURCE/scripts/$script" "$REPO/scripts/"
done
"$REAL_GIT" -C "$REPO" init -q
printf '.occlient/\n' > "$REPO/.gitignore"
unset OPENCODE_TEST_OUTPUT_ROOT
run real_git_default 0
export OPENCODE_TEST_OUTPUT_ROOT="$REPO/.occlient/path with spaces"
run real_git_custom 0 test_unit.sh
check_argv
export OPENCODE_TEST_OUTPUT_ROOT="$REPO/unignored"
reject_root real_git_unignored
[ ! -e "$OPENCODE_TEST_OUTPUT_ROOT" ] || fail 'real Git unignored output created'
ln -s "$WORK/external dir" "$REPO/.occlient/escape"
export OPENCODE_TEST_OUTPUT_ROOT="$REPO/.occlient/escape/output"
reject_root real_git_symlink_escape
# Force a tracked entry into only this temporary index, without a commit.
object=$(printf 'synthetic fixture\n' | "$REAL_GIT" -C "$REPO" hash-object -w --stdin)
"$REAL_GIT" -C "$REPO" update-index --add --cacheinfo "100644,$object,.occlient/forced.txt"
export OPENCODE_TEST_OUTPUT_ROOT="$REPO/.occlient/tracked-output"
reject_root real_git_tracked
"$REAL_GIT" -C "$REPO" update-index --force-remove .occlient/forced.txt
# Re-include a child directory to test real ignore matching, not just containment.
printf '.occlient/*\n!.occlient/unignored/\n' > "$REPO/.gitignore"
export OPENCODE_TEST_OUTPUT_ROOT="$REPO/.occlient/unignored"
reject_root real_git_reincluded_child
[ ! -e "$OPENCODE_TEST_OUTPUT_ROOT" ] || fail 're-included output created'
printf '.occlient/\n' > "$REPO/.gitignore"
mkdir -p "$REPO/.occlient/nested"
"$REAL_GIT" -C "$REPO/.occlient/nested" init -q
export OPENCODE_TEST_OUTPUT_ROOT="$REPO/.occlient/nested/output"
reject_root real_git_nested
export OPENCODE_TEST_OUTPUT_ROOT="$REPO/.occlient/unused/../normalized"
run real_git_normalized 0
printf 'PASS all %s scenarios; artifacts: %s\n' "$count" "$WORK"
