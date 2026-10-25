#!/bin/bash
# Polish lint — source scanner for the Quiet Tech polish rubric.
#
# Enforces the `lint` rows of docs/features/polish/rubric.md. Every finding
# cites the rubric ID it enforces, so a failure is traceable to a rubric row.
# It is a script and not an XCTest because the test bundle runs inside the
# simulator sandbox and cannot read the repository source tree.
#
# Ratchet model (PRY-11): scripts/polish_lint_baseline.txt records every
# violation present at seeding time, one per line. Matching is count-based
# per (file, rule) — line numbers in the baseline are informational, so
# refactors that shift lines do not produce noise. The lint is green while
# the tree holds no MORE violations than the baseline allows and fails the
# moment one is added. The baseline only ever shrinks: `--prune-baseline`
# refuses to write a baseline larger than the one on disk.
#
# Usage:
#   scripts/polish_lint.sh                        # all rules, ratchet on
#   scripts/polish_lint.sh --rules=type,color     # a subset
#   scripts/polish_lint.sh --no-baseline          # raw scan, ignore baseline
#   scripts/polish_lint.sh --seed-baseline        # (re)write the baseline
#   scripts/polish_lint.sh --prune-baseline       # shrink the baseline to now
#   scripts/polish_lint.sh --self-test            # negative test on a fixture
#   scripts/polish_lint.sh --help
#
# Exit codes: 0 clean (or fully baselined) · 1 violations found · 2 usage error.
# `--self-test` deliberately propagates the fixture run's non-zero exit: a
# non-zero exit there is the expected, passing outcome (see PRY-11).
#
# Suppression: append `polish-lint:allow` on the offending line with the rule
# ID, e.g.  `Color.red // polish-lint:allow POL-COLOR-08 stop affordance`.
#
# Conventions follow scripts/lib_simulator.sh: bash 3.2 (no associative
# arrays), BSD-grep only, paths relative to the repo root.

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${POLISH_LINT_ROOT:-$ROOT}"
APP="OpenCodeClient/OpenCodeClient"
VIEWS="$APP/Views"
BASELINE_REL="scripts/polish_lint_baseline.txt"
BASELINE="$ROOT/$BASELINE_REL"

# ---------------------------------------------------------------------------
# Rule catalogue. group | id | hard | pattern | scope | exclude-pattern | message
# hard=1 rules are not baseline-eligible: any hit fails (they are presence
# checks that pass today; a hit means a rubric guarantee was deleted).
# ---------------------------------------------------------------------------
ALL_RULES="type,color,spacing,opacity,motion,haptics,preview"

scan_grep() { # id hard pattern scope exclude message
  local id="$1" hard="$2" pattern="$3" scope="$4" exclude="$5" message="$6" out
  out="$(cd "$ROOT" && grep -rnE "$pattern" "$scope" 2>/dev/null | grep -v 'polish-lint:allow' || true)"
  if [ -n "$exclude" ]; then
    out="$(printf '%s\n' "$out" | grep -vE "$exclude" || true)"
  fi
  [ -z "$out" ] && return 0
  printf '%s\n' "$out" | while IFS= read -r line; do
    printf '%s: %s: %s\n' "$line" "$id" "$message"
  done >>"$FOUND"
  return 0
}

# Presence rule: fails when the pattern does NOT exist in scope.
require_grep() { # id scope pattern message
  local id="$1" scope="$2" pattern="$3" message="$4"
  if ! (cd "$ROOT" && grep -rqE "$pattern" "$scope" 2>/dev/null); then
    printf '%s:0: %s: %s\n' "$scope" "$id" "$message" >>"$FOUND"
  fi
}

