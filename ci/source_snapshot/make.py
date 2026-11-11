#!/usr/bin/env python3
"""Rebuild the precise 0.6.2 source input of a green Windows CI, no Cargo.

Not a new game version. Creates a portable fully editable tree and manifest
from the source archive + the SAME ordered overlay scripts at the pinned
CI commit. Does not merge or rewrite main/stable.
"""
from __future__ import annotations
import hashlib,json,os,shutil,subprocess,sys,zipfile
from pathlib import Path
from datetime import datetime,timezone

ROOT=Path(__file__).resolve().parents[2]
HARNESS=ROOT/"work/harness"
SOURCE=HARNESS/"work/source/Living-Sector-Galaxy-0.2"
ART=HARNESS/"work/art"
OUT=ROOT/"source-snapshot-results"
DEST=OUT/"Living-Sector-Galaxy-0.6.2-SOURCE"
PINNED="4ffd80002ec74b4af3eccb0db5279578c1148e0a"
BUILDRUN="42990801593"
IGNORED={".git","target","node_modules","__pycache__",".pytest_cache",".cargo"}

def sha(path:Path)->str:
    h=hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda:f.read(1024*1024),b""):h.update(chunk)
    return h.hexdigest()

def files(root:Path):
    return sorted((p for p in root.rglob("*") if p.is_file()
        and not any(part in IGNORED for part in p.relative_to(root).parts)),
        key=lambda p:p.relative_to(root).as_posix())

def version(command):
    try:return subprocess.check_output(command,stderr=subprocess.STDOUT,
       timeout=20,text=True).strip()
    except Exception as e:return f"unavailable: {type(e).__name__}"

