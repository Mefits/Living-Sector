#!/usr/bin/env python3
"""Test-only short-range gas pressure fixture for REAL native Genesis server.

Never touches the tracked world JSON or any user save.
The shorter Sol-Alpha lane is a diagnostic accelerator, NOT a production
balance/distance change. All goods, purchases, contracts and payouts are
still performed by the actual Windows Genesis economy/ship AI.
"""
from __future__ import annotations
import argparse, json, shutil
from pathlib import Path

def prepare(source: Path, dest: Path):
    if dest.exists():
        shutil.rmtree(dest)
    shutil.copytree(source, dest)
    sol_path=dest/"worlds"/"sol.json"
    alpha_path=dest/"worlds"/"alpha_centauri.json"
    sol=json.loads(sol_path.read_text(encoding="utf-8"))
    alpha=json.loads(alpha_path.read_text(encoding="utf-8"))
    assert len(sol["markets"])==1 and len(alpha["markets"])==1
    sm=sol["markets"][0]
    am=alpha["markets"][0]
    # Demand happens in the native simulation; the pressure is REAL.
    sm["supply"]["gas"]=0
    sm["demand"]["gas"]=8
    am["supply"]["gas"]=6000
    am["prices"]["gas"]=1.5
    # Keep native topology intact and only accelerate ONE existing edge
    # in this throw-away copy (route is otherwise ~120 units).
    lanes=[r for r in sol["travel_routes"] if {
        r.get("from"),r.get("to")}=={"earth-station","alpha-station"}]
    assert len(lanes)==1, "Expected original existing Sol-Alpha corridor"
    original_distance=lanes[0]["distance"]
    lanes[0]["distance"]=6

    haulers=[s for s in sol["ships"] if s["class"]=="hauler"
        and s["faction_id"]=="terran-authority"]
    assert len(haulers)==1, "Expected a single Genesis Huge haul ship"
    hauler=haulers[0]
    assert hauler["fitting"]=={"comms":"comms_t2"}
    hauler["location"]="alpha-station"
    # Avoid choosing a pre-existing expensive metal/food shipment before
    # the gas refinery posts its funded shortage order. All ship credits
    # remain a REAL finite asset, no free purchase or God-mode transaction.
    hauler["credits"]=950
    for path,world in ((sol_path,sol),(alpha_path,alpha)):
        path.write_text(json.dumps(world,ensure_ascii=False,indent=2)+"\n",
                        encoding="utf-8")
    return {"kind":"test-only-real-native-gas-fixture",
            "production_sources_unchanged":True,
            "sol_alpha_route_distance_original":original_distance,
            "sol_alpha_route_distance_test":6,
            "hauler_start":"alpha-station",
            "hauler_start_credits":950,
            "hauler_fitting":hauler["fitting"],
            "earth_initial_gas":sm["supply"]["gas"],
            "alpha_initial_gas":am["supply"]["gas"],
            "alpha_test_gas_price":am["prices"]["gas"],
            "goal":"native refinery-funded gas order must be accepted, physically bought and delivered without economy cheats"}

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--source",type=Path,required=True)
    p.add_argument("--dest",type=Path,required=True)
    p.add_argument("--manifest",type=Path,required=True)
    a=p.parse_args()
    result=prepare(a.source,a.dest)
    a.manifest.parent.mkdir(exist_ok=True,parents=True)
    a.manifest.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",
                          encoding="utf-8")
    print(json.dumps(result,ensure_ascii=True))

if __name__=="__main__":main()
