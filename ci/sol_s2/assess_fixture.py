#!/usr/bin/env python3
"""Strict observable native end-to-end receipt and shortage recovery evidence.

This NEVER treats Posted, Accepted, shipment movement or a paid escrow as
physical market relief. Actual event contract_delivered is emitted by
sim_server *after* its native market supply mutation. Quantity is from the
identical native contract. A later observed inventory+shortage trend is
a stronger but separate condition (not a claim of permanent resilience).
"""
from __future__ import annotations
import argparse,json
from pathlib import Path

def read(path:Path):
    return [json.loads(line) for line in path.read_text(encoding="utf8").splitlines() if line.strip()]

def obj(v):return v if isinstance(v,dict) else {}
def arr(v):return v if isinstance(v,list) else []
def tick(s):return int(obj(s.get("health")).get("tick",0))
def event(e):return obj(obj(e).get("event",e))

def market(s,location):
    return next((m for m in arr(obj(s.get("report")).get("markets"))
        if obj(m).get("facility_location")==location),{})

def native_contracts(samples):
    result={}
    for sample in samples:
        t=tick(sample)
        for c in arr(sample.get("contracts")):
            if not isinstance(c,dict):continue
            cid=c.get("id")
            if (isinstance(cid,str) and c.get("commodity")=="gas"
              and c.get("destination_location")=="earth-station"
              and c.get("source_location")=="alpha-station"
              and c.get("contract_type")=="delivery"
              and obj(c.get("funding")).get("source")=="facility"):
                result.setdefault(cid,[]).append({"tick":t,**c})
    return result

def analyze(samples,events):
    if not samples:raise AssertionError("No real API samples")
    samples=sorted(samples,key=tick)
    contracts=native_contracts(samples)
    stages={}
    for cid,timeline in contracts.items():
        stages[cid]={
            "statuses":list(dict.fromkeys(c.get("status") for c in timeline)),
            "fulfiller_ids":sorted({str(c.get("fulfiller_id")) for c in timeline if c.get("fulfiller_id")}),
            "first_post_tick":timeline[0]["tick"],
            "last_observation_tick":timeline[-1]["tick"],
            "last_status":timeline[-1].get("status"),
            "last_order":obj(obj(timeline[-1].get("funding")).get("station_order")),
            "quantity":timeline[0].get("quantity")
        }
    actual=[]
    for rec in events:
        e=event(rec)
        cid=e.get("contract_id")
        if (e.get("kind")!="contract_delivered" or cid not in contracts
                or e.get("commodity")!="gas" or
                e.get("destination")!="earth-station" or
                e.get("contract_type")!="delivery"):
            continue
        original=contracts[cid][0]
        quantity=original.get("quantity")
        t=rec.get("tick")
        if (not isinstance(quantity,int) or quantity<=0 or
                not isinstance(t,(int,float))):
            continue
        # It is possible the probe samples after physical purchase when
        # reserved credits went to the ship. Require a real positive
        # funding escrow at *some* earlier native snapshot.
        if not any(obj(c.get("funding")).get("reserved",0)>0 for c in contracts[cid]):
            continue
        native_qty=e.get("quantity")
        if native_qty is not None and native_qty!=quantity:continue
        actual.append({"tick":int(t),"contract_id":cid,"quantity":quantity,
                       "source":original["source_location"],
                       "destination":"earth-station",
                       "native_event":e})

    trend=[]
    for sample in samples:
        earth=market(sample,"earth-station")
        alpha=market(sample,"alpha-station")
        trend.append({"tick":tick(sample),
            "earth_gas":obj(earth.get("supply")).get("gas"),
            "earth_gas_shortage_ticks":obj(earth.get("shortage_ticks")).get("gas"),
            "alpha_gas":obj(alpha.get("supply")).get("gas")})
    shortage_baseline=trend[0]["earth_gas_shortage_ticks"]
    receipt_tick=min((r["tick"] for r in actual),default=None)
    before=next((p for p in reversed(trend) if
        receipt_tick is not None and p["tick"]<receipt_tick),None)
    after=[p for p in trend if receipt_tick is not None and p["tick"]>=receipt_tick]
    observed_stock=sum(1 for p in after if isinstance(p["earth_gas"],(int,float)) and p["earth_gas"]>0)
    observed_shortage_reset=(bool(before) and isinstance(before.get("earth_gas_shortage_ticks"),(int,float)) and
         any(isinstance(p.get("earth_gas_shortage_ticks"),(int,float))
             and p["earth_gas_shortage_ticks"]<before["earth_gas_shortage_ticks"] for p in after))
    recovery=bool(actual and observed_stock and observed_shortage_reset)
    # A fulfilled delivery is independently shown by engine event even if
    # coarse telemetry does not catch momentary stock before consumption.
    return {
        "format":"native-genesis-s2-controlled-market-delivery-v1",
        "fixture":"test-only fast Earth-Alpha lane; not the default galaxy map",
        "samples":len(samples),"events":len(events),
        "from_tick":trend[0]["tick"],"last_tick":trend[-1]["tick"],
        "gas_contracts":stages,
        "native_market_delivery_receipts":actual,
        "delivery_verified":bool(actual),
        "shortage_baseline":shortage_baseline,
        "trend":trend,
        "inventory_post_receipt_observations":observed_stock,
        "shortage_reset_after_receipt_observed":observed_shortage_reset,
        "relief_verified":recovery if actual else "unknown",
        "resilience_verified":"not_tested",
        "conclusion":("delivery_and_observed_relief" if recovery else
             "delivered_relief_not_yet_observed" if actual else
             "no_native_gas_delivery_observed")
    }

