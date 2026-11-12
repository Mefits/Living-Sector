#!/usr/bin/env python3
"""N37: verify frozen Rust asset inventory without copying media into Godot.
Requires Python 3 standard library and a local full Git checkout.
Exit 0: inventory matches; licensing approval is NOT implied.
"""
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "godot/docs/N37_ASSET_INVENTORY.json"

def main():
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    ref = data["source_commit"]
    proc = subprocess.run(
        ["git", "-C", str(ROOT), "ls-tree", "-r", "-l", ref, "--", data["scope"]],
        capture_output=True, text=True, check=False,
    )
    if proc.returncode:
        print("N37_FAIL: frozen Git commit unavailable:", proc.stderr.strip())
        return 2
    actual = {}
    for line in proc.stdout.splitlines():
        meta, path = line.split("\t", 1)
        mode, kind, sha, size = meta.split()
        if kind == "blob":
            actual[path] = (sha, int(size))
    expected = {item["path"]: (item["git_blob_sha"], item["bytes"])
                for item in data["assets"]}
    issues = []
    if len(expected) != len(data["assets"]):
        issues.append("duplicate inventory paths")
    for path in sorted(set(actual) - set(expected)):
        issues.append("unlisted source asset: " + path)
    for path in sorted(set(expected) - set(actual)):
        issues.append("missing source asset: " + path)
    for path in sorted(set(expected) & set(actual)):
        if actual[path] != expected[path]:
            issues.append("changed blob/size: " + path)
    counts = {}
    for item in data["assets"]:
        category = item["category"]
        counts[category] = counts.get(category, 0) + 1
        if item["godot_transfer"] != "blocked_pending_review":
            issues.append("unreviewed transfer approval: " + item["path"])
        if not item["path"].startswith(data["scope"]):
            issues.append("outside scope: " + item["path"])
    if counts != data["counts"]:
        issues.append("category counts disagree")
    if issues:
        for issue in issues:
            print("N37_FAIL:", issue)
        return 1
    print("N37_INVENTORY_PASS:", len(actual), "source files match frozen blob SHA and size")
    print("N37_RIGHTS_PENDING: all transfers blocked until provenance/license review")
    return 0

if __name__ == "__main__":
    sys.exit(main())