run_rule_group() {
  local group="$1"
  case ",$group," in
    *,color,*)
      # POL-COLOR-08 No raw system colour literal (QT-LANDING)
      scan_grep POL-COLOR-08 0 \
        'Color\.(red|blue|green|orange|purple|pink|yellow|black|white|gray|grey)\b' \
        "$APP" '' 'raw system colour literal — use DesignColors tokens'
      # POL-COLOR-10 There is no second blue (QT-PALETTE)
      scan_grep POL-COLOR-10 0 'Semantic\.info' "$APP" '' \
        'Semantic.info is the forbidden second blue — use Brand.primary'
      # POL-COLOR-11 Error surfaces use accent + explicit text (QT-PALETTE, chat)
      scan_grep POL-COLOR-11 0 'Semantic\.error' "$VIEWS" '' \
        'Semantic.error in a View — error surfaces use accent + explicit text'
      # POL-COLOR-14 Success is a checkmark in text.secondary, never green (QT-PALETTE)
      scan_grep POL-COLOR-14 0 'Semantic\.success' "$APP" '' \
        'Semantic.success is forbidden — success is a checkmark in text.secondary'
      # POL-COLOR-15 Warning is gold text with an explanation (QT-PALETTE)
      scan_grep POL-COLOR-15 0 'Semantic\.warning' "$APP" '' \
        'Semantic.warning is forbidden — warning is gold text with an explanation'
      # POL-COLOR-17 No gradients anywhere (QT-NONGOAL)
      scan_grep POL-COLOR-17 0 '\.linearGradient|\.radialGradient|Gradient\(' \
        "$APP" '' 'gradient — the Quiet Tech spec has no gradients'
      ;;
    *,spacing,*)
      # POL-COLOR-19 Spacing comes from DesignSpacing (QT-LANDING)
      scan_grep POL-COLOR-19 0 '\.(padding|spacing)\([^)]*[0-9]' \
        "$VIEWS" 'DesignSpacing' \
        'numeric spacing literal — use DesignSpacing'
      ;;
    *,opacity,*)
      # POL-COLOR-09 Opacity comes from DesignColors.Opacity (QT-LANDING)
      scan_grep POL-COLOR-09 0 '\.opacity\(' "$VIEWS" '' \
        'ad-hoc .opacity( — use DesignColors.Opacity'
      ;;
    *,type,*)
      # POL-TYPE-07 No literal .font(.system(size:)) (QT-LANDING)
      scan_grep POL-TYPE-07 0 '\.system\(size:' "$APP" '' \
        'literal .system(size:) font — use DesignTypography'
      # POL-TYPE-08 No semantic system font in a View (QT-LANDING)
      scan_grep POL-TYPE-08 0 \
        '\.font\(\.(caption2?|body|subheadline|callout|footnote|headline|title2?|title3|largeTitle)\b' \
        "$VIEWS" '' 'semantic system font — use DesignTypography'
      # POL-TYPE-09 Only SF system fonts; no third-party registration outside DesignTokens (QT-TYPE)
      scan_grep POL-TYPE-09 0 '\.custom\("|CTFontCreateWithName|UIFont\(' \
        "$APP" "DesignTokens\\.swift" \
        'font registration outside DesignTokens — the type scale is SF only'
      # POL-TYPE-13 The accessibility probe is a named helper, not inline size: 1 (INIT)
      scan_grep POL-TYPE-13 0 'system\(size: 1\)' "$APP" '' \
        'inline accessibility-probe hack — use Utils/AccessibilityProbe.swift'
      ;;
    *,motion,*)
      # POL-MOTION-02 Tool rows use the custom spring, not DisclosureGroup (QT-MOTION)
      scan_grep POL-MOTION-02 0 'DisclosureGroup' "$VIEWS" '' \
        'DisclosureGroup — tool rows expand with the DesignAnimation spring'
      # POL-MOTION-09 Every withAnimation uses a named DesignMotion preset (INIT)
      scan_grep POL-MOTION-09 0 'withAnimation\(\.[a-z]|withAnimation\([0-9]' \
        "$VIEWS" '' \
        'raw animation — every withAnimation uses a named DesignMotion preset'
      ;;
    *,haptics,*)
      # POL-HAPTIC-01..07: each event must keep at least one firing site (QT-HAPTIC).
      # Hard rules: today they pass; a failure means a guarantee was deleted.
      require_grep POL-HAPTIC-01 "$APP" '\.fire\(\.messageSent' \
        'no .messageSent haptic site — sending a message must produce a haptic'
      require_grep POL-HAPTIC-02 "$APP" '\.fire\(\.permissionArrived' \
        'no .permissionArrived haptic site — its signature must differ from every other event'
      require_grep POL-HAPTIC-03 "$APP" '\.fire\(\.questionArrived' \
        'no .questionArrived haptic site — its signature must differ from every other event'
      require_grep POL-HAPTIC-04 "$APP" '\.fire\(\.sendFailed' \
        'no .sendFailed haptic site — a failed send must produce a distinct haptic'
      require_grep POL-HAPTIC-05 "$APP" '\.fire\(\.destructiveConfirmed' \
        'no .destructiveConfirmed haptic site — destructive confirmation needs a distinct haptic'
      require_grep POL-HAPTIC-06 "$APP" '\.fire\(\.selectionChanged' \
        'no .selectionChanged haptic site — selection change needs a distinct haptic'
      require_grep POL-HAPTIC-07 "$APP" '\.fire\(\.recordingStarted|\.fire\(\.recordingStopped' \
        'recording start/stop haptic pair missing'
      ;;
    *,preview,*)
      # POL-PREVIEW-01 Every screen-level View has at least one #Preview (INIT).
      # Threshold follows the audit predicate: fewer than 8 preview-bearing
      # files in the app target is a violation.
      local preview_files
      preview_files="$(cd "$ROOT" && grep -rl '#Preview' "$APP" 2>/dev/null | grep -v 'polish-lint:allow' | wc -l | tr -d ' ')"
      if [ "$preview_files" -lt 8 ]; then
        printf '%s:0: POL-PREVIEW-01: only %s file(s) carry a #Preview — every screen-level View needs one (ratchet target 8+)\n' "$APP" "$preview_files" >>"$FOUND"
      fi
      # POL-PREVIEW-02 Every preview runs on an isolated UserDefaults suite (REPO)
      local f
      while IFS= read -r f; do
        [ -z "$f" ] && continue
        if ! grep -q 'UserDefaults(suiteName:' "$ROOT/$f"; then
          printf '%s:0: POL-PREVIEW-02: preview file without an isolated UserDefaults suite\n' "$f" >>"$FOUND"
        fi
      done <<EOF