def main():
    if not (SOURCE/"Cargo.lock").is_file() or not (SOURCE/"crates/sim_core").is_dir():
        raise RuntimeError("No replayed native source; check exact overlay sequence")
    for relative in ("crates/sim_core/src/strategy/governance.rs",
                     "crates/sim_core/src/strategy/economic_mandate.rs",
                     "crates/sim_core/src/strategy/charter.rs",
                     "observer/governance-charter.html"):
        if not (SOURCE/relative).is_file():
            raise RuntimeError("Missing expected Galaxy 0.6.2 source: "+relative)
    if DEST.exists():raise RuntimeError("Refuse to overwrite previous snapshot")
    OUT.mkdir(exist_ok=True)
    shutil.copytree(SOURCE,DEST,ignore=shutil.ignore_patterns(
        "target",".git","node_modules","__pycache__",".pytest_cache"))
    copied=files(DEST)
    if not copied:raise RuntimeError("Source tree empty after reconstruction")
    source_index={}
    overall=hashlib.sha256()
    for p in copied:
        rel=p.relative_to(DEST).as_posix()
        digest=sha(p)
        source_index[rel]=digest
        overall.update((rel+"\0"+digest+"\n").encode("utf8"))
    tree_hash=overall.hexdigest()
    work=HARNESS/"work/input"
    originals={
        "outer_bundle":HARNESS/"ci-input/LS-GALAXY-03-CI-INPUT.zip",
        "base_source_bundle":work/"LS-AI-BLOCK-IV-SOURCES.zip",
        "reference_art_bundle":work/"Living-Sector-Art-Catalog-v0.4.zip",
    }
    if not all(p.is_file() for p in originals.values()):
        raise RuntimeError("Missing pinned input ZIP(s)")
    inputs={name:{"path":str(p.relative_to(HARNESS)).replace("\\","/"),
                  "sha256":sha(p)} for name,p in originals.items()}
    overlays=[
        "ci/fix_galaxy_sources.py",
        "ci/galaxy04/apply.py",
        "ci/galaxy05/apply.py",
        "ci/galaxy06/apply.py",
        "ci/galaxy061/apply.py",
        "ci/galaxy062/apply.py",
    ]
    for rel in overlays:
        if not (HARNESS/rel).exists():
            raise RuntimeError("Missing pinned overlay: "+rel)
    overlay_hashes=[{"path":path,"sha256":sha(HARNESS/path)}
                    for path in overlays]
    # Save auxiliary art as a clearly separate, non-canonical source asset.
    # It is part of the standalone Windows package, not a Rust crate.
    art_manifest={"files":len(files(ART)),"sha256_by_path":{
        p.relative_to(ART).as_posix():sha(p) for p in files(ART)}}
    manifest={
        "schema_version":"living-sector-source-snapshot-v1",
        "origin":"exact overlay replay, no Cargo compilation in this job",
        "original_windows_ci_run_id":BUILDRUN,
        "verified_replay_commit":PINNED,
        "snapshot_workflow_commit":os.environ.get("GITHUB_SHA"),
        "rustc_version_on_snapshot_runner":version(["rustc","--version"]),
        "python_version":sys.version,
        "node_version_on_snapshot_runner":version(["node","--version"]),
        "input_archives":inputs,
        "overlays_in_applied_order":overlay_hashes,
        "cargo_lock_sha256":sha(DEST/"Cargo.lock"),
        "tree_hash_algorithm":"SHA256(join sorted(relative_path + NUL + content_SHA256 + LF))",
        "full_source_tree_sha256":tree_hash,
        "source_files":len(copied),
        "artifact_files_excluded":["target",".git","__pycache__","node_modules"],
        "reference_art_files":len(art_manifest["sha256_by_path"]),
        "notes":[
            "This source is replayed from the EXACT Git commit used by the passing 0.6.2 Windows workflow.",
            "It is not proven byte-for-byte equal to the Rust compiler's generated binary.",
            "No new gameplay features, no main/stable branch edits, no DB migrations.",
            "Future source patches should target a git branch imported from THIS tree, not append Python text replacements.",
        ],
    }
    for name,value in (("SOURCE-MANIFEST.json",manifest),
                       ("SOURCE-FILES-SHA256.json",source_index),
                       ("ART-FILES-SHA256.json",art_manifest)):
        (OUT/name).write_text(json.dumps(value,indent=2,ensure_ascii=False)+"\n",
                             encoding="utf8")
    md=[
        "# Living Sector Galaxy 0.6.2 — source manifest",
        "",
        f"Verified Windows build: https://github.com/Mefits/Living-Sector/actions/runs/{BUILDRUN}",
        f"Pinned source+overlay commit: {PINNED}",
        f"Files: {len(copied)}; SHA256 source tree: {tree_hash}",
        "",
        "This is a complete editable tree, not an additional Python overlay.",
        "It was generated by replaying the exact source+overlay inputs from the green Windows build.",
        "No Cargo compilation was performed while creating this snapshot;",
        "compiler output equivalence is NOT asserted from source hash alone.",
        "",
        "## Inputs SHA256",
    ]
    md.extend(f"- {n}: {v['sha256']}" for n,v in inputs.items())
    md.extend(["","## Overlays, exact order"])
    md.extend(f"- {x['path']} — {x['sha256']}" for x in overlay_hashes)
    md.extend(["","## Transition",
       "Create the next direct-source development branch from this tree;",
       "keep the replay pipeline only as a recovery reference.",
       "Before replacing the old build process, compile the direct-source",
       "tree and run the SAME Windows smoke and economic checks.",
       "Do not assume existing SQLite saves migrate without a separate test.",
       ""])
    (OUT/"SOURCE-MANIFEST.md").write_text("\n".join(md),encoding="utf8")
    zip_path=OUT/"Living-Sector-Galaxy-0.6.2-SOURCE.zip"
    with zipfile.ZipFile(zip_path,"w",compression=zipfile.ZIP_DEFLATED,
                         compresslevel=7,allowZip64=True) as out:
        for p in copied:
            rel=Path("Living-Sector-Galaxy-0.6.2-SOURCE")/p.relative_to(DEST)
            out.write(p,rel.as_posix())
        for name in ("SOURCE-MANIFEST.json","SOURCE-MANIFEST.md",
                     "SOURCE-FILES-SHA256.json","ART-FILES-SHA256.json"):
            out.write(OUT/name,name)
    (OUT/"SOURCE-ZIP-SHA256.txt").write_text(
        sha(zip_path)+"  "+zip_path.name+"\n",encoding="utf8")
    print(json.dumps({"source_files":len(copied),"tree_sha256":tree_hash,
        "zip_sha256":sha(zip_path),"zip_bytes":zip_path.stat().st_size,
        "origin_run":BUILDRUN},indent=2),flush=True)

if __name__=="__main__":main()
