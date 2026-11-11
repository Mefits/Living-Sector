#!/usr/bin/env python3
"""Evaluate the *native* observed outcome; startup != successful AI.

No computed or fabricated stock. All proof comes from the native server audit.
"""
import argparse
import json
from pathlib import Path


def evaluate(summary: dict) -> tuple[str, str]:
    results = summary.get("results")
    if not isinstance(results, list) or len(results) != 1:
        return "ERROR", "Missing exactly one real hybrid execution report"
    result = results[0]
    if result.get("mode") != "hybrid":
        return "ERROR", "Expected a hybrid run, not a baseline/HTN report"
    if result.get("status") != "passed":
        return "ERROR", "New game server did not start and advance ticks normally"
    if result.get("confirmed_terran_earth_water_chains", 0) > 0:
        return "PROVEN", "Terran Earth: native delivery and actual paid water production confirmed; warehouse stock is reported separately"
    if result.get("confirmed_multistep_recipe_chains", 0) > 0:
        return "PARTIAL", "A native production chain was proven, but not the controlled Terran Earth water target"
    if result.get("durable_completed_native_plans", 0) > 0:
        return "PARTIAL", "Native plan finished, but no complete delivery -> recipe chain proven"
    if result.get("confirmed_paid_native_contracts"):
        return "PARTIAL", "Native paid delivery observed; complete production chain NOT proven"
    if result.get("native_contracts_observed"):
        return "PARTIAL", "Native delivery contract posted; payment/recipe NOT proven"
    return "INCONCLUSIVE", "Server ran but no native hybrid delivery observed in this time window"


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--summary", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    args = p.parse_args()
    try:
        state, reason = evaluate(json.loads(args.summary.read_text(encoding="utf-8")))
    except (OSError, ValueError, KeyError) as exc:
        state, reason = "ERROR", f"Cannot read evidence: {exc}"
    message = (f"Native hybrid chain: {state}\n{reason}\n"
               "A healthy server and a ready plan do NOT prove delivery or production.\n"
               "Run checked the *new executable* built from the current archive.\n")
    args.output.write_text(message, encoding="utf-8")
    print(message)
    return 1 if state == "ERROR" else 0


if __name__ == "__main__":
    raise SystemExit(main())
