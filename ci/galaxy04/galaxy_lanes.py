"""B4: real, traversable interstellar corridors in the SAME native
travel_routes graph used by WorldRegistry/PathfinderCtx. The Observer must
read these runtime edges instead of drawing decorative star lines.
Requires B1 worlds08.py first.
"""
from pathlib import Path
import json

base=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2/priv/galaxy/data/worlds"
fnames={
    "sol":"sol.json","alpha":"alpha_centauri.json","epsilon":"epsilon_eridani.json",
    "tau":"tau_ceti.json","vega":"vega.json","lalande":"lalande.json",
    "barnard":"barnard.json","nadir":"nadir.json"
}
W={k:json.loads((base/f).read_text(encoding="utf-8")) for k,f in fnames.items()}
anchors={
    "sol":("earth-station",None),
    "alpha":("alpha-station",None),
    "epsilon":("lane-epsilon", "ee-meridian"),
    "tau":("lane-tau","anvil"),
    "vega":("lane-vega","veritas"),
    "lalande":("lane-lalande","kinship"),
    "barnard":("lane-barnard","yeoman"),
    "nadir":("pirate-outpost",None),
}
for key,(location,body) in anchors.items():
    if body is not None:
        assert any(x["id"]==body for x in W[key]["bodies"])
        if not any(x["name"]==location for x in W[key].get("nav_sites",[])):
            W[key].setdefault("nav_sites",[]).append({
                "name":location,"type":"navigation_lane","body":body
            })
# Each corridor is a legitimate ship transit edge, seeded bidirectionally
# by sim_db::seeder::seed_world. Costs large enough that early factions
# normally develop within their home system before making distant runs.
edges=[
    ("sol","alpha",120), ("sol","epsilon",115),
    ("alpha","tau",155), ("epsilon","tau",150),
    ("tau","vega",135), ("vega","lalande",160),
    ("tau","barnard",200), ("barnard","nadir",390),
]
for a,b,distance in edges:
    origin=anchors[a][0]
    target=anchors[b][0]
    W[a].setdefault("travel_routes",[]).append({
        "from":origin,"to":target,"distance":distance
    })
# Validate 8 unique systems and source/target existence in either world.
all_locations={f["location"] for w in W.values() for f in w["facilities"]}
all_locations|={site["name"] for w in W.values() for site in w.get("nav_sites",[])}
for w in W.values():
    for route in w["travel_routes"]:
        if route["from"] not in all_locations or route["to"] not in all_locations:
            raise RuntimeError("Dangling pathfinder edge: "+repr(route))
for key,data in W.items():
    (base/fnames[key]).write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print("Galaxy B4: seeded",len(edges),"traversable star corridors (both directions)")
