#!/usr/bin/env python3
"""Read-only exact native ACCEPT -> BUY -> DELIVER chain across WebSocket events.

No game build/run. Uses the already collected Windows Genesis samples and WS
events. A market contract_delivered event is necessary but is not by itself
enough to claim a full traced shipment purchase path.
"""
from __future__ import annotations
import argparse, json
from collections import Counter
from pathlib import Path

def read(p):
    return [json.loads(l) for l in Path(p).read_text(encoding="utf-8").splitlines() if l.strip()]
def obj(x): return x if isinstance(x,dict) else {}
def event(row):return obj(obj(row).get("event",row))
def n(row):return row.get("tick")

def analyze(rows):
    receipts=[(i,r,event(r)) for i,r in enumerate(rows)
        if event(r).get("kind")=="contract_delivered"
        and event(r).get("contract_type")=="delivery"
        and event(r).get("commodity")=="gas"
        and event(r).get("destination")=="earth-station"]
    evidence=[]
    for _,row,e in receipts:
        cid=e.get("contract_id")
        receipt_tick=n(row)
        ops=[(idx,n(r),evt) for idx,r in enumerate(rows)
            if (evt:=event(r)).get("kind")=="ship_transaction_applied"
               and evt.get("contract_id")==cid]
        accepts=[(t,evt) for _,t,evt in ops if evt.get("operation")=="accept"]
        buys=[(t,evt) for _,t,evt in ops if evt.get("operation")=="buy"
            and evt.get("location")=="alpha-station"
            and evt.get("commodity")=="gas"]
        delivers=[(t,evt) for _,t,evt in ops if evt.get("operation")=="deliver"]
        chain=None
        for accepted_tick,acc in accepts:
            if not isinstance(accepted_tick,(int,float)):continue
            for buy_tick,buy in buys:
                if (not isinstance(buy_tick,(int,float)) or buy_tick<accepted_tick or
                    buy.get("ship_id")!=acc.get("ship_id") or
                    not isinstance(buy.get("quantity"),(int,float)) or
                    buy["quantity"]<=0):continue
                for delivered_tick,delivered in delivers:
                    if (isinstance(delivered_tick,(int,float)) and
                        delivered_tick>=buy_tick and
                        delivered_tick==receipt_tick and
                        delivered.get("ship_id")==acc.get("ship_id")):
                        chain={"ship_id":acc.get("ship_id"),
                            "accepted_tick":accepted_tick,
                            "buy_tick":buy_tick,
                            "delivered_tick":delivered_tick,
                            "buy_units":buy.get("quantity"),
                            "native_buy_payment":buy.get("payment"),
                            "deliver_payment":delivered.get("payment")}
                        break
                if chain:break
            if chain:break
        evidence.append({"contract_id":cid,"receipt_tick":receipt_tick,
            "verified_full_native_chain":chain is not None,
            "matched_chain":chain,
            "all_matching_native_ops":[{"tick":t,"operation":evt.get("operation"),
                "ship_id":evt.get("ship_id"),"quantity":evt.get("quantity"),
                "location":evt.get("location"),"reason":evt.get("reason")}
                for _,t,evt in ops]})
    refused=Counter(str(evt.get("reason","missing_reason"))
        for rec in rows if (evt:=event(rec)).get("kind")=="ship_transaction_rejected")
    return {"format":"native-genesis-gas-accept-buy-deliver-audit",
        "gas_market_receipts":evidence,
        "complete_market_gas_chains":sum(int(e["verified_full_native_chain"]) for e in evidence),
        "generic_rejections_NOT_CAUSALLY_LINKED":dict(refused),
        "interpretation":"Only exact matching contract_id + actual native ship transaction accept/buy/deliver proves whole traced sequence"}

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--raw",type=Path,required=True)
    p.add_argument("--out",type=Path,required=True)
    a=p.parse_args()
    rows=read(a.raw/"events.jsonl")
    result=analyze(rows)
    a.out.mkdir(exist_ok=True,parents=True)
    (a.out/"native-transaction-chain.json").write_text(
        json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(result,ensure_ascii=True)[:24000])
if __name__=="__main__":main()