$(cd "$ROOT" && grep -rl '#Preview' "$APP" 2>/dev/null || true)
EOF
      ;;
  esac
}

usage() {
  cat <<'HELP'
polish_lint.sh — Quiet Tech polish lint (rubric enforcement)

Usage:
  scripts/polish_lint.sh [options]

Options:
  --rules=LIST      Comma-separated subset of: type,color,spacing,opacity,
                    motion,haptics,preview (default: all)
  --no-baseline     Ignore the ratchet baseline; report every violation
  --seed-baseline   (Re)write scripts/polish_lint_baseline.txt from the
                    current tree — for the first run only
  --prune-baseline  Shrink the baseline to the current tree; refuses to grow
  --self-test       Negative test: lints a deliberately offending fixture and
                    propagates its non-zero exit (that non-zero IS the pass)
  --help            This text

Rules and the rubric rows they enforce (docs/features/polish/rubric.md):

  color
    POL-COLOR-08  No raw system colour literal in the app target (QT-LANDING)
    POL-COLOR-10  No second blue: Semantic.info must not exist (QT-PALETTE)
    POL-COLOR-11  Error surfaces use accent + explicit text, in Views (QT-PALETTE)
    POL-COLOR-14  No Semantic.success — success is text.secondary (QT-PALETTE)
    POL-COLOR-15  No Semantic.warning — warning is gold text (QT-PALETTE)
    POL-COLOR-17  No gradients anywhere (QT-NONGOAL)
  spacing
    POL-COLOR-19  No numeric .padding/.spacing literal outside DesignSpacing (QT-LANDING)
  opacity
    POL-COLOR-09  No ad-hoc .opacity( in Views (QT-LANDING)
  type
    POL-TYPE-07   No literal .font(.system(size:)) (QT-LANDING)
    POL-TYPE-08   No semantic system font in a View (QT-LANDING)
    POL-TYPE-09   No font registration outside DesignTokens (QT-TYPE)
    POL-TYPE-13   No inline system(size: 1) accessibility probe (INIT)
  motion
    POL-MOTION-02 No DisclosureGroup — the DesignAnimation spring expands rows (QT-MOTION)
    POL-MOTION-09 Every withAnimation uses a named DesignMotion preset (INIT)
  haptics (presence, not baseline-eligible)
    POL-HAPTIC-01 .messageSent fires
    POL-HAPTIC-02 .permissionArrived fires
    POL-HAPTIC-03 .questionArrived fires
    POL-HAPTIC-04 .sendFailed fires
    POL-HAPTIC-05 .destructiveConfirmed fires
    POL-HAPTIC-06 .selectionChanged fires
    POL-HAPTIC-07 .recordingStarted/.recordingStopped fire
  preview
    POL-PREVIEW-01 At least 8 files carry a #Preview (audit predicate) (INIT)
    POL-PREVIEW-02 Every preview file isolates UserDefaults (REPO)

Output: file:line: POL-XXX-NN: message — every message cites its rubric ID.
Exit: 0 clean or fully baselined · 1 violations · 2 usage error.
HELP
}

FOUND="$(mktemp "${TMPDIR:-/tmp}/polish_lint_found.XXXXXX")"
trap 'rm -f "$FOUND"' EXIT
: >"$FOUND"

RULES="$ALL_RULES"
MODE="check"
while [ $# -gt 0 ]; do
  case "$1" in
    --rules=*)
      RULES="${1#--rules=}"
      [ -n "$RULES" ] || { echo "polish_lint: --rules= needs a list" >&2; exit 2; }
      ;;
    --no-baseline) MODE="check-raw" ;;
    --seed-baseline) MODE="seed" ;;
    --prune-baseline) MODE="prune" ;;
    --self-test) MODE="selftest" ;;
    --help|-h) usage; exit 0 ;;
    *) echo "polish_lint: unknown argument: $1 (see --help)" >&2; exit 2 ;;
  esac
  shift
