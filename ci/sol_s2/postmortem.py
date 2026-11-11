#!/usr/bin/env python3
"""Read-only native Genesis S2 failure triage from the saved live 1263-tick run.

No guesses. Every attribution is keyed by a real native contract ID or ship ID.
Never treat generic ship_transaction_rejected totals as gas failures.
"""
from __future__ import annotations
import argparse,json
from collections import Counter,defaultdict
from pathlib import Path
from audit_operations import analyze as operation_audit

def read(p):
    return [json.loads(x) for x in p.read_text(encoding="utf-8").splitlines() if x.strip()]
def obj(x):return x if isinstance(x,dict) else {}
def arr(x):return x if isinstance(x,list) else []
def tick(x):return obj(x.get("health")).get("tick")
def event(x):return obj(obj(x).get("event",x))

def analyze(samples,events):
    contracts=defaultdict(list)
    for s in samples:
        for c in arr(s.get("contracts")):
            if obj(c).get("commodity")=="gas" and obj(c).get("destination_location")=="earth-station":
                contracts[c["id"]].append({"tick":tick(s),**c})
    gas_ids=set(contracts)
    board={}
    for cid,history in sorted(contracts.items()):
        orders=[]
        for c in history:
            funding=obj(c.get("funding"))
            orders.append({"tick":c["tick"],"status":c.get("status"),
                "source":c.get("source_location"),"faction":c.get("faction_id"),
                "fulfiller_id":c.get("fulfiller_id"),"quantity":c.get("quantity"),
                "contract_type":c.get("contract_type"),"requestor_id":c.get("requestor_id"),
                "funding_source":funding.get("source"),"reserved":funding.get("reserved"),
                "station_order":funding.get("station_order"),
                "initial_payment":c.get("initial_payment"),"payment":c.get("payment"),
                "min_reputation":c.get("min_reputation"),
                "expires_at_tick":c.get("expires_at_tick")})
        board[cid]={"first":orders[0],"last":orders[-1],
                    "states":list(dict.fromkeys(o["status"] for o in orders)),
                    "order_states":list(dict.fromkeys(
                        (obj(o["station_order"]).get("state"),
                         obj(o["station_order"]).get("blocked_reason"),
                         obj(o["station_order"]).get("executor_id"))
                        for o in orders)),
                    "observations":orders}
    fleet=[]
    for s in samples:
        t=tick(s)
        ships=[]
        for sh in arr(obj(s.get("report")).get("ships")):
            sh=obj(sh)
            if sh.get("faction_id")!="terran-authority":continue
            ships.append({"id":sh.get("id"),"class":sh.get("class"),
                "faction":sh.get("faction_id"),
                "location":sh.get("location"),"position":sh.get("position"),
                "transit":sh.get("transit"),"current_goal":sh.get("current_goal"),
                "active_contract_id":sh.get("active_contract_id"),
                "credits":sh.get("credits"),
                "cargo":sh.get("cargo"),
                "sensor_range_au":obj(obj(sh.get("fitting")).get("stats")).get("sensor_range_au")})
        fleet.append({"tick":t,"genesis_ships":ships})
    earth=[]
    for s in samples:
        markets=arr(obj(s.get("report")).get("markets"))
        m=next((x for x in markets if obj(x).get("facility_location")=="earth-station"),{})
        alpha=next((x for x in markets if obj(x).get("facility_location")=="alpha-station"),{})
        earth.append({"tick":tick(s),
                      "earth_gas":obj(m.get("supply")).get("gas"),
                      "earth_shortage":obj(m.get("shortage_ticks")).get("gas"),
                      "alpha_gas":obj(alpha.get("supply")).get("gas")})
    gas_events=[]
    for row in events:
        e=event(row)
        if (e.get("contract_id") in gas_ids or
            (e.get("commodity")=="gas" and e.get("destination")=="earth-station")):
            gas_events.append({"tick":row.get("tick"),"event":e})
    overall=Counter(str(event(r).get("kind")) for r in events)
    rejections=Counter(str(event(r).get("reason","unknown"))
        for r in events if event(r).get("kind")=="ship_transaction_rejected")
    gas_rejections=Counter(str(e["event"].get("reason","unknown"))
        for e in gas_events if e["event"].get("kind")=="ship_transaction_rejected")
    result={"format":"s2-failed-native-gas-contract-audit",
        "source_type":"saved genuine Windows Genesis /api samples + /ws events",
        "sample_count":len(samples),"event_count":len(events),
        "sample_last_tick":max((tick(s) for s in samples),default=0),
        "gas_contracts":board,
        "gas_ids":sorted(gas_ids),
        "genesis_fleet_timeline":fleet,
        "earth_gas_timeline":earth,
        "gas_specific_events":gas_events,
        "event_kinds":dict(overall),
        "all_transaction_rejections_not_gas_scoped":dict(rejections),
        "gas_id_transaction_rejections":dict(gas_rejections),
        "exact_operation_chains":operation_audit(events),
        "warning":"No generic rejected event may be imputed to a gas contract without an explicit matching native contract_id"}
    return result

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--raw",type=Path,required=True)
    p.add_argument("--out",type=Path,required=True)
    a=p.parse_args()
    samples=read(a.raw/"samples.jsonl")
    events=read(a.raw/"events.jsonl")
    result=analyze(samples,events)
    a.out.mkdir(parents=True,exist_ok=True)
    (a.out/"s2-gas-postmortem.json").write_text(
        json.dumps(result,indent=2,ensure_ascii=False)+"\n",encoding="utf8")
    summary={"samples":result["sample_count"],"events":result["event_count"],
        "last_tick":result["sample_last_tick"],"gas_ids":result["gas_ids"],
        "contracts":[{"id":cid,"first":v["first"],"last":v["last"],
            "order_states":v["order_states"]} for cid,v in result["gas_contracts"].items()],
        "fleet_first":result["genesis_fleet_timeline"][0] if result["genesis_fleet_timeline"] else None,
        "fleet_last":result["genesis_fleet_timeline"][-1] if result["genesis_fleet_timeline"] else None,
        "all_rejections":result["all_transaction_rejections_not_gas_scoped"],
        "gas_specific_rejections":result["gas_id_transaction_rejections"],
        "exact_operation_chains":result["exact_operation_chains"]["complete_market_gas_chains"],
        "chain_receipts":[{"contract_id":c["contract_id"],
            "receipt_tick":c["receipt_tick"],"matched_chain":c["matched_chain"]}
            for c in result["exact_operation_chains"]["gas_market_receipts"]
            if c["verified_full_native_chain"]],
        "market_first":result["earth_gas_timeline"][0] if result["earth_gas_timeline"] else None,
        "market_last":result["earth_gas_timeline"][-1] if result["earth_gas_timeline"] else None,
        "first_positive_earth_gas":next((p for p in result["earth_gas_timeline"]
            if isinstance(p.get("earth_gas"),(int,float)) and p["earth_gas"]>0),None),
        "gas_event_count":len(result["gas_specific_events"])}
    print(json.dumps(summary,ensure_ascii=True)[:58000],flush=True)
    report=["# S2: фактический результат Windows Genesis",
       f"Samples={result['sample_count']}; WS={result['event_count']}; last_tick={result['sample_last_tick']}",
       "", "## Газовые контракты (точные native IDs)"]
    for cid,v in result["gas_contracts"].items():
        report.append("- "+cid+"; "+json.dumps(v["last"],ensure_ascii=True))
        report.append("  order states: "+json.dumps(v["order_states"],ensure_ascii=True))
    report+=["","## Only gas-ID-associated native events"]
    for e in result["gas_specific_events"][-80:]:
        report.append("- "+json.dumps(e,ensure_ascii=True))
    report+=["","## Final Genesis fleet"]
    for s in result["genesis_fleet_timeline"][-1:]:
        for sh in s["genesis_ships"]:
            report.append("- "+json.dumps(sh,ensure_ascii=True))
    report+=["","## Actual market series"]
    for m in result["earth_gas_timeline"]:report.append("- "+json.dumps(m,ensure_ascii=True))
    report+=["", "**Случайные общие отказы других кораблей НЕ связаны причинно с газовыми контрактами.**",""]
    (a.out/"S2-POSTMORTEM-RU.md").write_text("\n".join(report),encoding="utf-8")

if __name__=="__main__":main()
