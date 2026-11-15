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
        and "unified_n21_dock_queue_stage.gd" in n39
        and "func apply_native_n21_request(" in n39
        and "func apply_native_n21_dock_queue(" in n39
        and 'if phase == "dock_queue"' in n158
        and "production.apply_native_n21_dock_queue(" in n158
    )
    add("original_n21_fifo_dock_queue",
        queue_link,
        [rust_dock_path, "godot/scripts/sim/phase2/unified_n21_dock_queue_stage.gd",
         n39_path, n158_path, docking_path],
        "Chat1 N21 real N39 FIFO + real N9 paid dock + N158 tick phase are source-wired. Source N84 timeout and legacy manual Dock still need parity audit; runtime is NOT verified.",
        "SOURCE_LINK_PRESENT", "BLOCKING_SOURCE_GAP")

    # Frozen Rust ShipAction::Dock wait budget is 150 base ticks for a
    # prepaid N104 job, 30 for low morale, 60 otherwise, x multiplier.
    # The nullable N21 cursor belongs to the same persisted N39 ship.
    n84 = read(root, "godot/scripts/sim/phase2/unified_ship_ai_execution.gd")
    add("n21_original_dock_patience_and_replan",
        all(k in n84 for k in [
            "DOCK_WAIT_CONTRACT: int = 150",
            "DOCK_WAIT_DEFAULT: int = 60",
            "DOCK_WAIT_LOW_MORALE: int = 30",
            "DOCK_LOW_MORALE_THRESHOLD: float = 40.0",
            "func _native_dock_wait(",
            'ship["dock_attempt_start_tick"] = tick',
            'ship["dock_attempt_start_tick"] = null',
            "n21_original_dock_wait_timeout",
            # Following the released N104 replan source block, an
            # Accepted contract queues a guarded N146 ReleaseContract;
            # PickedUp resumes N81 from actual cargo. The old proposed
            # n21_paid_contract_retry_after_timeout marker is obsolete.
            "n104_pending_release_on_bt_failure",
            "n104_original_n81_pickedup_resume",
        ]) and
        "dock_attempt_start_tick" in read(
            root, "godot/scripts/sim/phase1/n39_native_world_schema.gd"
        ) and
        "dock_attempt_start_tick" in n158,
        ["native/crates/sim_core/src/agents/ship/actions.rs",
         "native/crates/sim_core/src/agents/ship/mod.rs",
         "godot/scripts/sim/phase2/unified_ship_ai_execution.gd",
         "godot/scripts/sim/phase1/n39_native_world_schema.gd",
         n158_path],
        "Source Dock patience and N38 cursor are wired. Active N104 contract keeps "
        "its prepaid obligation on timeout; full original contract route replan "
        "still needs real end-to-end inspection.",
        "SOURCE_LINK_PRESENT", "BLOCKING_SOURCE_GAP")

    # Never let the legacy manual/debug N15 cargo transfer code silently
    # dock a physical ship for free when N39's N21/N9 is authoritative.
    add("n21_manual_paid_dock_no_legacy_bypass",
        'if action == "dock":' in n158 and
        "n21_manual_dock_requires_paid_native_tick" in n158 and
        "production.apply_native_n21_manual_dock(" in n158 and
        "func apply_native_n21_manual_dock(" in n39 and
        'if action == "dock":\n        return false' in n39 and
        "n21_manual_no_free_paid_slot" in n39,
        [n158_path, n39_path,
         "godot/scripts/sim/phase2/unified_n21_dock_queue_stage.gd"],
        "Explicit user Dock settles in the current committed N39/N9 "
        "tick when a real FIFO-free paid berth exists. Full ports "
        "reject manual queue-jumping; legacy N15 free Dock is disabled.",
        "SOURCE_LINK_PRESENT", "BLOCKING_SOURCE_GAP")

    # Rust N84 BT::Failure emits guarded SimCommand::ReleaseContract.
    # Only Accepted -> Posted is legal; PickedUp reconstructs N81 from
    # physical cargo, without duplicate Buy/Accept or escrow funding.
    n104_release = read(
        root, "godot/scripts/sim/phase2/unified_n104_release_stage.gd"
    )
    n104_resume = read(
        root, "godot/scripts/sim/phase2/unified_n104_contract_resume.gd"
    )
    add("n104_frozen_contract_failure_replanning",
        all(k in n84 for k in [
            "N104Resume.propose(", '"ReleaseContract"',
            "n104_pending_release_on_bt_failure",
            "n104_original_n81_pickedup_resume",
            "n104_original_n81_checkpoint_resume",
        ]) and all(k in n158 for k in [
            'if kind == "ReleaseContract":',
            "production.apply_native_n104_release_contract(",
        ]) and all(k in n39 for k in [
            "func apply_native_n104_release_contract(",
            "NativeN104Release.stage(", "Schema.validate(next)",
            "n104_release_changed_prepaid_n9_escrow",
        ]) and all(k in n104_release for k in [
            'board["status"] = "posted"',
            'board["fulfiller_id"] = ""',
            "reason != \"issuer_funding_failure\"",
            "Relations.bump_standing(", "initial_payment",
        ]) and all(k in n104_resume for k in [
            "Plans.resume_contract_request(", "Goap.plan(",
            "Plans.compile_plan_to_bt_actions(", "n104_resume_would_duplicate_pickup",
            "n104_picked_up_cargo_not_physical",
            "static func _original_gate_edges(",
            "gate_link", "paired_gate_id", '"kind": "gate"',
        ]),
        ["native/crates/sim_core/src/agents/ship/behavior.rs",
         "native/crates/sim_server/src/engine/apply.rs",
         "native/crates/sim_core/src/economy/contracts.rs",
         "godot/scripts/sim/phase2/unified_n104_release_stage.gd",
         "godot/scripts/sim/phase2/unified_n104_contract_resume.gd",
         "godot/scripts/sim/phase2/unified_ship_ai_execution.gd",
         n39_path, n158_path],
        "N104 source: guarded Accepted release and next N153 rebid, exact "
        "penalty, no escrow refund; PickedUp real N81/GOAP resume from "
        "existing cargo. Still needs whole-game Godot acceptance.",
        "SOURCE_LINK_PRESENT", "BLOCKING_SOURCE_GAP")

    # These adapters may exist without being called by the live engine.
    # N80 is direct N158 ship execution. N92 is deliberately mediated
    # by N39: do not misreport the released Chat2 B4 as SOURCE_ONLY just
    # because its pure helper is not preloaded directly by N158.
    exploration = read(
        root, "godot/scripts/sim/phase2/unified_n80_ship_exploration_stage.gd"
    )
    add("n80_idle_exploration_source_apply",
        bool(exploration) and (
            "NativeN80Exploration" in n158 or
            "unified_n80_ship_exploration_stage.gd" in n158),
        ["godot/scripts/sim/phase2/unified_n80_ship_exploration_stage.gd",
         n158_path],
        "Only a direct N158 ship-phase source adapter may claim this bridge.",
        "SOURCE_LINK_PRESENT", "SOURCE_ONLY_NOT_YET_CONNECTED")

    n92 = read(root, "godot/scripts/sim/phase2/unified_n92_colony_aftercare.gd")
    add("n92_colony_aftercare_head_apply",
        bool(n92) and
        'func apply_native_b4_colony_aftercare(' in n39 and
        'NativeB4ColonyAftercare.observe(' in n39 and
        'NativeB4ColonyAftercare.stock_head(' in n39 and
        'production.apply_native_b4_colony_aftercare(' in n158 and
        'func apply_native_hybrid_planning(' in n39 and
        'func apply_native_n121_execution(' in n39,
        ["godot/scripts/sim/phase2/unified_n92_colony_aftercare.gd",
         n39_path, n158_path],
        "Chat2 B4 is source-wired through one N39 planner and N158 faction phase; physical success remains UNVERIFIED.",
        "SOURCE_LINK_PRESENT", "SOURCE_ONLY_NOT_YET_CONNECTED")

    # Rust workforce migration is a separate N92/N147 strategic Head
    # gate: a ready proposal alone is not an N134 migrate_colony decision.
    add("n147_original_head_authorizes_workforce",
        "NativeN147Head.authorize(" in n39 and
        'head_source.get("head", {}) != baseline' in n39 and
        "production.post_native_passenger_migration(" in n158 and
        'var head: Dictionary = _last_n134_result.get(' in n158 and
        'world, _faction_sources, head)' in n158,
        ["native/crates/sim_core/src/strategy/coordination.rs",
         n39_path, n158_path],
        "Source N147 contract must follow the same-faction current-cycle N134 Head grant; no duplicate N104 money.",
        "SOURCE_LINK_PRESENT", "SOURCE_ONLY_NOT_YET_CONNECTED")

    # Native N113 1.20x / 2 REAL decision-cycle confirmation is now a
    # single N147/N39 strategic-memory gate. This statically checks only
    # its call links, not the quality of live source candidate inputs.
    n113 = read(root, "godot/scripts/sim/phase2/unified_n113_strategy_switch.gd")
    n147_head = read(
        root, "godot/scripts/sim/phase2/unified_n147_colony_head_grant.gd"
    )
    candidates_path = (
        "godot/scripts/sim/phase2/unified_n113_original_candidates.gd"
    )
    n113_sources = read(root, candidates_path)
    add("n113_frozen_strategy_hysteresis_in_n147",
        "const SUPERIORITY: float = 1.20" in n113 and
        "const CONFIRMATIONS: int = 2" in n113 and
        "SourceN113.decide(" in n147_head and
        "60 * multiplier" in n147_head and
        "NativeN147Head.authorize(" in n39 and
        "N113_REAL_STRATEGY_NO_N104_CONTRACT" in n39 and
        "Schema.validate(next_world)" in n39 and
        "production.post_native_passenger_migration(" in n158,
        ["native/crates/sim_core/src/strategy/director.rs",
         "godot/scripts/sim/phase2/unified_n113_strategy_switch.gd",
         "godot/scripts/sim/phase2/unified_n147_colony_head_grant.gd",
         n39_path, n158_path],
        "Rust N113 memory, 1.20 threshold, adjacent real-cycle confirmation, and no-payment first vote are source-wired. Gameplay remains UNVERIFIED.",
        "SOURCE_LINK_PRESENT", "SOURCE_ONLY_NOT_YET_CONNECTED")
    add("n113_full_original_candidate_sources",
        "SourceN113Candidates.project(" in n147_head and
        "NativeN147Head.authorize(" in n39 and
        "sources, original, graph, multiplier)" in n39 and
        "ResearchShift.research_ready(" in n113_sources and
        "NativeColonyContracts.active_site(" in n113_sources and
        "NativeNewColony.propose(" in n113_sources and
        "NativeConstruction.observe(" in n113_sources and
        "N111.compare_goal(" in n113_sources,
        [candidates_path,
         "godot/scripts/sim/phase1/n143_native_research_shift.gd",
         "godot/scripts/sim/phase2/unified_n144_new_colony_head.gd",
         "godot/scripts/native_port/n111_options.gd", n39_path],
        "Research, active/new colonies, and current source N154/N111 prior-supply quote are connected. Unknown prior logistics quotes and delegated charter actions remain fail-closed, not synthesized.",
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
