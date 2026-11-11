#!/usr/bin/env python3
"""Evidence-only S1 triage: contract backlog under real Earth gas crisis.

No changes to Genesis, no invented link from generic ship rejection to a
specific contract. Reads cached REAL Windows S0 sample/event files.
"""
from __future__ import annotations
from collections import Counter,defaultdict
import argparse,json
from pathlib import Path
from analyze import read_jsonl

def D(value):return value if isinstance(value,dict) else {}
def L(value):return value if isinstance(value,list) else []

def examine(samples,events):
    if not samples:raise ValueError("No native snapshots")
    first,last=samples[0],samples[-1]
    report=D(last.get("report"))
    location="earth-station";commodity="gas"
    station=next((f for f in L(report.get("facilities"))
        if D(f).get("location")==location and D(f).get("type")=="station"),None)
    if not station or not station.get("faction_id"):
        raise ValueError("No real earth-station in native /api/report")
    faction=station["faction_id"]
    contract_history=defaultdict(list)
    all_matches=[]
    for sample in samples:
        tick=D(sample.get("health")).get("tick")
        for contract in L(sample.get("contracts")):
            c=D(contract)
            if (c.get("destination_location")==location and
                c.get("commodity")==commodity and
                c.get("faction_id")==faction and c.get("id")):
                contract_history[c["id"]].append({
                    "tick":tick,"status":c.get("status"),
                    "source_location":c.get("source_location"),
                    "fulfiller_id":c.get("fulfiller_id"),
                    "contract_type":c.get("contract_type"),
                    "quantity":c.get("quantity"),
                    "reserved_cr":D(c.get("funding")).get("reserved"),
                    "posted_at_tick":c.get("posted_at_tick"),
                    "accepted_at_tick":c.get("accepted_at_tick"),
                    "expires_at_tick":c.get("expires_at_tick")})
    gas_ids=set(contract_history)
    for cid,history in sorted(contract_history.items()):
        phases=list(dict.fromkeys(str(x.get("status")) for x in history))
        all_matches.append({"contract_id":cid,"phases_seen":phases,
              "first_seen_tick":history[0]["tick"],
              "last_seen_tick":history[-1]["tick"],
              "last_observation":history[-1],
              "timeline":history})
    contract_events=[]
    all_rejects=Counter()
    rejections_by_ship=defaultdict(Counter)
    rejection_samples=[]
    direct_gas_rejects=[]
    generic_contract_accepts=0
    for record in events:
        event=D(D(record).get("event"))
        kind=event.get("kind")
        if kind=="ship_transaction_rejected":
            reason=str(event.get("reason","unknown"))
            all_rejects[reason]+=1
            shipid=str(event.get("ship_id","unknown"))
            rejections_by_ship[shipid][reason]+=1
            if len(rejection_samples)<10:
                rejection_samples.append({"tick":record.get("tick"),"event":event})
            if event.get("contract_id") in gas_ids:
                direct_gas_rejects.append({"tick":record.get("tick"),"event":event})
        if kind=="contract_accepted":generic_contract_accepts+=1
        if kind in ("contract_accepted","contract_delivered","contract_expired",
                    "contract_breached","contract_escrow_refunded"):
            cid=event.get("contract_id")
            if cid in gas_ids:
                contract_events.append({"tick":record.get("tick"),"event":event})
    market_path=[]
    head_path=[]
    for sample in samples:
        tick=D(sample.get("health")).get("tick")
        market=next((m for m in L(D(sample.get("report")).get("markets"))
            if D(m).get("facility_location")==location),{})
        source=next((m for m in L(D(sample.get("report")).get("markets"))
            if D(m).get("facility_location")=="alpha-station"),{})
        market_path.append({"tick":tick,
            "destination_gas_stock":D(market.get("supply")).get(commodity),
            "destination_gas_demand":D(market.get("demand")).get(commodity),
            "destination_gas_shortage_ticks":D(market.get("shortage_ticks")).get(commodity),
            "alpha_gas_stock":D(source.get("supply")).get(commodity)})
        faction_view=next((f for f in L(D(sample.get("strategy")).get("factions"))
            if D(f).get("faction_id")==faction),{})
        assessments=[a for a in L(faction_view.get("assessments"))
            if D(D(a).get("goal")).get("commodity")==commodity and
               D(D(a).get("goal")).get("destination")==location]
        head=D(faction_view.get("head"))
        head_path.append({"tick":tick,
            "strategy_status":faction_view.get("status"),
            "strategy_reason":faction_view.get("reason"),
            "gas_assessments":assessments,
            "selected_option":head.get("selected_option"),
            "head_reason":head.get("reason"),
            "head_problem":head.get("problem"),
            "native_chain_probe":head.get("native_chain_probe"),
            "construction_reason":D(faction_view.get("construction")).get("reason")})
    orders_by_tick=[]
    gas_order_ids={"station:delivery:"+cid for cid in gas_ids}
    for sample in samples:
        tick=D(sample.get("health")).get("tick")
        orders=[D(o) for o in L(D(sample.get("strategy")).get("orders"))
            if D(o).get("target_id") in gas_ids or
               D(o).get("order_id") in gas_order_ids]
        orders_by_tick.append({"tick":tick,"gas_orders":orders})
    ships=[{"id":sh.get("id"),"class":sh.get("class"),
            "credits":sh.get("credits"),
            "cargo_capacity":sh.get("cargo_capacity"),
            "active_contract_id":sh.get("active_contract_id"),
            "current_goal":sh.get("current_goal"),
            "fuel":sh.get("fuel"),
            "location":sh.get("location"),
            "destination":sh.get("destination"),
            "cargo":sh.get("cargo")}
            for sh in L(report.get("ships")) if D(sh).get("faction_id")==faction]
    return {
        "format":"sol-s1-gas-contract-triage-v1",
        "evidence_source":"real S0 1813-tick fresh Genesis Galaxy 0.6.2",
        "faction_id":faction,"location":location,"commodity":commodity,
        "contract_count":len(gas_ids),
        "contract_ids":sorted(gas_ids),
        "gas_contract_timelines":all_matches,
        "gas_contract_specific_native_events":contract_events,
        "rejections_directly_identifying_gas_contract":direct_gas_rejects,
        "generic_all_ship_rejections_by_reason":dict(all_rejects),
        "generic_all_ship_rejections_by_ship":{
            ship:dict(c) for ship,c in rejections_by_ship.items()},
        "generic_rejection_samples":rejection_samples,
        "all_factions_contract_accepted_events":generic_contract_accepts,
        "market_gas_path":market_path,
        "strategy_gas_path":head_path,
        "owned_ship_last_snapshot":ships,
        "gas_orders_by_tick":orders_by_tick,
        "proven_claims":[
            "Observed real gas shortage plus native gas goal on Earth",
            "Native posted gas contracts observed with exact contract IDs",
            "Native delivery of those gas IDs must be proven separately"],
        "explicit_uncertainties":[
            "Generic contract_unavailable errors are not gas-specific without a matching contract_id",
            "No contract pickup/transport completion inferred from reserved escrow",
            "No final verdict on transport fault until native order and carrier blockers are traced",
            "Short observation window cannot prove permanent non-delivery"],
    }

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--samples",type=Path,required=True)
    p.add_argument("--events",type=Path,required=True)
    p.add_argument("--out",type=Path,required=True)
    a=p.parse_args()
    result=examine(read_jsonl(a.samples),read_jsonl(a.events))
    a.out.mkdir(parents=True,exist_ok=True)
    (a.out/"GAS-CONTRACT-TRIAGE.json").write_text(
        json.dumps(result,indent=2,ensure_ascii=False)+"\n",encoding="utf8")
    summary=[
        "# Earth Station gas — S1 диагноз на реальных тиках",
        "",
        f"Контрактов на газ для {result['faction_id']}: {result['contract_count']}",
        f"ID: {', '.join(result['contract_ids']) or 'нет'}",
        f"Всего отклонённых ship transactions (НЕ обязательно gas): "+
          str(sum(result["generic_all_ship_rejections_by_reason"].values())),
        f"Отказы с прямым gas contract ID: "+
          str(len(result["rejections_directly_identifying_gas_contract"])),
        "",
        "| Тик | Gas stock | Gas shortage ticks | Доступный газ Alpha Station |",
        "|---:|---:|---:|---:|"
    ]
    for m in result["market_gas_path"]:
        summary.append(f"| {m['tick']} | {m['destination_gas_stock']} | "+
            f"{m['destination_gas_shortage_ticks']} | {m['alpha_gas_stock']} |")
    summary+=["","## Последние native dispatcher orders (только gas ID)"]
    for o in result["gas_orders_by_tick"][-3:]:
        summary.append("tick "+str(o["tick"])+": "+json.dumps(o["gas_orders"],ensure_ascii=False))
    summary+=["","## Корабли владельца Earth Station (последний snapshot)"]
    for sh in result["owned_ship_last_snapshot"]:
        summary.append("- "+json.dumps(sh,ensure_ascii=False))
    summary+=["","## Статусы настоящих контрактов"]
    for c in result["gas_contract_timelines"]:
        summary.append(f"- {c['contract_id']}: "+", ".join(c["phases_seen"])+
            f"; до тика {c['last_seen_tick']}")
    summary+=["",
        "Это инструмент расследования, не фиксация ошибки планировщика.",
        "Ни один общий отказ корабля не приписывается газу без ID.",
        "Для выводов необходима цепь native order → carrier → pickup → delivery.",
        ""]
    (a.out/"GAS-TRIAGE-RU.md").write_text("\n".join(summary),encoding="utf8")
    print("\n".join(summary).encode("ascii","backslashreplace").decode("ascii"))

if __name__=="__main__":main()
