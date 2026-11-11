#!/usr/bin/env python3
"""Read-only postmortem of the S1 real Genesis gas shortage.

Uses saved raw S1 snapshots from direct-source patched Windows Galaxy 0.6.2.
Does NOT infer pickup, successful delivery or profit without receipts.
"""
from __future__ import annotations
import json,sys
from collections import Counter, defaultdict
from pathlib import Path

STATION="earth-station"
SOURCE="alpha-station"
GAS="gas"

def load(path:Path)->list[dict]:
    if not path.is_file():raise FileNotFoundError(path)
    return [json.loads(l) for l in path.read_text(encoding="utf8").splitlines() if l.strip()]

def obj(x):return x if isinstance(x,dict) else {}
def arr(x):return x if isinstance(x,list) else []

def market_at(s:dict,loc:str)->dict:
    return next((m for m in arr(obj(s.get("report")).get("markets"))
                  if obj(m).get("facility_location")==loc),{})

def find_gas_contracts(samples:list[dict]):
    found:dict[str,list[dict]]=defaultdict(list)
    for s in samples:
        tick=obj(s.get("health")).get("tick")
        for c in arr(s.get("contracts")):
            c=obj(c)
            if (c.get("commodity")==GAS and c.get("destination_location")==STATION
                and c.get("id")):
                found[str(c["id"])].append({"tick":tick,**c})
    return found

def analyze(samples,events):
    if not samples:raise ValueError("No actual native S1 snapshots")
    contracts=find_gas_contracts(samples)
    first,last=samples[0],samples[-1]
    ticks=[obj(s.get("health")).get("tick") for s in samples]
    stages={}
    for cid,timeline in contracts.items():
        stages[cid]={
            "first":timeline[0],"last":timeline[-1],
            "statuses":list(dict.fromkeys(x.get("status") for x in timeline)),
            "observations":[{k:x.get(k) for k in ("tick","status","source_location",
                "destination_location","payment","initial_payment","quantity",
                "expires_at_tick","fulfiller_id","faction_id","requestor_id",
                "mission_category","funding")} for x in timeline]
        }
    market_series=[]
    for s in samples:
        tick=obj(s.get("health")).get("tick")
        source=market_at(s,SOURCE)
        earth=market_at(s,STATION)
        market_series.append({
            "tick":tick,
            "alpha_gas_supply":obj(source.get("supply")).get(GAS),
            "alpha_gas_price":obj(source.get("prices")).get(GAS),
            "alpha_market_price_keys":sorted(source.keys()),
            "alpha_price_components":{k:source.get(k) for k in ("pricing","price","prices","market_prices","supply_price","sell_price") if k in source},
            "earth_gas_supply":obj(earth.get("supply")).get(GAS),
            "earth_gas_shortage_ticks":obj(earth.get("shortage_ticks")).get(GAS)
        })
    orders_series=[]
    for s in samples:
        tick=obj(s.get("health")).get("tick")
        strategy=obj(s.get("strategy"))
        gas_order_refs=set(contracts)
        matching=[]
        for key in ("orders","station_orders","contract_orders"):
            for order in arr(strategy.get(key)):
                o=obj(order)
                if (o.get("target_id") in gas_order_refs or
                    any(cid in str(o.get("order_id","")) for cid in gas_order_refs) or
                    obj(o.get("order")).get("target_id") in gas_order_refs):
                    matching.append({"api_container":key,"order":o})
        orders_series.append({"tick":tick,"matching":matching,
            "top_level_strategy_keys":sorted(strategy)})
    rejection=Counter()
    targeted=[]
    contract_events=[]
    for e in events:
        evt=obj(obj(e).get("event",e))
        if evt.get("kind")=="ship_transaction_rejected":
            rejection[str(evt.get("reason","missing_reason"))]+=1
            if str(evt.get("contract_id")) in contracts:
                targeted.append(e)
        if evt.get("contract_id") in contracts:
            contract_events.append(e)
    ships=[]
    for s in (first,last):
        tick=obj(s.get("health")).get("tick")
        fleet=[{k:ship.get(k) for k in ("id","class","size","credits",
                   "cargo_capacity","cargo","fuel","current_goal",
                   "active_contract_id","location","destination","fitting",
                   "faction_id")} for ship in arr(obj(s.get("report")).get("ships"))
               if obj(ship).get("faction_id")=="terran-authority"]
        ships.append({"tick":tick,"fleet":fleet})
    return {"format":"sol-s1-real-gas-offline-audit-v1",
        "build_source":"direct-source 0.6.2 sensor fix",
        "source_workflow_run":43011866774,
        "ticks":ticks,"total_samples":len(samples),"total_events":len(events),
        "station":STATION,"source_market":SOURCE,"commodity":GAS,
        "all_matching_contracts":stages,
        "gas_contract_ids":sorted(stages),
        "market_series":market_series,
        "strategy_gas_orders":orders_series,
        "fleet_first_last":ships,
        "generic_rejection_reasons_not_gas_scoped":dict(rejection),
        "gas_specific_rejections":targeted,
        "gas_specific_events":contract_events,
        "conclusion":"Observed-only: no reason attributed without explicit native contract id",
        "relief_verified":"unknown"}

