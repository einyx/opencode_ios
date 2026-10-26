#!/usr/bin/env python3
"""Attach an uploaded build to a version and update its review notes.

    python3 scripts/asc_attach_build.py 34
    python3 scripts/asc_attach_build.py 34 --notes-from docs/appstore/review-notes.md

Finds the build with that version number in the app, attaches it to the
version 1.0 that is waiting for review, and writes the review notes.

The build has to be processed by Apple first: an upload appears as
`processingState: PROCESSING` for a while, and only a `VALID` build can be
attached.
"""

from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import time

APP_ID = "6826903678"
API = "https://api.appstoreconnect.apple.com"


def call(method: str, path: str, payload: dict | None = None) -> dict:
    """Calls the App Store Connect API through `scripts/asc_api.py`."""
    args = [sys.executable, str(pathlib.Path(__file__).with_name("asc_api.py")), method, path]
    if payload is not None:
        args.append(json.dumps(payload))
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit(f"the API call failed: {result.stderr.strip()}")
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

    versions = call("GET", f"/v1/apps/{APP_ID}/appStoreVersions").get("data", [])
    target = next((v for v in versions if v["attributes"]["versionString"] == "1.0"), None)
    if target is None:
        raise SystemExit("version 1.0 is not in the app")
    print(f"version 1.0 is {target['attributes']['appStoreState']}")

    build = find_build(version)
    build_id = build["id"]
    print(f"attaching build {version} ({build_id})")

    call("PATCH", f"/v1/appStoreVersions/{target['id']}", {
        "relationships": {"build": {"data": {"id": build_id, "type": "builds"}}}
    })

    notes_path = None
    if "--notes-from" in sys.argv:
        notes_path = pathlib.Path(sys.argv[sys.argv.index("--notes-from") + 1])
    if notes_path and notes_path.exists():
        text = notes_path.read_text(encoding="utf-8")
        # The document has a title and a "---" separator; the notes are the
        # part after it.
        body = text.split("---", 1)[1].strip() if "---" in text else text.strip()
        detail = call("GET", f"/v1/appStoreVersions/{target['id']}/appStoreReviewDetail")
        detail_id = detail["data"]["id"]
        call("PATCH", f"/v1/appStoreReviewDetails/{detail_id}", {"notes": body})
        print(f"review notes updated ({len(body)} chars)")

    final = call("GET", f"/v1/appStoreVersions/{target['id']}?include=build")
    attached = final.get("included", [{}])[0].get("attributes", {}).get("version")
    print(f"version 1.0 now carries build {attached}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
