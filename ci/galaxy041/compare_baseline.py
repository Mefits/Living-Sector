#!/usr/bin/env python3
"""Describe the difference between old user Galaxy 0.4-D diagnostics
and a fresh autonomous 0.4.1 run. Not an A/B causality claim.

Run:
 python ci/galaxy041/compare_baseline.py \
  --summary autonomous-bench-results/summary.json \
  --output autonomous-bench-results
"""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path

TRACKED=(
    ("colonies","Колонии",None),
    ("starving_colonies","Голодающие колонии","down"),
    ("colonies_without_food_stock","Колонии без еды","down"),
    ("zero_credit_colonies","Колонии без CR","down"),
    ("paid_food_contracts","Завершено доставок еды","up"),
    ("paid_metals_contracts","Завершено доставок металлов","up"),
    ("ship_credits","CR кораблей",None),
    ("facility_credits","CR предприятий",None),
    ("faction_treasuries","CR казн",None),
    ("household_credits","CR домохозяйств",None),
)

def safe_rate(n,d):
    if not isinstance(n,(int,float)) or not isinstance(d,(int,float)) or d<=0:
        return None
    return round(n/d,3)

def make_comparison(baseline:dict,summary:dict)->dict:
    previous=baseline["snapshots"]
    fresh=summary.get("checkpoints",[])
    results=[]
    for i, current in enumerate(fresh):
        if i>=len(previous): break
        past=previous[i]
        actual=current.get("metrics",{})
        before_colonies=past.get("colonies",0)
        after_colonies=actual.get("colonies",0)
        measurements=[]
        for key,label,desired in TRACKED:
            before=past.get(key)
            after=actual.get(key)
            diff=after-before if isinstance(before,(int,float)) and isinstance(after,(int,float)) else None
            measurements.append({"metric":key,"label":label,
                "old":before,"new":after,"delta":diff,"desired_direction":desired})
        results.append({
            "old_tick":past["tick"],
            "new_tick":current.get("actual_tick",actual.get("tick")),
            "source_seed":summary.get("world_seed"),
            "old_colonies":before_colonies,
            "new_colonies":after_colonies,
            "old_starving_share":safe_rate(past.get("starving_colonies"),before_colonies),
            "new_starving_share":safe_rate(actual.get("starving_colonies"),after_colonies),
            "old_empty_food_share":safe_rate(past.get("colonies_without_food_stock"),before_colonies),
            "new_empty_food_share":safe_rate(actual.get("colonies_without_food_stock"),after_colonies),
            "measurements":measurements,
        })
    return {
        "format":"living-sector-galaxy041-descriptive-baseline-comparison-v1",
        "status":summary.get("status","unknown"),
        "new_build_sha":summary.get("build_sha"),
        "warning":baseline["caution"],
        "old_sources":baseline["source_files"],
        "pairs":results,
    }

def render_markdown(data:dict)->str:
    lines=[
        "# Galaxy 0.4.1 — сравнение с предыдущим игровым прогоном",
        "",
        "**Это описательное сравнение двух игровых миров, а не доказательство улучшения.**",
        "Мир, случайный seed, маршруты и число заселённых колоний могут отличаться.",
        "Частоту голода сопоставляем и по числу колоний, и по доле; меньшее число",
        "колоний само по себе не является победой.",
        "",
        "| Старый тик | Новый тик | Колонии (было → стало) | Доля голода (было → стало) | Доля без еды (было → стало) |",
        "|---:|---:|---|---|---|",
    ]
    percentage=lambda x:"—" if x is None else f"{100*x:.1f}%"
    for pair in data["pairs"]:
        lines.append(
            f"| {pair['old_tick']} | {pair['new_tick']} | "
            f"{pair['old_colonies']} → {pair['new_colonies']} | "
            f"{percentage(pair['old_starving_share'])} → {percentage(pair['new_starving_share'])} | "
            f"{percentage(pair['old_empty_food_share'])} → {percentage(pair['new_empty_food_share'])} |"
        )
    if data["pairs"]:
        pair=data["pairs"][-1]
        lines+=["","## Последняя доступная контрольная точка","",
                "| Показатель | Galaxy 0.4-D | Galaxy 0.4.1 | Разница |",
                "|---|---:|---:|---:|"]
        for m in pair["measurements"]:
            fmt=lambda n:"—" if n is None else f"{n:,}".replace(","," ")
            lines.append(
                f"| {m['label']} | {fmt(m['old'])} | {fmt(m['new'])} | "
                f"{('+' if m['delta']>0 else '')+fmt(m['delta']) if m['delta'] is not None else '—'} |"
            )
    lines+=["","**Интерпретация:** отдельно смотреть реальные завершённые доставки,",
            "остатки рынков, движения денег и число колоний. Даже если голод",
            "уменьшился, но строительство и экспансия полностью остановились —",
            "это не считается успешной стабилизацией.",""]
    return "\n".join(lines)

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--summary",type=Path,required=True)
    p.add_argument("--output",type=Path,required=True)
    args=p.parse_args()
    here=Path(__file__).resolve().parent
    previous=json.loads((here/"legacy_baseline.json").read_text(encoding="utf8"))
    current=json.loads(args.summary.read_text(encoding="utf8"))
    result=make_comparison(previous,current)
    args.output.mkdir(parents=True,exist_ok=True)
    (args.output/"baseline_comparison.json").write_text(
        json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf8")
    markdown=render_markdown(result)
    (args.output/"BASELINE-COMPARISON-RU.md").write_text(markdown,encoding="utf8")
    print(f"Compared {len(result['pairs'])} stage(s) against old diagnostics.")
    if path:=os.getenv("GITHUB_STEP_SUMMARY"):
        with open(path,"a",encoding="utf8") as stream:
            stream.write("\n"+markdown+"\n")

if __name__=="__main__":
    main()
