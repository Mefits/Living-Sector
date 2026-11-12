#!/usr/bin/env python3
"""Read-only provenance audit of frozen Observer static assets; stdlib only."""
import argparse
import json
import re
import subprocess
import sys
from pathlib import PurePosixPath

REFERENCE = "archive/rust-galaxy-067-reference"
ROOT = "native/observer/"
EXT = {".png", ".jpg", ".jpeg", ".svg", ".webp", ".gif", ".woff", ".woff2", ".ttf", ".otf", ".mp3", ".ogg", ".wav", ".ico"}
TEXT = {".html", ".css", ".js", ".mjs"}
REF_RE = re.compile(r"""(?:src|href)\s*=\s*["']([^"']+)["']|url\(\s*["']?([^)"']+)""", re.I)

def git(*args):
    result = subprocess.run(["git", *args], check=True, capture_output=True, text=True)
    return result.stdout

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ref", default=REFERENCE)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    rows = git("ls-tree", "-r", "-l", args.ref, "--", ROOT).splitlines()
    files = {}
    for row in rows:
        meta, path = row.split("\t", 1)
        mode, kind, sha, size = meta.split()
        if kind == "blob":
            files[path] = {"sha": sha, "bytes": int(size)}
    assets = sorted(p for p in files if PurePosixPath(p).suffix.lower() in EXT)
    manifest_path = ROOT + "assets/station-kit/manifest.json"
    manifest = json.loads(git("show", f"{args.ref}:{manifest_path}"))
    declared = [m["path"] for m in manifest["modules"]]
    duplicate = sorted({p for p in declared if declared.count(p) > 1})
    missing = sorted(ROOT + "assets/station-kit/" + p for p in declared if ROOT + "assets/station-kit/" + p not in files)
    references = []
    for path in sorted(files):
        if PurePosixPath(path).suffix.lower() not in TEXT:
            continue
        content = git("show", f"{args.ref}:{path}")
        for match in REF_RE.finditer(content):
            target = (match.group(1) or match.group(2)).strip()
            if target.startswith(("http:", "https:", "//", "data:")):
                references.append({"source": path, "target": target, "kind": "external_or_embedded"})
    report = {
        "reference": args.ref, "observer_files": len(files),
        "physical_media_count": len(assets),
        "physical_media": [{"path": p, **files[p], "license_status": "UNREVIEWED_DO_NOT_COPY"} for p in assets],
        "station_manifest_entries": len(declared),
        "station_manifest_duplicate_paths": duplicate,
        "station_manifest_missing_files": missing,
        "external_or_embedded_references": references,
        "gate": "BLOCKED" if missing or duplicate else "REVIEW_REQUIRED",
        "policy": "Manifest entries are not licensed artwork. Do not auto-download or copy."
    }
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print(f"Observer files: {len(files)}; physical media: {len(assets)}")
        print(f"Station-kit manifest: {len(declared)} paths; missing: {len(missing)}; duplicates: {len(duplicate)}")
        print("Gate:", report["gate"])
        for path in missing:
            print("MISSING:", path)
    return 1 if missing or duplicate else 0

if __name__ == "__main__":
    sys.exit(main())
