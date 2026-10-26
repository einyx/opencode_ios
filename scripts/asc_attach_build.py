#!/usr/bin/env python3
"""Attach an uploaded build to a version and update its review notes.

    python3 scripts/asc_attach_build.py 34
    python3 scripts/asc_attach_build.py 34 --notes-from docs/appstore/review-notes.md

Finds the build with that version number in the app, attaches it to the
version, and writes the review notes.

A version that is already awaiting review is *locked*: Apple refuses both a
new build and new review notes ("A relationship value is not acceptable for
the current resource state"). Such a version has to leave the review queue
first — that means cancelling the submission, which also gives up the place in
the review queue, so it is never done without being asked for. Pass
`--withdraw` to cancel the submission as well; the version is not
re-submitted, because the release is manual.
"""

from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import time

APP_ID = "6826903678"
VERSION_ID = "8fbf4b93-cc24-43d7-8087-83517987cb41"


def call(method: str, path: str, payload: dict | None = None) -> dict:
    """Calls the App Store Connect API through `scripts/asc_api.py`."""
    args = [sys.executable, str(pathlib.Path(__file__).with_name("asc_api.py")), method, path]
    if payload is not None:
        args.append(json.dumps(payload))
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit(f"the API call failed: {result.stderr.strip()}")
    if not result.stdout.strip():
        return {}  # a 204 No Content — the relationship was set
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        raise SystemExit(f"unexpected API response: {result.stdout[:400]}")


def find_build(version: str) -> dict:
    """The build with that version number, once Apple has processed it."""
    for _ in range(60):
        builds = call("GET", f"/v1/apps/{APP_ID}/builds?limit=50").get("data", [])
        for build in builds:
            if build["attributes"]["version"] == version:
                state = build["attributes"]["processingState"]
                if state == "VALID":
                    return build
                if state in ("FAILED", "INVALID"):
                    raise SystemExit(f"build {version} was rejected by Apple: {state}")
                print(f"build {version} is still {state.lower()}; waiting…")
                break
        else:
            print(f"build {version} is not in the list yet; waiting…")
        time.sleep(30)
    raise SystemExit(f"build {version} never became valid")


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 64
    version = sys.argv[1]
    withdraw = "--withdraw" in sys.argv

    version_resource = call("GET", f"/v1/appStoreVersions/{VERSION_ID}")["data"]
    state = version_resource["attributes"]["appStoreState"]
    print(f"version {version_resource['attributes']['versionString']} is {state}")

    if state in ("WAITING_FOR_REVIEW", "IN_REVIEW"):
        if not withdraw:
            print(
                "\nThe version is in the review queue, so Apple locks its build and\n"
                "its review notes. To ship a new build it has to leave the queue\n"
                "first, which gives up the place in the queue:\n\n"
                "  python3 scripts/asc_attach_build.py " + version + " --withdraw\n\n"
                "That cancels the submission and attaches the build; it does not\n"
                "re-submit it — the release is manual.",
            )
            return 1
        print("cancelling the submission so the build can be attached…")
        call("DELETE", f"/v1/appStoreVersionSubmissions/{VERSION_ID}")
        time.sleep(5)

    build = find_build(version)
    build_id = build["id"]
    print(f"attaching build {version} ({build_id})")
    call("PATCH", f"/v1/appStoreVersions/{VERSION_ID}/relationships/build", {
        "data": {"id": build_id, "type": "builds"}
    })

    notes_path = None
    if "--notes-from" in sys.argv:
        notes_path = pathlib.Path(sys.argv[sys.argv.index("--notes-from") + 1])
    if notes_path and notes_path.exists():
        text = notes_path.read_text(encoding="utf-8")
        # The document has a title and a "---" separator; the notes are the
        # part after it.
        body = text.split("---", 1)[1].strip() if "---" in text else text.strip()
        detail = call("GET", f"/v1/appStoreVersions/{VERSION_ID}/appStoreReviewDetail")
        detail_id = detail["data"]["id"]
        # The review-detail PATCH wants the full JSON:API document, unlike the
        # flat bodies the rest of this API takes.
        call("PATCH", f"/v1/appStoreReviewDetails/{detail_id}", {
            "data": {
                "type": "appStoreReviewDetails",
                "id": detail_id,
                "attributes": {"notes": body},
            }
        })
        print(f"review notes updated ({len(body)} chars)")

    final = call("GET", f"/v1/appStoreVersions/{VERSION_ID}?include=build")
    attached = final.get("included", [{}])[0].get("attributes", {}).get("version")
    print(f"version {version_resource['attributes']['versionString']} now carries build {attached}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
