"""Focused structural invariants for Galaxy 0.4 B new seed.
Runs after source overlays and before Rust compilation; no simulation.
"""
from pathlib import Path
import json
root=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2/priv/galaxy/data"
w=[json.loads(p.read_text(encoding="utf-8")) for p in (root/"worlds").glob("*.json")]
assert len(w)==8, f"Expected 8 worlds, got {len(w)}"
names=[x["system"]["name"] for x in w]
assert len(names)==len(set(names)), names
ids=[b["id"] for x in w for b in x["bodies"]]
assert len(ids)==len(set(ids)), "Duplicate body IDs"
locations={f["location"] for x in w for f in x["facilities"]}
locations.update(s["name"] for x in w for s in x.get("nav_sites",[]))
for x in w:
    for f in x["facilities"]:
        assert f["body"] in {b["id"] for b in x["bodies"]}, (x["system"]["name"],f["id"])
    for edge in x["travel_routes"]:
        assert edge["from"] in locations and edge["to"] in locations, edge
    if x["system"]["name"] in ("Sol","Alpha Centauri","Nadir"):
        primary={k for b in x["bodies"] for k,v in b["resources"].items() if v>0}
        assert {"ore","ice","gas"} <= primary,x["system"]["name"]
nadir=next(x for x in w if x["system"]["name"]=="Nadir")
sol=next(x for x in w if x["system"]["name"]=="Sol")
assert len([f for f in nadir["facilities"] if f["faction_id"]=="pirates"])==5
assert len([s for s in nadir["ships"] if s["faction_id"]=="pirates"])==8
assert len([p for p in nadir["populations"] if p["faction_id"]=="pirates"])==1
assert len([m for m in nadir["markets"] if m["facility_id"]=="pirate-outpost"])==1
assert not any(f["faction_id"]=="pirates" for f in sol["facilities"])
assert not any(s["faction_id"]=="pirates" for s in sol["ships"])
assert not any(p["faction_id"]=="pirates" for p in sol["populations"])
factions=json.loads((root/"factions.json").read_text(encoding="utf-8"))
assert next(f for f in factions if f["id"]=="pirates")["home_system"]=="system-nadir"
grades=json.loads((root/"resource_grades.json").read_text(encoding="utf-8"))
assert grades["active"] is False
assert list(grades["coefficients"].values()) == [.75,.9,1.0,1.15,1.3]
for x in w:
    system_grades=grades["systems"][x["system"]["id"]]
    for body in x["bodies"]:
        assert set(system_grades[body["id"]])=={k for k,v in body["resources"].items() if v>0}
        assert all(1<=g<=5 for g in system_grades[body["id"]].values())
# Reported lanes must correspond to REAL seeded travel_routes.
expected_edges=8
lanes=[r for x in w for r in x["travel_routes"] if r["from"].startswith("lane-")
    or r["to"].startswith("lane-")
    or (r["from"]=="earth-station" and r["to"]=="alpha-station")]
assert len(lanes)==expected_edges, (len(lanes),lanes)
print(f"Galaxy B: verified {len(w)} systems, {len(lanes)} native star links, "
      f"3 self-sufficient starts and intact pirate relocation")
