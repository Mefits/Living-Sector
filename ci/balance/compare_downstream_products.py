#!/usr/bin/env python3
"""Safety audit: compare REAL market stock trajectories across gas balance A/B.

All rates remain NET (supply from all sources minus all sinks). Never claim
lower gasoline demand proves refinery production if fuel/polymers collapse.
"""
from __future__ import annotations
import argparse,json
from pathlib import Path
MATERIALS=("gas","fuel","polymers","water","food","metals","components")
LOCATIONS=("alpha-station","earth-station")

def load(path):
    return [json.loads(l) for l in Path(path).read_text(encoding="utf-8").splitlines() if l.strip()]
def obj(x):return x if isinstance(x,dict) else {}
def arr(x):return x if isinstance(x,list) else []
def series(samples):
    result={}
    for loc in LOCATIONS:
        rows=[]
        for s in samples:
            m=next((m for m in arr(obj(s.get("report")).get("markets"))
                if obj(m).get("facility_location")==loc),{})
            if not m:continue
            rows.append({"tick":obj(s.get("health")).get("tick"),
                "supply":{c:obj(m.get("supply")).get(c) for c in MATERIALS},
                "shortage":{c:obj(m.get("shortage_ticks")).get(c) for c in MATERIALS}})
        result[loc]=rows
    return result
def compare(base,variant):
    a,b=series(base),series(variant)
    rows=[]
    for loc in LOCATIONS:
        left,right=a.get(loc,[]),b.get(loc,[])
        for c in MATERIALS:
            if not left or not right:continue
            bl,vl=left[-1]["supply"].get(c),right[-1]["supply"].get(c)
            if not isinstance(bl,(int,float)) or not isinstance(vl,(int,float)):
                diff=None
            else:diff=round(vl-bl,3)
            rows.append({"market":loc,"commodity":c,
                "baseline_last_supply":bl,"variant_last_supply":vl,
                "variant_minus_baseline":diff,
                "baseline_last_shortage":left[-1]["shortage"].get(c),
                "variant_last_shortage":right[-1]["shortage"].get(c),
                "baseline_positive_stock_samples":sum((r["supply"].get(c) or 0)>0 for r in left),
                "variant_positive_stock_samples":sum((r["supply"].get(c) or 0)>0 for r in right)})
    return {"run_baseline":43038799967,"source":"real native Windows S2 x16",
      "comparison":"identical test-only physical geometry and world data",
      "baseline_samples":len(base),"variant_samples":len(variant),
      "rows":rows,"limitations":"Inventory NET is not industrial output; single seed not resilience proof"}
def main():
    p=argparse.ArgumentParser()
    p.add_argument("--baseline",type=Path,required=True)
    p.add_argument("--variant",type=Path,required=True)
    p.add_argument("--out",type=Path,required=True)
    a=p.parse_args()
    v=compare(load(a.baseline/"samples.jsonl"),load(a.variant/"samples.jsonl"))
    a.out.mkdir(exist_ok=True,parents=True)
    (a.out/"downstream-stocks.json").write_text(json.dumps(v,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    md=["# S2 A/B — проверить цену экономии газа для других ресурсов",
        "Два реальных Windows x16 прогона, одна и та же тестовая геометрия.",
        "Остаток на складе не равен выпуску предприятия. Сравнение описательное.",
        "| Рынок | Ресурс | Конец до | Конец после | Разница | Тики дефицита до | Тики дефицита после |",
        "|---|---|---:|---:|---:|---:|---:|"]
    for x in v["rows"]:
        md.append("| "+" | ".join(str(x[y]) for y in (
            "market","commodity","baseline_last_supply","variant_last_supply",
            "variant_minus_baseline","baseline_last_shortage","variant_last_shortage"))+" |")
    md+=["","Важно: проверяются также fuel, polymers, water, food, metals и components.",
          "Если газа стало больше, но переработка или жизнеобеспечение просели,",
          "вариант нельзя принимать без следующего анализа причин и повторов.",""]
    (a.out/"DOWNSTREAM-AUDIT-RU.md").write_text("\n".join(md),encoding="utf-8")
    print(json.dumps({"baseline_samples":len(load(a.baseline/"samples.jsonl")),
        "variant_samples":len(load(a.variant/"samples.jsonl")),
        "rows":v["rows"]},ensure_ascii=True)[:32000])
if __name__=="__main__":main()
