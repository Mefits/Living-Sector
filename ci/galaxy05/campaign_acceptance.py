#!/usr/bin/env python3
"""Galaxy05 progression evaluation from REAL native HTTP and WS snapshots.

A lengthy running server is not a successful tech-tree experiment by
itself. This script checks actual bought research, real commodity stock
or production receipts, physically committed upgrades, and core tiers.
It never transforms a proposed/shadow action into a fulfilled milestone.
"""
from __future__ import annotations
import argparse
from collections import Counter
import json
from pathlib import Path

COMMODITIES=("rare_ore","alloys","crystal_ore","quantum_cores")
TECH=("alloytech2","survey2","drilltech2","structuretech2",
      "survey3","drill3","quantumtech3","structuretech3")

def observed(checkpoint:Path)->dict:
    data=json.loads(checkpoint.read_text(encoding="utf8"))
    sources=data["endpoints"]
    report=sources["report"]["value"]
    strategy=sources["strategy"]["value"]
    commanders=strategy.get("commanders",{})
    technologies={fac:sorted(set(c.get("technologies",[])).intersection(TECH))
                  for fac,c in commanders.items()}
    markets=report.get("markets",[])
    physical={c:round(sum(float(m.get("supply",{}).get(c,0)) for m in markets),3)
              for c in COMMODITIES}
    stations=[]
    production=Counter()
    for facility in report.get("facilities",[]):
        if facility.get("type")=="station":
            core=facility.get("station_core",{})
            stations.append({"id":facility.get("id"),"faction":facility.get("faction_id"),
                "location":facility.get("location"),"tier":core.get("tier","t1"),
                "slots":core.get("slot_capacity"),"occupied":core.get("used"),
                "upgrade_target":core.get("upgrade_target"),
                "labor":core.get("upgrade_labor_completed"),
                "blocked":core.get("upgrade_blocked_reason")})
        shift=(facility.get("crew") or {}).get("work_shift") or {}
        for recipe,outputs in (shift.get("produced_outputs") or {}).items():
            for commodity,amount in outputs.items():
                if commodity in COMMODITIES:
                    production[(recipe,commodity)]+=float(amount)
    return {"snapshot_tick":report.get("tick"),"technologies":technologies,
            "physical_stocks":physical,"stations":stations,
            "production_receipts":[{"recipe":r,"commodity":c,"amount":round(v,3)}
                for (r,c),v in sorted(production.items())]}

def analyze(root:Path)->dict:
    checkpoints=[]
    for path in sorted((root/"checkpoints").glob("*-diagnostics.json")):
        checkpoints.append(observed(path))
    if len(checkpoints)!=3:
        return {"status":"technical_incomplete","checkpoints":checkpoints,
                "reason":"Not all three real game checkpoints exist"}
    end=checkpoints[-1]
    technologies=end["technologies"]
    unlocked={t for group in technologies.values() for t in group}
    receipts={(r["recipe"],r["commodity"]) for r in end["production_receipts"]
              if r["amount"]>0}
    stations=end["stations"]
    tiers={s["tier"] for s in stations}
    has_t2=any(s["tier"] in ("t2","t3") for s in stations)
    has_t3="t3" in tiers
    alloy_recipe=any(c=="alloys" for _,c in receipts)
    quantum_recipe=any(c=="quantum_cores" for _,c in receipts)
    milestones={
        "C1_research_t2":{
            "passed":bool({"alloytech2","survey2","drilltech2","structuretech2"}&unlocked),
            "details":"Observed technology IDs from real /api/strategy commander"},
        "C2_real_alloy_recipe":{
            "passed":alloy_recipe,
            "details":"Requires native facility shift produced_outputs, not a market forecast"},
        "C3_paid_t2_station":{
            "passed":has_t2,
            "details":"Requires station_core.tier from real /api/report"},
        "C4_native_quantum_recipe":{
            "passed":quantum_recipe,
            "details":"Actual produced_outputs receipt, not newly seeded stock"},
        "C4_paid_t3_station":{
            "passed":has_t3,
            "details":"Requires persisted actual station_core.tier == t3"},
        "C5_planner_comparison":{
            "passed":False,
            "status":"not_run",
            "details":"Separate same-world baseline/HTN/GOAP/Beam comparison is not in this simulation"},
    }
    # Mandatory engine progress through real native T2. T3 is a real
    # additional acceptance criterion; missing it is INCOMPLETE, not PASS.
    progress_ok=all(milestones[k]["passed"] for k in
                    ("C1_research_t2","C2_real_alloy_recipe","C3_paid_t2_station"))
    complete=progress_ok and milestones["C4_native_quantum_recipe"]["passed"] and has_t3
    return {"status":"progression_complete" if complete else
            "progression_incomplete","checkpoint_count":len(checkpoints),
            "milestones":milestones,"final":end,
            "all_technologies_observed":sorted(unlocked),
            "note":"Only actual API stocks and native paid work receipts qualify as proof",
            "C3_complete":progress_ok}

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--bench",type=Path,required=True)
    p.add_argument("--output",type=Path,required=True)
    args=p.parse_args()
    analysis=analyze(args.bench)
    args.output.mkdir(parents=True,exist_ok=True)
    (args.output/"PROGRESSION-CAMPAIGN.json").write_text(
        json.dumps(analysis,ensure_ascii=False,indent=2)+"\n",encoding="utf8")
    lines=["# Galaxy 0.5 — автоматическая приёмка прогрессии","",
           "Статус: **"+analysis["status"]+"**",""]
    for key,v in analysis.get("milestones",{}).items():
        status="пройден" if v.get("passed") else ("не проверялся" if v.get("status")=="not_run" else "не пройден")
        lines.append("- "+key+": **"+status+"**. "+v["details"])
    end=analysis.get("final",{})
    lines+=["","## Последний снимок",""]
    for s in end.get("stations",[]):
        if s.get("tier")!="t1" or s.get("upgrade_target"):
            lines.append(f"- {s['location']}: {s['tier']} / слот {s.get('occupied')}/{s.get('slots')} / блокер {s.get('blocked')}")
    lines+=["","Статус не подменяется красивым графиком или отсутствием аварии.",
            "Кредитные, складские и строительные инварианты отдельно проверяют Rust unit-тесты.",""]
    result="\n".join(lines)
    (args.output/"PROGRESSION-CAMPAIGN-RU.md").write_text(result,encoding="utf8")
    print(result)
    # Missing T2 or T3 is NOT a test success; keep reports for debugging.
    if analysis["status"]!="progression_complete":
        raise SystemExit(2)

if __name__=="__main__":
    main()
