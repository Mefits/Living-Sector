#!/usr/bin/env python3
"""Fast dependency/bootstrapping audit of the REAL native Rust recipe catalog.

This intentionally checks ONLY catalog structure and dependency reachability.
It does NOT simulate gameplay, credits, margins, queues, LOD, ship travel,
individual markets, or evolving inventories. Never use it as a Golden pass.
"""
from __future__ import annotations
import re
from dataclasses import dataclass, replace
from pathlib import Path

CATALOG = Path(__file__).resolve().parents[2] / "native/crates/sim_core/src/economy/recipes.rs"
RAW_MATERIALS = frozenset(("Ore", "Ice", "Gas", "RareOre", "CrystalOre"))

@dataclass(frozen=True)
class Recipe:
    id: str
    facility_type: str
    inputs: tuple[tuple[str,int], ...]
    outputs: tuple[tuple[str,int], ...]

RECIPE_RE = re.compile(
    r'Recipe\s*\{\s*id:\s*"([^"]+)"\s*,\s*'
    r'facility_type:\s*"([^"]+)"\s*,\s*'
    r'inputs:\s*&\[(.*?)\]\s*,\s*'
    r'outputs:\s*&\[(.*?)\]\s*,\s*\}', re.S)
INPUT_RE = re.compile(r'\(\s*Commodity::([A-Za-z0-9_]+)\s*,\s*(\d+)\s*\)')

def parse_native_catalog(path:Path=CATALOG) -> list[Recipe]:
    src=path.read_text(encoding="utf-8")
    result=[]
    for m in RECIPE_RE.finditer(src):
        inputs=tuple((c,int(n)) for c,n in INPUT_RE.findall(m.group(3)))
        outputs=tuple((c,int(n)) for c,n in INPUT_RE.findall(m.group(4)))
        if not inputs or not outputs:
            raise ValueError(f"Recipe {m.group(1)} has missing parsed input/output")
        result.append(Recipe(m.group(1),m.group(2),inputs,outputs))
    if len(result)<10:
        raise ValueError("Expected complete native recipe table, not partial regex matches")
    ids=[x.id for x in result]
    if len(ids)!=len(set(ids)):
        raise ValueError("Duplicate native recipe ids")
    return result

def reachable_goods(recipes:list[Recipe], initial=frozenset(RAW_MATERIALS)) -> set[str]:
    known=set(initial)
    while True:
        more=set()
        for recipe in recipes:
            if all(c in known for c,units in recipe.inputs if units>0):
                more.update(c for c,units in recipe.outputs if units>0)
        updated=known|more
        if updated==known:return known
        known=updated

def proposed_energy_cells_t1(catalog:list[Recipe]) -> list[Recipe]:
    """FUTURE hypothetical graph; not deployed; every number is provisional."""
    # In this bootstrap concept, an existing T1 refinery can pack energy from
    # real Fuel without EnergyCells as a required input. No extra mandatory slot.
    out=[Recipe("charge_energy_cells","refinery",
        (("Fuel",2),), (("EnergyCells",8),))]
    for r in catalog:
        inputs=list(r.inputs)
        # Make most industrial and farm recipes require actual cells,
        # but NEVER make Ice->Fuel (bootstrap) or cell production depend
        # on cells. Mining is not a recipe in this catalog and stays exempt.
        if r.id in (
            "smelt_metals","refine_polymers","grow_food","assemble_components",
            "build_electronics","forge_tools","produce_medical","craft_luxury",
            "smelt_alloys_t2","smelt_alloys_t2_retrofit",
            "fabricate_quantum_cores_t3","fabricate_quantum_cores_t3_retrofit"
        ):
            inputs.append(("EnergyCells",1))
        out.append(replace(r,inputs=tuple(inputs)))
    return out

def dependency_report(path:Path=CATALOG) -> dict:
    catalog=parse_native_catalog(path)
    original=reachable_goods(catalog)
    idea=proposed_energy_cells_t1(catalog)
    future=reachable_goods(idea)
    targets=("EnergyCells","Food","Fuel","Metals","Polymers","Components","Electronics")
    return {"real_recipe_count":len(catalog),
       "native_gas_consuming_refinery_recipes":[r.id for r in catalog
          if r.facility_type=="refinery" and any(c=="Gas" for c,_ in r.inputs)],
       "native_ice_to_fuel_recipe":any(r.id=="process_ice"
          and "Fuel" in {c for c,_ in r.outputs} for r in catalog),
       "actual_reachable_goods":sorted(original),
       "hypothetical_energy_cells_reachable":sorted(future),
       "hypothetical_critical_goods_reachable":{k:k in future for k in targets},
       "warning":"Structural prerequisite DAG only. This is NOT an economic flow, pricing or ship simulation."}

if __name__=="__main__":
    import json
    print(json.dumps(dependency_report(),indent=2,ensure_ascii=False))