done

IFS=',' read -r -a RULE_LIST <<<"$RULES"
for r in "${RULE_LIST[@]}"; do
  case ",$ALL_RULES," in
    *",$r,"*) ;;
    *) echo "polish_lint: unknown rule '$r' (valid: $ALL_RULES)" >&2; exit 2 ;;
  esac
done

for r in "${RULE_LIST[@]}"; do
  run_rule_group "$r"
done

# --- self-test ---------------------------------------------------------------
if [ "$MODE" = "selftest" ]; then
  SELFROOT="$(mktemp -d "${TMPDIR:-/tmp}/polish_lint_selftest.XXXXXX")"
  # Mirror the real layout: the lint scans $ROOT/OpenCodeClient/OpenCodeClient.
  mkdir -p "$SELFROOT/OpenCodeClient/OpenCodeClient/Views"
  cat >"$SELFROOT/OpenCodeClient/OpenCodeClient/Views/SelfTestView.swift" <<'FIXTURE'
import SwiftUI

// Deliberately offending fixture for the polish lint negative test.
struct SelfTestView: View {
    var body: some View {
        Color.blue
            .opacity(0.5)
            .padding(12)
            .font(.system(size: 14))
            .font(.caption)
            .onTapGesture { withAnimation(.easeIn) {} }
    }
}
FIXTURE
  POLISH_LINT_ROOT="$SELFROOT" "$0" --rules=type,color,spacing,opacity,motion --no-baseline \
    >"$SELFROOT/out.txt" 2>&1 && {
    echo "polish_lint --self-test: FAILED — the lint accepted the offending fixture:"
    cat "$SELFROOT/out.txt"
    rm -rf "$SELFROOT"
    exit 1
  }
  missing=""
  for want in POL-COLOR-08 POL-COLOR-09 POL-COLOR-19 POL-TYPE-07 POL-TYPE-08 POL-MOTION-09; do
    grep -q "$want" "$SELFROOT/out.txt" || missing="$missing $want"
  done
  rm -rf "$SELFROOT"
  if [ -n "$missing" ]; then
    echo "polish_lint --self-test: FAILED — fixture run did not cite:$missing"
    exit 1
  fi
  echo "polish_lint --self-test: OK — the fixture produced violations and a non-zero"
  echo "exit (the expected negative result per PRY-11)."
  exit 1
fi

# --- baseline modes ----------------------------------------------------------
total="$(wc -l <"$FOUND" | tr -d ' ')"