def report(r):
    m=["# S2: native Genesis — gas contract evidence",
       "","**Контролируемая test-only карта:** маршрут Alpha ↔ Earth укорочен только",
       "в копии игрового seed. Двигатель, контракты, цены в ходе торговли,",
       "склады, списания и движения грузов — настоящий Windows Genesis.",
       "",
       f"Снимков: {r['samples']}; событий: {r['events']}; последний тик: {r['last_tick']}",
       f"Доставка подтверждена: {r['delivery_verified']}",
       f"Наблюдаемое восстановление дефицита: {r['relief_verified']}",
       f"Устойчивость к повторным кризисам: {r['resilience_verified']}",
       "",
       "## Контракты газа"]
    for cid,data in sorted(r["gas_contracts"].items()):
        m.append("- "+cid+": "+",".join(str(x) for x in data["statuses"])+
                 ", исполнители="+",".join(data["fulfiller_ids"])+
                 ", last_order="+json.dumps(data["last_order"],ensure_ascii=True))
    m+=["","## Только настоящие подтверждённые события доставки"]
    for receipt in r["native_market_delivery_receipts"]:
        m.append("- "+json.dumps(receipt,ensure_ascii=True))
    m+=["","## Фактический рынок Earth"]
    for row in r["trend"]:
        m.append("- "+json.dumps(row,ensure_ascii=True))
    m+=["","**Не следует утверждать:** устойчивость экономики,",
        "ресурсный relief в стандартной галактике или успех S0/S1 при",
        "отсутствии именно нативных контрактных событий."]
    return "\n".join(m)+"\n"

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--source",type=Path,required=True)
    p.add_argument("--out",type=Path,required=True)
    p.add_argument("--require-delivery",action="store_true")
    args=p.parse_args()
    samples=read(args.source/"samples.jsonl")
    events=read(args.source/"events.jsonl")
    result=analyze(samples,events)
    args.out.mkdir(parents=True,exist_ok=True)
    (args.out/"result.json").write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf8")
    (args.out/"REPORT-RU.md").write_text(report(result),encoding="utf8")
    print(json.dumps({key:result[key] for key in (
        "samples","events","last_tick","delivery_verified",
        "relief_verified","resilience_verified","conclusion")},ensure_ascii=True),flush=True)
    if args.require_delivery and not result["delivery_verified"]:
        raise SystemExit("No confirmed native gas market receipt in bounded controlled fixture")

if __name__=="__main__":main()
