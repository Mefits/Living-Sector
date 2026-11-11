#!/usr/bin/env python3
"""Strict read-only gas stocks and cargo-fill audit of real native Windows S2."""
from __future__ import annotations
import argparse,json,math
from pathlib import Path

def read(path):
    return [json.loads(l) for l in Path(path).read_text(encoding="utf8").splitlines() if l.strip()]
def o(x):return x if isinstance(x,dict) else {}
def arr(x):return x if isinstance(x,list) else []
def num(x):return x if isinstance(x,(int,float)) and not isinstance(x,bool) and math.isfinite(x) else None
def event(r):return o(o(r).get("event",r))
def market(s,loc):
    return next((m for m in arr(o(s.get("report")).get("markets"))
                 if o(m).get("facility_location")==loc),{})

def analyze(samples,events):
    assert samples, "Native API snapshots required"
    samples=sorted(samples,key=lambda s:o(s.get("health")).get("tick",0))
    markets={}
    for loc in ("earth-station","alpha-station"):
        series=[]
        for s in samples:
            m=market(s,loc)
            if not m:continue
            series.append({"tick":o(s.get("health")).get("tick"),
               "gas":num(o(m.get("supply")).get("gas")),
               "shortage":o(m.get("shortage_ticks")).get("gas"),
               "price":num(o(m.get("prices")).get("gas"))})
        markets[loc]=series
    caps={}
    for s in samples:
        for ship in arr(o(s.get("report")).get("ships")):
            sh=o(ship)
            if sh.get("id") and num(sh.get("cargo_capacity")) is not None:
                caps[sh["id"]]={"class":sh.get("class"),
                    "capacity":sh["cargo_capacity"]}
    buys=[]
    deliver=[]
    for row in events:
        e=event(row)
        if e.get("kind")!="ship_transaction_applied" or e.get("commodity")!="gas":
            continue
        op=e.get("operation")
        if op not in ("buy","deliver"):continue
        item={"tick":row.get("tick"),"ship_id":e.get("ship_id"),
           "contract_id":e.get("contract_id"),"operation":op,
           "quantity":num(e.get("quantity")),"location":e.get("location")}
        if op=="buy":
            cap=o(caps.get(e.get("ship_id"))).get("capacity")
            item["actual_capacity"]=cap
            item["percent_cargo_hold_for_gas"]=(
                round(100*item["quantity"]/cap,2) if cap and item["quantity"] is not None else None)
            buys.append(item)
        else:deliver.append(item)
    net={}
    for loc,rows in markets.items():
        valid=[r for r in rows if r["gas"] is not None and num(r.get("tick")) is not None]
        if len(valid)<2:continue
        first,last=valid[0],valid[-1]
        delta=last["gas"]-first["gas"]
        dt=last["tick"]-first["tick"]
        net[loc]={"first":first,"last":last,"net_change":round(delta,2),
           "net_per_tick":round(delta/dt,4) if dt>0 else None,
           "positive_gas_snapshots":sum(r["gas"]>0 for r in valid)}
    return {"source_run":43038799967,"samples":len(samples),"events":len(events),
      "gas_market_timeseries":markets,"market_net":net,"gas_buys":buys,
      "gas_deliveries":deliver,"ship_capacities_observed":caps,
      "note":"Market stock NET change includes production, industry and trading, and is NOT gross consumption",
      "test_only_map":"Alpha displaced only in disposable S2 fixture"}
def main():
    p=argparse.ArgumentParser()
    p.add_argument("--raw",type=Path,required=True)
    p.add_argument("--out",type=Path,required=True)
    args=p.parse_args()
    result=analyze(read(args.raw/"samples.jsonl"),read(args.raw/"events.jsonl"))
    args.out.mkdir(exist_ok=True,parents=True)
    (args.out/"gas-balance-evidence.json").write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf8")
    lines=["# Реальная логистика газа — количественная диагностика",
       "Источник: Windows Genesis S2 run 43038799967, 1250 тиков",
       "Внимание: это ускоренная тестовая геометрия, не стандартная карта.",
       "## Рынки (чистое изменение запасов, не изолированное потребление)"]
    for loc,r in result["market_net"].items():
        lines.append(f"- {loc}: начальный газ {r['first']['gas']}, конечный {r['last']['gas']}; изменение {r['net_change']}, среднее за тик {r['net_per_tick']}")
    lines+=["## Реальные покупки газа и заполнение трюмов"]
    for b in result["gas_buys"]:
        lines.append(f"- {b['ship_id']} / {b['contract_id']}: газ {b['quantity']}, трюм {b['actual_capacity']}, доля {b['percent_cargo_hold_for_gas']}%")
    lines+=["## Ограничение вывода",
      "Чистое изменение склада складывается из добычи, переработки и торговли.",
      "Нельзя считать весь отток газа потреблением без событий по источникам.",""]
    (args.out/"GAS-BALANCE-EVIDENCE-RU.md").write_text("\n".join(lines),encoding="utf8")
    print(json.dumps({"market_net":result["market_net"],
        "gas_buys":result["gas_buys"],"gas_deliveries":result["gas_deliveries"]},
        ensure_ascii=True)[:24000])
if __name__=="__main__":main()