if [ "$MODE" = "seed" ] || [ "$MODE" = "prune" ]; then
  # Baseline format: relpath:RULE — one violation per line (PRY-11).
  # The content between line number and rule ID is arbitrary Swift source
  # (colons included), so anchor on the last POL-*-* token.
  sed -E 's/^([^:]+):[0-9]+:.*(POL-[A-Z]+-[0-9]+):.*/\1:\2/' "$FOUND" \
    | LC_ALL=C sort >"$FOUND.keys"
  newcount="$(wc -l <"$FOUND.keys" | tr -d ' ')"
  if [ "$MODE" = "prune" ] && [ -f "$BASELINE" ]; then
    oldcount="$(wc -l <"$BASELINE" | tr -d ' ')"
    if [ "$newcount" -gt "$oldcount" ]; then
      echo "polish_lint: refusing to prune — the tree holds $newcount violations" >&2
      echo "  against a baseline of $oldcount; the baseline only ever shrinks." >&2
      exit 1
    fi
  fi
  printf '# Polish lint ratchet baseline (PRY-11) — one violation per line.\n' >"$BASELINE"
  printf '# Format: relpath:POL-XXX-NN. Matching is count-based per file+rule,\n' >>"$BASELINE"
  printf '# so refactors that shift line numbers stay green. Shrink only:\n' >>"$BASELINE"
  printf '# fix violations, then re-run with --prune-baseline.\n' >>"$BASELINE"
  cat "$FOUND.keys" >>"$BASELINE"
  echo "polish_lint: baseline written — $newcount violations ($BASELINE_REL)"
  rm -f "$FOUND.keys"
  exit 0
fi

# --- check -------------------------------------------------------------------
if [ "$total" -eq 0 ]; then
  echo "polish_lint: clean ($RULES)"
  exit 0
fi

if [ "$MODE" = "check-raw" ] || [ ! -f "$BASELINE" ]; then
  echo "polish_lint: $total violation(s):"
  cat "$FOUND"
  [ ! -f "$BASELINE" ] && echo "polish_lint: no baseline at $BASELINE_REL — seed one with --seed-baseline." >&2
  exit 1
fi

# Count-based ratchet: per (file, rule), the baseline allows N occurrences.
# Occurrences up to N are grandfathered; growth beyond N fails and reports
# every current occurrence for that pair so the author can see the full set.
keycount() { # file with lines "relpath:RULE" -> print "count key" per key
  sed -E 's/^([^:]+):[0-9]+:.*(POL-[A-Z]+-[0-9]+):.*/\1:\2/' "$1" \
    | LC_ALL=C sort | uniq -c | awk -v OFS=' ' '{ print $1, $2, $3 }'
}

keycount "$FOUND" >"$FOUND.counts"
grep -vE '^#' "$BASELINE" | LC_ALL=C sort >"$BASELINE.keys" || true
keycount "$BASELINE.keys" >"$BASELINE.counts" 2>/dev/null || : >"$BASELINE.counts"

new_total=0
join -j 2 -o 0,1.1,2.1 <(sort -k2 "$FOUND.counts") <(sort -k2 "$BASELINE.counts") \
  | while read -r key found_n base_n; do
      if [ "$found_n" -gt "$base_n" ]; then
        echo "$key $found_n $base_n"
      fi
    done >"$FOUND.excess"

if [ -s "$FOUND.excess" ]; then
  while read -r key found_n base_n; do
    file="${key%:*}"; rule="${key##*:}"
    echo "polish_lint: NEW violations for $rule in $file (baseline allows $base_n, found $found_n):"
    grep -F "$file" "$FOUND" | grep -F "$rule" || true
    new_total=$((new_total + found_n - base_n))
  done <"$FOUND.excess"
fi

# Hard rules and pairs with no baseline entry fail unconditionally.
while read -r n key; do
  rule="${key##*:}"
  case ",$RULE_LIST," in
    *,haptics,*) case "$rule" in POL-HAPTIC-*) continue ;; esac ;;
  esac
  grep -qF "$key" "$BASELINE.counts" 2>/dev/null && continue
  file="${key%:*}"
  echo "polish_lint: NEW violations for $rule in $file (not in baseline):"
  grep -F "$file" "$FOUND" | grep -F "$rule" || true
  new_total=$((new_total + n))
done <"$FOUND.counts"

rm -f "$FOUND.counts" "$BASELINE.counts" "$BASELINE.keys" "$FOUND.keys" "$FOUND.excess"

if [ "$new_total" -eq 0 ]; then
  echo "polish_lint: clean — $total hit(s), all within the ratchet baseline ($RULES)"
  exit 0
fi
echo "polish_lint: $new_total new violation(s) beyond the baseline ($RULES)"
exit 1
