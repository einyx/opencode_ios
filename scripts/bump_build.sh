#!/bin/bash
# Bump the app's build number.
#
#   ./scripts/bump_build.sh            # bump to the next build
#   ./scripts/bump_build.sh 34         # set the build to 34
#   ./scripts/bump_build.sh --show     # print the current build
#
# The build number lives in CURRENT_PROJECT_VERSION of every configuration in
# the Xcode project, so all of them move together — a build that is only
# bumped in some configurations uploads with the wrong number.
#
# The archive script calls this before it archives, so every archive carries
# a fresh build number and no two uploads claim the same one.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$REPO_ROOT/OpenCodeClient/OpenCodeClient.xcodeproj/project.pbxproj"

[ -f "$PROJECT" ] || { echo "error: $PROJECT not found" >&2; exit 1; }

current_build() {
  grep -o 'CURRENT_PROJECT_VERSION = [0-9]*' "$PROJECT" | head -1 | awk '{print $3}'
}

case "${1:-}" in
  --show)
    current_build
    exit 0
    ;;
  "")
    ;;
  *[!0-9]*)
    echo "usage: $(basename "$0") [build number|--show]" >&2
    exit 64
    ;;
esac

CURRENT="$(current_build)"
[ -n "$CURRENT" ] || { echo "error: no CURRENT_PROJECT_VERSION in the project" >&2; exit 1; }

if [ -n "${1:-}" ]; then
  TARGET="$1"
else
  TARGET=$((CURRENT + 1))
fi

if [ "$TARGET" -le "$CURRENT" ]; then
  echo "error: build $TARGET is not newer than the current build $CURRENT" >&2
  exit 1
fi

COUNT=$(grep -c 'CURRENT_PROJECT_VERSION = ' "$PROJECT")
# BSD sed needs an explicit backup suffix; the file is restored right after.
sed -i '' "s/CURRENT_PROJECT_VERSION = $CURRENT;/CURRENT_PROJECT_VERSION = $TARGET;/g" "$PROJECT"

UPDATED=$(current_build)
if [ "$UPDATED" != "$TARGET" ]; then
  echo "error: the build number did not change (still $UPDATED)" >&2
  exit 1
fi

echo "==> Build $CURRENT -> $TARGET ($COUNT configuration(s))"
