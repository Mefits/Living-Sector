#!/usr/bin/env python3
"""Deterministic baseline vs one controlled balance-variant native replay.

Both scenarios must use the SAME disposable 4,0 Alpha test geometry,
server x16 and same seed layout. Not a normal-distance resilience claim.
"""
import argparse,json
from pathlib import Path
def load(p):return json.loads(Path(p).read_text(encoding="utf8"))
def metric(obj):
    series=obj["trend"]
    receipts=obj["native_market_delivery_receipts"]
    return {"last_tick":obj["last_tick"],
       "delivery_verified":obj["delivery_verified"],
       "relief_verified":obj["relief_verified"],
       "resilience_verified":obj["resilience_verified"],
       "first_earth_gas":series[0].get("earth_gas"),
       "last_earth_gas":series[-1].get("earth_gas"),
       "last_earth_gas_shortage_ticks":series[-1].get("earth_gas_shortage_ticks"),
       "last_alpha_gas":series[-1].get("alpha_gas"),
       "positive_earth_gas_snapshots":sum((p.get("earth_gas") or 0)>0 for p in series),
       "verified_native_gas_receipt_count":len(receipts),
       "verified_native_gas_receipt_units":sum(r["quantity"] for r in receipts)}
def main():
    p=argparse.ArgumentParser()
    p.add_argument("--baseline",type=Path,required=True)
    p.add_argument("--experiment",type=Path,required=True)
    p.add_argument("--out",type=Path,required=True)
    a=p.parse_args()
    baseline=metric(load(a.baseline))
    experiment=metric(load(a.experiment))
    delta={k:experiment[k]-baseline[k] for k in (
        "last_earth_gas","last_earth_gas_shortage_ticks",
        "last_alpha_gas","positive_earth_gas_snapshots",
        "verified_native_gas_receipt_count","verified_native_gas_receipt_units")}
    result={"comparison":"S2 native controlled identical-geometry balance experiment",
      "baseline_source_run":43038799967,
      "baseline":baseline,"experiment":experiment,"delta":delta,
      "do_not_claim":"Not proven stable across multiple seeds, real interstellar distances, food/water crises, or alternative galaxy topology",
      "experimental_changes":["Remove gas-to-fuel refinery recipe",
        "Keep existing Ice-to-Water+Fuel recipe",
        "Gas-to-Polymers still consumes 6 gas per batch",
        "No bulk cargo or mining changes"],
      "interpretation":"single run descriptive only; no automatic production balance change"}
    a.out.parent.mkdir(parents=True,exist_ok=True)
    a.out.write_text(json.dumps(result,indent=2,ensure_ascii=False)+"\n",encoding="utf8")
    print(json.dumps(result,ensure_ascii=True)[:20000])
if __name__=="__main__":main()
