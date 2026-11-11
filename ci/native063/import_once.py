#!/usr/bin/env python3
"""One-time promotion of *pinned* Galaxy 0.6.3 changes to direct Git sources.

Important: the historical overlays are inputs to a SINGLE migration commit,
never part of a production build/runtime. Replays pinned 0.6.3 on a throwaway
copy of the already verified native Galaxy 0.6.2 tree. Copies only changed,
explicitly allowlisted files back into native/, with hash provenance.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

EXPECTED_OVERLAY = "bc26814f9819ad64e32eafe32cd2601e1aa5b201"
ALLOWLIST = {
    "crates/sim_core/src/strategy.rs",
    "crates/sim_core/src/strategy/director.rs",
    "crates/sim_core/src/strategy/economic_proposal.rs",
    "crates/sim_core/src/strategy/coordination.rs",
    "crates/sim_core/src/strategy/economic_mandate.rs",
    "crates/sim_server/src/control.rs",
    "crates/sim_server/src/engine.rs",
    "crates/sim_server/src/snapshot.rs",
    "crates/sim_server/src/runtime.rs",
    "crates/sim_server/src/http/player.rs",
    "crates/sim_server/src/http/api.rs",
    "observer/governance-approvals.html",
    "observer/governance-charter.html",
    "observer/governance-economy.html",
    "observer/governance.html",
}
REQUIRED_NEW = {
    "crates/sim_core/src/strategy/economic_proposal.rs",
    "observer/governance-approvals.html",
}
IGNORED = {".git", "target", "__pycache__", "node_modules", ".pytest_cache"}


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def inventory(root: Path) -> dict[str, str]:
    return {
        p.relative_to(root).as_posix(): digest(p.read_bytes())
        for p in sorted(root.rglob("*"))
        if p.is_file() and not (set(p.relative_to(root).parts) & IGNORED)
    }


def run(args: argparse.Namespace) -> None:
    native = args.native.resolve()
    overlay_repo = args.overlay_repo.resolve()
    repo = Path(__file__).resolve().parents[2]
    if not (native / "Cargo.lock").is_file():
        raise RuntimeError("Editable Galaxy 0.6.2 native sources not found")
    if (native / "crates/sim_core/src/strategy/economic_proposal.rs").exists():
        raise RuntimeError("Galaxy 0.6.3 source already imported; cannot replay twice")
    if not (native / "crates/sim_core/src/strategy/charter.rs").is_file():
        raise RuntimeError("0.6.2 faction charter baseline is missing")
    pinned = subprocess.check_output(
        ["git", "-C", str(overlay_repo), "rev-parse", "HEAD"],
        text=True, timeout=30).strip()
    if pinned != EXPECTED_OVERLAY:
        raise RuntimeError(f"Overlay must be pinned to {EXPECTED_OVERLAY}, got {pinned}")
    overlay = overlay_repo / "ci/galaxy063/apply.py"
    if not overlay.is_file():
        raise RuntimeError("Pinned 0.6.3 importer missing")

    target = overlay_repo / "work/source/Living-Sector-Galaxy-0.2"
    if target.exists():
        raise RuntimeError(f"Refusing to replace migration scratch source: {target}")
    shutil.copytree(native, target, ignore=shutil.ignore_patterns(*IGNORED))
    original = inventory(native)
    before_replay = inventory(target)
    if before_replay != original:
        raise RuntimeError("Migration scratch tree differs from verified 0.6.2 native tree")

    subprocess.run([sys.executable, str(overlay)], cwd=overlay_repo, check=True, timeout=180)
    updated = inventory(target)
    if set(original) - set(updated):
        raise RuntimeError("Galaxy 0.6.3 migration deleted original source files")
    changed = sorted(k for k in set(original) | set(updated)
                     if original.get(k) != updated.get(k))
    unexpected = set(changed) - ALLOWLIST
    if unexpected:
        raise RuntimeError("Galaxy 0.6.3 modified unknown files: " + repr(sorted(unexpected)))
    if not REQUIRED_NEW.issubset(set(changed)):
        raise RuntimeError("Expected quoted approval module and UI did not materialize")
    if len(changed) < 10:
        raise RuntimeError(f"Suspiciously small one-time import: {changed!r}")

    # Only at this point mutate native sources; the overlay scripts never run
    # directly inside native/ or during regular compilation.
    for relative in changed:
        dest = native / relative
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(target / relative, dest)

    after = inventory(native)
    if after != updated:
        raise RuntimeError("Promoted direct source differs from audited 0.6.3 replay")
    manifest = {
        "schema": "living-sector-galaxy063-native-promotion-v1",
        "source_version": "Galaxy 0.6.2 editable native Git tree",
        "target_version": "Galaxy 0.6.3 direct native Git tree",
        "base_native_checkout_git_sha": subprocess.check_output(
            ["git", "-C", str(repo), "rev-parse", "HEAD"],
            text=True, timeout=30).strip(),
        "one_time_overlay_source_sha": pinned,
        "overlay_used_only_for_one_time_source_migration": True,
        "regular_builds_require_no_overlay": True,
        "files_modified": len(changed),
        "before_source_files": len(original),
        "after_source_files": len(after),
        "changed_paths": [
            {"path": k, "sha256_before": original.get(k), "sha256_after": after.get(k)}
            for k in changed
        ],
        "full_after_tree_sha256": digest("".join(
            f"{k}\0{v}\n" for k, v in sorted(after.items())).encode("utf-8")),
        "scope": "0.6.3 approval proposals, native command, decision console, tests",
        "explicitly_not_included": [
            "experimental gas balance PR #70",
            "S1/S2 gas dispatch corrections on separate branches",
            "planetary gameplay",
            "real save compatibility proof",
        ],
    }
    out = args.out.resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
                   encoding="utf-8")
    print(json.dumps({
        "source_files": len(after),
        "changed_files": changed,
        "tree_sha256": manifest["full_after_tree_sha256"],
        "pinned_overlay": pinned,
        "regular_build": "native Rust code only, NO overlays",
    }, ensure_ascii=True), flush=True)


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--native", type=Path, required=True)
    p.add_argument("--overlay-repo", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    run(p.parse_args())
