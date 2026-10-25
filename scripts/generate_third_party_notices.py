#!/usr/bin/env python3
"""Generate the third-party licence notices.

The app ships the licences of the packages it links, so the notices have to
follow the resolved package graph. The versions come from
`Package.resolved` and the licence metadata from
`scripts/third_party_licenses.json`; the licence texts live in `licenses/`.

    python3 scripts/generate_third_party_notices.py

Writes:
  THIRD_PARTY_NOTICES.md                        (repository root)
  OpenCodeClient/OpenCodeClient/Resources/ThirdPartyNotices.txt  (bundled in the app)

A package that is resolved but not described in the metadata is an error: the
notices would otherwise silently miss a dependency.
"""

from __future__ import annotations

import json
import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
METADATA = REPO / "scripts" / "third_party_licenses.json"
LICENSES = REPO / "licenses"
RESOLVED = (
    REPO
    / "OpenCodeClient"
    / "OpenCodeClient.xcodeproj"
    / "project.xcworkspace"
    / "xcshareddata"
    / "swiftpm"
    / "Package.resolved"
)
MARKDOWN_OUT = REPO / "THIRD_PARTY_NOTICES.md"
APP_OUT = REPO / "OpenCodeClient" / "OpenCodeClient" / "Resources" / "ThirdPartyNotices.txt"


def main() -> int:
    metadata = json.loads(METADATA.read_text())
    resolved = json.loads(RESOLVED.read_text())
    pins = {pin["identity"]: pin for pin in resolved.get("pins", [])}

    missing = sorted(set(pins) - set(metadata))
    if missing:
        print(f"error: no licence metadata for: {', '.join(missing)}", file=sys.stderr)
        print("       add them to scripts/third_party_licenses.json", file=sys.stderr)
        return 1

    entries = []
    for identity in sorted(pins):
        info = metadata[identity]
        version = pins[identity].get("state", {}).get("version") or pins[identity].get("state", {}).get("revision", "")[:12]
        license_text = ""
        if info.get("licenseFile"):
            path = LICENSES / info["licenseFile"]
            if not path.exists():
                print(f"error: missing licence text {path}", file=sys.stderr)
                return 1
            license_text = path.read_text()
        entries.append((identity, info, version, license_text))

    unlicensed = [e[1]["name"] for e in entries if e[1]["spdx"] == "NOASSERTION"]

    # The text the app shows.
    app_lines = [
        "Third-party licences",
        "",
        "This app links the packages below. Their licences are reproduced here in full.",
        "",
    ]
    for identity, info, version, license_text in entries:
        app_lines.append(f"{info['name']} {version}")
        app_lines.append(f"{info['url']}")
        app_lines.append(f"Licence: {info['spdx']}")
        if info.get("copyright"):
            app_lines.append(info["copyright"])
        if info.get("notice"):
            app_lines.append("")
            app_lines.append(info["notice"])
        if license_text:
            app_lines.append("")
            app_lines.append(license_text.strip())
        else:
            app_lines.append("")
            app_lines.append(info.get("note") or "No licence text is available for this package.")
        app_lines.append("")
        app_lines.append("-" * 72)
        app_lines.append("")
    APP_OUT.parent.mkdir(parents=True, exist_ok=True)
    APP_OUT.write_text("\n".join(app_lines).rstrip() + "\n")

    # The human-readable file in the repository.
    md = [
        "# Third-party licences",
        "",
        "This app links the packages below. The licences are reproduced in full in",
        "[`OpenCodeClient/OpenCodeClient/Resources/ThirdPartyNotices.txt`](OpenCodeClient/OpenCodeClient/Resources/ThirdPartyNotices.txt),",
        "which ships inside the app and is shown under Settings → About → Open source licences.",
        "",
        "The file is generated from `Package.resolved` and `scripts/third_party_licenses.json`:",
        "run `python3 scripts/generate_third_party_notices.py` after changing a dependency.",
        "",
        "| Package | Version | Licence |",
        "|---|---|---|",
    ]
    for identity, info, version, _ in entries:
        md.append(f"| {info['name']} | {version} | {info['spdx']} |")
    md.append("")
    if unlicensed:
        md.append("## Packages without a licence")
        md.append("")
        for identity, info, version, _ in entries:
            if info["spdx"] == "NOASSERTION":
                md.append(f"- **{info['name']} {version}** ({info['url']}): {info.get('note', 'no licence')}")
        md.append("")
    MARKDOWN_OUT.write_text("\n".join(md).rstrip() + "\n")

    print(f"wrote {MARKDOWN_OUT.relative_to(REPO)}")
    print(f"wrote {APP_OUT.relative_to(REPO)}")
    if unlicensed:
        print(f"warning: no licence for: {', '.join(unlicensed)}")
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