def main():
    if len(sys.argv)!=3:
        raise SystemExit("Usage: audit_gas_offline.py <raw-artifact-dir> <out-dir>")
    raw,out=Path(sys.argv[1]),Path(sys.argv[2])
    samples=load(raw/"samples.jsonl")
    events=load(raw/"events.jsonl")
    res=analyze(samples,events)
    out.mkdir(exist_ok=True,parents=True)
    (out/"gas-audit.json").write_text(json.dumps(res,ensure_ascii=False,indent=2)+"\n",encoding="utf8")
    md=[
      "# S1 — реальные заказы газа после исправления сенсоров",
      "",
      f"Исходный Windows run: {res['source_workflow_run']}; снимков: {res['total_samples']}; событий: {res['total_events']}",
      "",
      "**Это анализ настоящего сохранённого прогона. Никакая успешная доставка не предполагается.**",
      "",
      "| Контракт | Статусы | Источник | Количество | Исходная оплата | Последняя оплата | Блок заказа |",
      "|---|---|---|---:|---:|---:|---|",
    ]
    last_orders=res["strategy_gas_orders"][-1]["matching"] if res["strategy_gas_orders"] else []
    for cid,rec in res["all_matching_contracts"].items():
        c=rec["last"]
        assigned=[o["order"] for o in last_orders if o["order"].get("target_id")==cid]
        blocked="; ".join(str(o.get("blocked_reason",obj(o.get("order")).get("blocked_reason"))) for o in assigned) or "not visible"
        md.append("| "+" | ".join([
            cid,", ".join(str(x) for x in rec["statuses"]),
            str(c.get("source_location")),str(c.get("quantity")),
            str(c.get("initial_payment")),str(c.get("payment")),blocked
        ])+" |")
    md.extend(["","## Спрос, цены и видимость источника"])
    for m in res["market_series"]:
        md.append(f"- Tick {m['tick']}: Alpha stock={m['alpha_gas_supply']}, "
            f"price={m['alpha_gas_price']}, Earth stock={m['earth_gas_supply']}, "
            f"shortage_ticks={m['earth_gas_shortage_ticks']}")
    md.extend(["","## Native contract order matching (last sample)"])
    for rec in last_orders:md.append("- "+json.dumps(rec,ensure_ascii=True))
    md.extend(["","## Первый/последний снимки кораблей"])
    for record in res["fleet_first_last"]:
        for ship in record["fleet"]:
            md.append(f"- tick {record['tick']}: {ship.get('id')}; "
                f"goal={ship.get('current_goal')}; "
                f"active_contract={ship.get('active_contract_id')}; "
                f"credits={ship.get('credits')}; "
                f"position={ship.get('location')}; "
                f"sensors={obj(obj(ship.get('fitting')).get('stats')).get('sensor_range_au')}")
    md.extend(["","## Причины отказов — ТОЛЬКО общая статистика"])
    for k,v in res["generic_rejection_reasons_not_gas_scoped"].items():
        md.append(f"- {k}: {v}")
    md.extend([f"- Причинно связанные с пятью контрактами отказов: {len(res['gas_specific_rejections'])}",
               f"- Native events с явно указанным gas contract ID: {len(res['gas_specific_events'])}",
               "","**Ограничение:** порог сенсоров T2 — только один фильтр; "
               "без native accept/pickup/deliver и причинной stock attribution Goldens не зелёные.",""])
    (out/"GAS-AUDIT-RU.md").write_text("\n".join(md),encoding="utf8")
    # Show only ASCII so Windows cp1252 does not invalidate saved evidence.
    print(json.dumps({
        "gas_contracts":len(res["gas_contract_ids"]),
        "contract_payment_and_price":[{"cid":cid,
            "quantity":r["last"].get("quantity"),
            "initial_payment":r["last"].get("initial_payment"),
            "payment":r["last"].get("payment")} for cid,r in res["all_matching_contracts"].items()],
        "markets_first_last":[res["market_series"][0],res["market_series"][-1]],
        "gas_orders_last":last_orders[:15],
        "generic_rejections":res["generic_rejection_reasons_not_gas_scoped"],
        "direct_gas_rejections":len(res["gas_specific_rejections"]),
        "contracts_funding":[{"id":cid,"requestor_id":r["last"].get("requestor_id"),
          "funding":r["last"].get("funding"),"min_reputation":r["last"].get("min_reputation"),
          "posted_at_tick":r["last"].get("posted_at_tick"),
          "initial_min_reputation":r["last"].get("initial_min_reputation")}
          for cid,r in res["all_matching_contracts"].items()],
        "station_facility_balances":[{"id":f.get("id"),"type":f.get("type"),
          "faction_id":f.get("faction_id"),"credits":f.get("credits"),"location":f.get("location")}
          for f in arr(obj(samples[-1].get("report")).get("facilities"))
          if f.get("location") in (STATION,SOURCE)],
        "ship_final":[{"id":ship.get("id"),"location":ship.get("location"),
          "goal":ship.get("current_goal"),"credits":ship.get("credits"),
          "active_contract_id":ship.get("active_contract_id")}
          for ship in res["fleet_first_last"][-1]["fleet"]],
    },ensure_ascii=True)[:24000])

if __name__=="__main__": main()
