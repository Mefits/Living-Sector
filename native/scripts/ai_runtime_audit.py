#!/usr/bin/env python3
"""Observe REAL Genesis execution; never simulate contracts, money or cargo.

Each mode starts a freshly compiled game server on its own empty SQLite database.
A PASS here means the server ran and was observable, NOT that a plan succeeded.
Native success evidence requires an identified contract with status Paid (or a
confirmed production receipt). Unobserved results stay inconclusive.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import socket
import subprocess
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


NATIVE_TAG = "strategy.logistics.v1"
NATIVE_MODES = {"native_htn_opt_in", "native_hybrid_opt_in"}


def read_json(port: int, path: str, timeout: float = 3.0):
    url = f"http://127.0.0.1:{port}{path}"
    req = Request(url, headers={"Accept": "application/json"})
    with urlopen(req, timeout=timeout) as response:
        if response.status != 200:
            raise ValueError(f"{path}: HTTP {response.status}")
        data = response.read(8_000_001)
        if len(data) > 8_000_000:
            raise ValueError(f"{path}: response exceeds safety limit")
        return json.loads(data)


def port_free() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return int(s.getsockname()[1])


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fp:
        for chunk in iter(lambda: fp.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def record_view(strategy: dict, contracts: dict, mode: str, previously_seen: dict):
    """Parse exposed JSON fields, never infer a simulated or expected event."""
    heads = []
    for entry in strategy.get("factions", []):
        if not isinstance(entry, dict):
            continue
        faction = entry.get("faction_id")
        head = entry.get("head") or {}
        if not isinstance(head, dict):
            continue
        native = head.get("htn_execution")
        if isinstance(native, dict) and native.get("mode") in NATIVE_MODES:
            heads.append({
                "faction_id": faction,
                "mode": native.get("mode"),
                "plan_id": native.get("plan_id"),
                "status": native.get("status"),
                "reason": native.get("reason"),
                "step_id": native.get("step_id"),
                "native_order_id": native.get("native_order_id"),
                "committed_credits": native.get("committed_credits"),
                "planner_id": native.get("planner_id"),
            })
    # A durable plan survives the short interval between coordination events;
    # exposing this through /api/strategy avoids losing real native receipts.
    ledger_events = []
    durable = strategy.get("ai_execution") or {}
    for faction, plan in (durable.get("active") or {}).items():
        ledger = plan.get("ledger") or {}
        for record in ledger.get("steps", []):
            if not isinstance(record, dict):
                continue
            ledger_events.append({
                "faction_id": faction, "plan_id": ledger.get("plan_id"),
                "planner_id": ledger.get("planner_id"),
                "step_id": (record.get("step") or {}).get("step_id"),
                "phase": record.get("phase"),
                "native_order_id": record.get("native_order_id"),
                "reason_code": record.get("reason_code"),
            })
            oid = record.get("native_order_id")
            if oid and not str(oid).startswith("facility:"):
                previously_seen[str(oid)] = faction
    terminal_events = []
    for outcome in durable.get("history", []):
        if not isinstance(outcome, dict):
            continue
        steps = outcome.get("steps") or []
        terminal_events.append({
            "faction_id": outcome.get("faction_id"),
            "plan_id": outcome.get("plan_id"),
            "planner_id": outcome.get("planner_id"),
            "final_status": outcome.get("final_status"),
            "reason": outcome.get("reason"),
            "tick": outcome.get("tick"),
            "goal": outcome.get("goal"),
            "observed_goal_stock": outcome.get("observed_goal_stock"),
            "produced_goal_units": outcome.get("produced_goal_units"),
            "required_goal_production_units": outcome.get("required_goal_production_units"),
            "steps": [{"step_id": (step.get("step") or {}).get("step_id"),
                       "phase": step.get("phase"),
                       "native_order_id": step.get("native_order_id"),
                       "reason_code": step.get("reason_code")}
                      for step in steps if isinstance(step, dict)]
        })
        for step in steps:
            if not isinstance(step, dict):
                continue
            oid = step.get("native_order_id")
            if oid and not str(oid).startswith("facility:"):
                previously_seen[str(oid)] = str(outcome.get("faction_id"))
    board = contracts.get("data", [])
    if not isinstance(board, list):
        raise ValueError("contracts.data should be a list")
    by_id = {str(c["id"]): c for c in board if isinstance(c, dict) and c.get("id")}
    for h in heads:
        oid = h.get("native_order_id")
        if oid and not str(oid).startswith("facility:"):
            previously_seen[str(oid)] = h.get("faction_id")
    native_receipts = []
    for oid, faction in sorted(previously_seen.items()):
        contract = by_id.get(oid)
        if contract is not None:
            native_receipts.append({
                "contract_id": oid,
                "faction_id": faction,
                "status": contract.get("status"),
                "requestor_id": contract.get("requestor_id"),
                "mission_category": contract.get("mission_category"),
                "reserved_credits": (contract.get("funding") or {}).get("reserved")
                if isinstance(contract.get("funding"), dict) else None,
            })
    # Missing or stale contract records are NOT interpreted as completed.
    return heads, native_receipts, ledger_events, terminal_events


def confirmed_goal_outcome(outcome: dict) -> bool:
    """Strict native evidence of EITHER remaining stock OR actual production.

    Consumed water can be truly produced but absent from the market. Never
    pretend its present stock meets a stocking target; certify output via the
    durable cumulative paid-recipe counters instead.
    """
    if outcome.get("final_status") != "completed":
        return False
    steps = outcome.get("steps") or []
    if not steps or any(s.get("phase") != "succeeded" or not s.get("native_order_id") for s in steps):
        return False
    goal = outcome.get("goal")
    if not isinstance(goal, dict):
        return False
    target = goal.get("target_units")
    if isinstance(target, bool) or not isinstance(target, int) or target <= 0:
        return False
    reason = outcome.get("reason")
    if reason == "native_receipts_and_goal_stock_confirmed":
        stock = outcome.get("observed_goal_stock")
        return (isinstance(stock, (float, int)) and not isinstance(stock, bool)
                and math.isfinite(stock) and stock >= target)
    if reason == "native_recipe_receipts_and_goal_production_confirmed":
        output = outcome.get("produced_goal_units")
        required = outcome.get("required_goal_production_units")
        return (isinstance(required, int) and not isinstance(required, bool)
                and required > 0 and required <= target
                and isinstance(output, (float, int)) and not isinstance(output, bool)
                and math.isfinite(output) and output + 0.0001 >= required
                and any(str(step.get("native_order_id", "")).startswith("facility:")
                        and step.get("reason_code") == "native_recipe_paid_and_output_counter_confirmed"
                        for step in steps))
    return False


def has_native_recipe_chain(outcome: dict) -> bool:
    """Distinguish complete delivery -> paid production from easy one-step runs."""
    if not confirmed_goal_outcome(outcome):
        return False
    steps = outcome["steps"]
    return (len(steps) >= 2
            and any(str(s.get("native_order_id", "")).startswith("facility:")
                    and s.get("reason_code") in (
                        "native_recipe_paid_and_step_stock_confirmed",
                        "native_recipe_paid_and_output_counter_confirmed")
                    for s in steps)
            and any(not str(s.get("native_order_id", "")).startswith("facility:")
                    and s.get("reason_code") == "native_contract_paid"
                    for s in steps))


def summarise(mode: str, timeline: list, binary_hash: str, exit_code: int | None,
              error: str | None) -> dict:
    valid = [s for s in timeline if isinstance(s.get("tick"), int)]
    start_tick = valid[0]["tick"] if valid else None
    end_tick = valid[-1]["tick"] if valid else None
    observed = {}
    statuses = {}
    for snap in timeline:
        for h in snap.get("head_events", []):
            key = (h.get("faction_id"), h.get("plan_id"), h.get("step_id"), h.get("status"), h.get("reason"))
            observed[key] = h
        for receipt in snap.get("native_receipts", []):
            statuses[receipt["contract_id"]] = receipt
    paid = sorted(k for k, value in statuses.items() if str(value.get("status", "")).lower() == "paid"
                  and value.get("mission_category") == NATIVE_TAG)
    submitted = sorted(k for k, value in statuses.items()
                       if value.get("mission_category") == NATIVE_TAG)
    attempts = [h for h in observed.values() if h.get("status") == "submitted"]
    ledger_steps = {}
    for snap in timeline:
        for step in snap.get("ledger_events", []):
            k = (step.get("faction_id"), step.get("plan_id"), step.get("step_id"))
            ledger_steps[k] = step
    succeeded_steps = [s for s in ledger_steps.values() if s.get("phase") == "succeeded"]
    production = [h for h in observed.values() if h.get("reason") == "native_production_confirmed"]
    terminal = {}
    for snap in timeline:
        for outcome in snap.get("terminal_events", []):
            terminal[(outcome.get("faction_id"), outcome.get("plan_id"))] = outcome
    completed = [o for o in terminal.values() if confirmed_goal_outcome(o)]
    recipe_chains = [o for o in completed if has_native_recipe_chain(o)]
    fixture_water_chains = [o for o in recipe_chains
                            if o.get("faction_id") == "terran-authority"
                            and (o.get("goal") or {}).get("destination_id") == "earth-station"
                            and (o.get("goal") or {}).get("commodity") == "water"]
    failed = [o for o in terminal.values() if o.get("final_status") not in ("completed", None)]
    legacy_unverified = [o for o in terminal.values()
                         if o.get("final_status") == "completed" and not confirmed_goal_outcome(o)]
    # Ephemeral head events and durable history may describe the SAME plan;
    # never add their counts. A transient "completed" without final stock is
    # not enough to certify an AI success.
    full_count = len(completed)
    healthy = bool(valid and end_tick > start_tick and not error)
    # Important: lack of evidence in a short run is inconclusive, not failure.
    status = "passed" if healthy else "failed"
    proof = ("native_plan_production_verified" if any(
        o.get("reason") == "native_recipe_receipts_and_goal_production_confirmed"
        for o in completed) else "native_plan_goal_stock_verified") if full_count else (
        "native_delivery_paid" if paid else (
        "native_delivery_submitted" if attempts else "not_observed"))
    return {
        "mode": mode, "binary_sha256": binary_hash,
        "status": status, "status_scope": "server_start_and_tick_progress_only",
        "native_result": proof if mode != "baseline" else "baseline_not_applicable",
        "native_result_status": ("passed" if full_count else ("partial" if paid else "inconclusive"))
                                if mode != "baseline" else "not_applicable",
        "start_tick": start_tick, "end_tick": end_tick,
        "samples": len(timeline), "observed_native_steps": len(observed),
        "native_contracts_observed": submitted,
        "confirmed_paid_native_contracts": paid,
        "confirmed_production_receipts": len(production),
        "last_observed_succeeded_ledger_steps": len(succeeded_steps),
        "completed_native_plan_reports": full_count,
        "durable_completed_native_plans": len(completed),
        "confirmed_multistep_recipe_chains": len(recipe_chains),
        "confirmed_terran_earth_water_chains": len(fixture_water_chains),
        "unverified_legacy_completion_reports": len(legacy_unverified),
        "durable_failed_native_plans": len(failed),
        "exit_code": exit_code, "error": error,
        "caveat": "Snapshot polling can miss short-lived receipts; successful API health does not prove successful AI planning. No cross-mode ranking without RNG parity."
    }


def run_one(binary: Path, root: Path, mode: str, duration: float,
            interval: float, dest: Path, data_dir: Path | None = None,
            open_observer: bool = False) -> dict:
    case = dest / mode
    case.mkdir(parents=True, exist_ok=True)
    db = case / "world.db"
    if db.exists():
        raise FileExistsError(f"Refusing to overwrite an existing test DB: {db}")
    data_dir = data_dir or (root / "priv" / "galaxy" / "data")
    if not data_dir.exists():
        raise FileNotFoundError(f"Missing authentic Galaxy data: {data_dir}")
    env = os.environ.copy()
    env.update({
        "BIND_ADDR": f"127.0.0.1:{port_free()}",
        "DATA_DIR": str(data_dir),
        "DATABASE_PATH": str(db),
        "LIVING_SECTOR_UI_DIR": str(root / "observer"),
        "LIVING_SECTOR_GALAXY": "1", "LIVING_SECTOR_STRATEGY_MODE": "execute",
        "WORLD_SPEED": "16", "LIVING_SECTOR_PLANNER_SHADOW": "0",
        "LIVING_SECTOR_PLANNER_COMPARE": "0",
    })
    if mode == "baseline":
        env.pop("LIVING_SECTOR_PLANNER", None)
    else:
        env["LIVING_SECTOR_PLANNER"] = mode
    port = int(env["BIND_ADDR"].split(":")[-1])
    timeline = []
    error = None
    exit_code = None
    with (case / "stdout.log").open("wb") as out, (case / "stderr.log").open("wb") as err:
        proc = subprocess.Popen([str(binary)], cwd=root, env=env, stdout=out, stderr=err)
        seen_orders: dict[str, str] = {}
        try:
            ready_deadline = time.monotonic() + 35
            while time.monotonic() < ready_deadline:
                if proc.poll() is not None:
                    raise RuntimeError(f"Server quit before becoming ready (exit={proc.returncode})")
                try:
                    health = read_json(port, "/api/health", 1.25)
                    if health.get("status") == "ok":
                        break
                except (URLError, HTTPError, TimeoutError, ConnectionError):
                    pass
                time.sleep(0.25)
            else:
                raise TimeoutError("Server did not expose /api/health within 35s")
            if open_observer:
                # The OBSERVER belongs to this exact new server process and DB;
                # opening a page in the browser never creates a simulation event.
                import webbrowser
                url = f"http://127.0.0.1:{port}/observer"
                print(f"Opening live Genesis Observer: {url}", flush=True)
                webbrowser.open(url)
            deadline = time.monotonic() + duration
            with (case / "events.jsonl").open("w", encoding="utf-8") as fp:
                while time.monotonic() < deadline:
                    if proc.poll() is not None:
                        raise RuntimeError(f"Server exited during observation (exit={proc.returncode})")
                    h = read_json(port, "/api/health")
                    st = read_json(port, "/api/strategy")
                    ct = read_json(port, "/api/contracts")
                    heads, receipts, ledger_events, terminal_events = record_view(st, ct, mode, seen_orders)
                    event = {
                        "tick": h.get("tick"), "strategy_tick": st.get("snapshot_tick"),
                        "contracts_tick": ct.get("tick"),
                        "world_speed": h.get("world_speed"),
                        "head_events": heads, "native_receipts": receipts,
                        "ledger_events": ledger_events, "terminal_events": terminal_events,
                        "contract_count": len(ct.get("data", [])),
                    }
                    timeline.append(event)
                    fp.write(json.dumps(event, ensure_ascii=False, sort_keys=True) + "\n")
                    fp.flush()
                    time.sleep(interval)
        except Exception as ex:
            error = f"{type(ex).__name__}: {ex}"
        finally:
            # A graceful exit preserves the game's SQLite snapshot and WAL.
            if proc.poll() is None:
                proc.terminate()
            try:
                exit_code = proc.wait(timeout=9)
            except subprocess.TimeoutExpired:
                proc.kill()
                exit_code = proc.wait(timeout=5)
                error = (error + "; " if error else "") + "server_shutdown_forced"
    result = summarise(mode, timeline, sha256(binary), exit_code, error)
    (case / "summary.json").write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
    return result


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--binary", type=Path, required=True, help="freshly compiled genesis_server executable")
    p.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    p.add_argument("--output", type=Path, default=None)
    p.add_argument("--modes", default="baseline,htn,hybrid")
    p.add_argument("--seconds", type=float, default=18.0)
    p.add_argument("--interval", type=float, default=0.6)
    p.add_argument("--data-dir", type=Path, default=None,
                   help="isolated, unmodified-during-run native starting scenario")
    p.add_argument("--open-observer", action="store_true",
                   help="open this exact fresh server's live Observer in a browser")
    args = p.parse_args(argv)
    modes = [x.strip().lower() for x in args.modes.split(",")]
    if not modes or any(x not in ("baseline", "htn", "hybrid") for x in modes) or len(set(modes)) != len(modes):
        p.error("--modes expects unique baseline,htn,hybrid names")
    if not (4 <= args.seconds <= 180 and .1 <= args.interval <= 10):
        p.error("require 4<=--seconds<=180 and 0.1<=--interval<=10")
    binary = args.binary.resolve()
    root = args.root.resolve()
    data_dir = args.data_dir.resolve() if args.data_dir else None
    if not binary.is_file():
        p.error(f"binary not found: {binary}")
    output = (args.output or (root / "ai-block-d-results")).resolve()
    output.mkdir(parents=True, exist_ok=True)
    summaries = []
    for mode in modes:
        print(f"Starting independent authentic Genesis run: {mode}", flush=True)
        summaries.append(run_one(binary, root, mode, args.seconds, args.interval,
                                 output, data_dir, open_observer=args.open_observer))
        print(f"  {mode}: {summaries[-1]['status']}; native={summaries[-1]['native_result']}", flush=True)
    result = {"schema_version": 2, "binary": str(binary), "binary_sha256": sha256(binary),
              "start_data_dir": str(data_dir or root / "priv" / "galaxy" / "data"),
              "start_data_sha256": sha256((data_dir or root / "priv" / "galaxy" / "data") / "worlds" / "sol.json"),
              "results": summaries,
              "comparison": "descriptive_only_rng_not_proven_equal"}
    (output / "summary.json").write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
    return 0 if all(x["status"] == "passed" for x in summaries) else 1


if __name__ == "__main__":
    sys.exit(main())
