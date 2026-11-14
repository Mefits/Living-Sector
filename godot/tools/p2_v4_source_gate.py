#!/usr/bin/env python3
"""Living Sector P2/V4: inspect SOURCE links, NEVER execute the simulation.

Run after the port reaches SOURCE_INTEGRATION_COMPLETE, before one coordinated
Godot/Windows acceptance. This static audit is not a claim of Godot PASS.
No external dependencies, no repository writes, no Rust/Godot subprocesses.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


PHASES = (
    "bodies", "bodies_regen", "lod", "ships", "apply1", "dock_queue",
    "drains", "facilities", "construction_labor", "populations",
    "markets", "crisis", "apply2", "factions", "progression",
    "colony", "relations", "snapshots", "persistence", "broadcast",
)


def read(root: Path, path: str) -> str:
    src = root / path
    return src.read_text(encoding="utf-8") if src.is_file() else ""


def report(name: str, ok: bool, refs: list[str], note: str,
           status_true: str = "SOURCE_LINK_PRESENT",
           status_false: str = "SOURCE_GAP") -> dict:
    return {
        "name": name,
        "status": status_true if ok else status_false,
        "evidence": refs,
        "note": note,
        "runtime_verified": False,
    }


def audit(root: Path) -> dict:
    rust_engine_path = "native/crates/sim_server/src/engine.rs"
    rust_dock_path = "native/crates/sim_server/src/engine/apply.rs"
    tuning_path = "native/priv/galaxy/data/tuning.json"
    runner_path = "godot/scripts/sim/tick_runner.gd"
    n39_runner_path = "godot/scripts/sim/phase1/n39_native_production_tick_runner.gd"
    n39_path = "godot/scripts/sim/phase1/n39_native_world_production.gd"
    n158_path = "godot/scripts/sim/phase2/n158_production_runtime.gd"
    docking_path = "godot/scripts/sim/ships/docking_registry.gd"
    n38_path = "godot/scripts/sim/save_state.gd"
    engine = read(root, rust_engine_path)
    rust_dock = read(root, rust_dock_path)
    runner = read(root, runner_path)
    p1 = read(root, n39_runner_path)
    n39 = read(root, n39_path)
    n158 = read(root, n158_path)
    docking = read(root, docking_path)
    n38 = read(root, n38_path)

    checks: list[dict] = []
    def add(name: str, ok: bool, refs: list[str], note: str,
            positive: str = "SOURCE_LINK_PRESENT",
            negative: str = "SOURCE_GAP") -> None:
        checks.append(report(name, ok, refs, note, positive, negative))

    m = re.search(
        r"const\s+NATIVE_PHASE_ORDER\s*:[^=]*=\s*\[(.*?)\]",
        runner, re.S,
    )
    actual = tuple(re.findall(r'"([^"]+)"', m.group(1))) if m else ()
    rust_named = tuple(re.findall(r"phase!\((\w+)", engine))
    order_positions = [actual.index(k) for k in rust_named if k in actual]
    add("one_ordered_native_tick", actual == PHASES and
        all(k in actual for k in rust_named) and
        order_positions == sorted(order_positions),
        [rust_engine_path, runner_path],
        "Godot's one phase list retains source engine order; not proof that each phase executes.")

    add("single_world_clock_ledger",
        'extends "res://scripts/sim/tick_runner.gd"' in p1
        and 'extends "res://scripts/sim/phase1/n39_native_production_tick_runner.gd"' in n158
        and "production.run_tick" in p1
        and "var _ledger" in n39 and "var _world" in n39,
        [n39_runner_path, n158_path, n39_path],
        "One N1/N158 tick chain and N39 physical/financial owner.")

    try:
        config = json.loads(read(root, tuning_path))
    except json.JSONDecodeError:
        config = {}
    add("frozen_galaxy_finite_resources_and_ships",
        config.get("auto_replace_retired_ships") is False and
        config.get("regenerate_body_resources") is False,
        [tuning_path, "native/crates/sim_core/src/simulation/tuning.rs"],
        "In this frozen world both legacy automatic resource regen and free retirement respawn are disabled. Do not add them.",
        "SOURCE_POLICY_CONFIRMED", "SOURCE_POLICY_UNRESOLVED")

    add("market_and_crisis_real_apply",
        all(x in n158 for x in [
            "MarketPhase.propose(", "production.apply_market_phase(",
            'if phase == "crisis"', "production.apply_native_crisis_phase(",
            "scheduled_event_due.emit",
        ]) and all(x in n39 for x in [
            "func apply_market_phase(", "func apply_native_crisis_phase(",
        ]),
        [rust_engine_path, n158_path, n39_path],
        "N150, Rust crisis flags, N39 Apply and signal are source-wired; runtime unverified.")

    add("physical_cargo_and_paid_contracts",
        all(x in n158 for x in [
            "NativeAIExecution", "FleetLogistics.command(",
            "production.post_funded_contract(", "N153Dispatch.propose(",
        ]) and all(x in n39 for x in [
            "func apply_fleet_logistics(", "func post_funded_contract(",
        ]),
        [n158_path, n39_path],
        "N153/N104/N15/N21 command entry points exist; continuous autonomous delivery remains UNVERIFIED.")

    add("colony_source_foundation",
        all(x in n39 for x in [
            "func apply_native_colony_foundation(",
            "func apply_native_colony_prepare_docks(",
        ]) and "NativeColonyEstablish" in n39,
        [n39_path, "godot/scripts/sim/phase2/unified_n151_colony_establish.gd"],
        "B1/B2/B3 source colony materialization exists; real end-to-end game progression UNVERIFIED.")

    add("head_planner_durable_execution",
        "func apply_native_hybrid_planning(" in n39
        and "func apply_native_n121_execution(" in n39
        and "NativeN121" in n39 and "NativeHybridPlanning" in n39,
        [n39_path, n158_path],
        "N100/N121 state and paid action entries exist; autonomous goal success UNVERIFIED.")

    add("one_n38_source_restore",
        "func save_runner(" in n38 and "func load_runner(" in n38
        and "NativeCoherence.validate(" in n38
        and "NativeTimeline.validate(" in n38,
        [n38_path, n39_runner_path, n158_path],
        "One N38 save/restore path; final Godot roundtrip and Windows export remain UNVERIFIED.")

    # This is a MATERIAL original gameplay difference, not a skipped API.
    # Rust admits queued ships every tick independently of ship AI cadence.
    queue_link = (
        "tick_dock_queue_advance" in rust_dock
        and "dock_queue" in docking
        and 'phase == "dock_queue"' in n158
    )
    add("original_n21_fifo_dock_queue",
        queue_link,
        [rust_dock_path, docking_path, n158_path],
        "Rust has FIFO queue, stale-entry pruning, per-tick head advance and fees; Godot immediate no_available_dock is not equivalent.",
        "SOURCE_LINK_PRESENT", "BLOCKING_SOURCE_GAP")

    # These adapters may exist without being called by the live engine.
    for name, stage_path, tokens in [
        ("n80_idle_exploration_source_apply",
         "godot/scripts/sim/phase2/unified_n80_ship_exploration_stage.gd",
         ["unified_n80_ship_exploration_stage.gd", "N80ShipExploration"]),
        ("n92_colony_aftercare_head_apply",
         "godot/scripts/sim/phase2/unified_n92_colony_aftercare.gd",
         ["unified_n92_colony_aftercare.gd", "N92ColonyAftercare"]),
    ]:
        stage = read(root, stage_path)
        live = bool(stage) and any(token in n158 for token in tokens)
        add(name, live, [stage_path, n158_path],
            "Having a source proposal is not a live N39/N158 Apply; inspect active chat leases before any shared edit.",
            "SOURCE_LINK_PRESENT", "SOURCE_ONLY_NOT_YET_CONNECTED")

    # Presentation must not claim a phase absent when it really executes.
    method = re.search(
        r"func implemented_phases\([^)]*\).*?(?=\nfunc |\Z)", n158, re.S
    )
    declarations = method.group(0) if method else ""
    wired_crisis = 'if phase == "crisis"' in n158
    add("implemented_phase_registry_coherence",
        not wired_crisis or '"crisis"' in declarations,
        [n158_path],
        "N158 reports implemented phases to callers; include real crisis when wired.",
        "SOURCE_LINK_PRESENT", "DIAGNOSTIC_PARITY_GAP")

    # Check the whole script tree, including every active test's preload.
    scripts = sorted((root / "godot").rglob("*.gd")) if (root / "godot").exists() else []
    missing: list[str] = []
    for src in scripts:
        body = src.read_text(encoding="utf-8")
        for resource in re.findall(r'preload\("res://([^"]+)"\)', body):
            if not (root / "godot" / resource).is_file():
                missing.append(f"{src.relative_to(root)} -> res://{resource}")
    add("all_godot_preload_targets_exist",
        bool(scripts) and not missing,
        ["godot/scripts", "godot/tests"],
        ("No missing resource preloads" if not missing
         else "Missing resources: " + "; ".join(missing[:12])),
        "SOURCE_LINK_PRESENT", "BLOCKING_SOURCE_GAP")

    gaps = [c for c in checks if c["status"] in (
        "BLOCKING_SOURCE_GAP", "DIAGNOSTIC_PARITY_GAP",
        "SOURCE_GAP", "SOURCE_ONLY_NOT_YET_CONNECTED",
        "SOURCE_POLICY_UNRESOLVED",
    )]
    return {
        "tool": "p2_v4_source_gate",
        "source": "frozen Rust Galaxy 0.6.7",
        "runtime_verified": False,
        "read_only": True,
        "checks": checks,
        "unresolved": [c["name"] for c in gaps],
        "conclusion": (
            "SOURCE_INTEGRATION_INCOMPLETE" if gaps
            else "STATIC_REFERENCES_ONLY__GODOT_RUNTIME_UNVERIFIED"
        ),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--repo-root", type=Path,
        default=Path(__file__).resolve().parents[2],
        help="Root of Living-Sector git working tree.",
    )
    parser.add_argument(
        "--json", action="store_true", help="Emit a JSON audit manifest."
    )
    parser.add_argument(
        "--require-complete", action="store_true",
        help="Exit 2 when source gaps remain. Never implies runtime PASS.",
    )
    args = parser.parse_args()
    result = audit(args.repo_root.resolve())
    if args.json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
    else:
        for check in result["checks"]:
            print(f'{check["status"]:32} {check["name"]}')
            if check["status"] not in (
                "SOURCE_LINK_PRESENT", "SOURCE_POLICY_CONFIRMED",
            ):
                print(f'    {check["note"]}')
        print("CONCLUSION:", result["conclusion"])
        print("NOTE: This is NOT a Godot parser, gameplay or Windows test.")
    return 2 if args.require_complete and result["unresolved"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
