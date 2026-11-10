"""Galaxy 0.4 B1/B2: add two star systems and move the *entire* pirate
seed to distant Nadir. New saves ONLY. Never touch established databases.
No existing output recipes, richness, or mining multipliers are changed.
"""
from pathlib import Path
import json

base = Path(__file__).resolve().parents[2] / "work/source/Living-Sector-Galaxy-0.2/priv/galaxy/data"
worlds = base / "worlds"
def read(p): return json.loads(p.read_text(encoding="utf-8"))
def save(p,x): p.write_text(json.dumps(x,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
existing = {p.stem:read(p) for p in worlds.glob("*.json")}
if set(existing) != {"sol","alpha_centauri","barnard","lalande","tau_ceti","vega"}:
    raise RuntimeError(f"Expected exact six-system seed, found {set(existing)}")
sol=existing["sol"]
pirate = {
    "facilities":[x for x in sol["facilities"] if x["faction_id"]=="pirates"],
    "markets":[x for x in sol["markets"] if x["facility_id"]=="pirate-outpost"],
    "ships":[x for x in sol["ships"] if x["faction_id"]=="pirates"],
    "populations":[x for x in sol["populations"] if x["faction_id"]=="pirates"],
}
if [len(pirate[k]) for k in ("facilities","markets","ships","populations")] != [5,1,8,1]:
    raise RuntimeError("Existing pirate seed contents changed")
sol["facilities"]=[x for x in sol["facilities"] if x not in pirate["facilities"]]
sol["markets"]=[x for x in sol["markets"] if x not in pirate["markets"]]
sol["ships"]=[x for x in sol["ships"] if x not in pirate["ships"]]
sol["populations"]=[x for x in sol["populations"] if x not in pirate["populations"]]
sol["travel_routes"]=[r for r in sol["travel_routes"]
    if r["from"]!="pirate-outpost" and r["to"]!="mine-callisto"]
sol["nav_sites"]=[x for x in sol["nav_sites"] if x["name"]!="mine-callisto"]
for f in pirate["facilities"]:
    if f["location"]!="pirate-outpost": raise RuntimeError("Unexpected pirate facility")
    f["body"]="nadir-wreckhold"
def body(id,name,kind,radius,period,angle,biome,res):
    return dict(id=id,name=name,type=kind,orbit_radius=radius,
        orbit_period=period,current_angle=angle,biome=biome,resources=res)
def system(id,name,xy,star,bodies,route=(),sites=()):
    return {"system":{"id":id,"name":name,"universe_offset":xy,"star_type":star},
        "bodies":bodies,"travel_routes":[{"from":a,"to":b,"distance":d} for a,b,d in route],
        "facilities":[],"markets":[],"ships":[],"populations":[],
        "nav_sites":[{"name":a,"type":"mining_site","body":b} for a,b in sites]}
nadir=system("system-nadir","Nadir",[255,-190],"M",[
    body("nadir-wreckhold","Wreckhold","moon",2.8,890,65,"lifeless",{"ore":.6,"ice":.6,"gas":.2}),
    body("nadir-ashfall","Ashfall","planet",1.7,670,155,"molten",{"ore":.8,"gas":.2}),
    body("nadir-deep-freeze","Deep Freeze","planet",4.3,1430,285,"ice",{"ice":.95,"gas":.45}),
    body("nadir-goliath","Goliath","planet",7.2,2530,210,"gas_giant",{"gas":.95}),
    body("nadir-black-belt","Black Belt","belt",5.7,1860,40,"asteroid",{"ore":.83,"ice":.3}),
    body("nadir-wreck-field","Wreck Field","asteroid",8.8,3150,130,"asteroid",{"ore":.35,"ice":.23,"gas":.1}),
],[
    ("pirate-outpost","mine-nadir-black-belt",14),
    ("pirate-outpost","mine-nadir-wreck-field",18),
],[
    ("mine-nadir-black-belt","nadir-black-belt"),
    ("mine-nadir-wreck-field","nadir-wreck-field"),
])
for k,objects in pirate.items(): nadir[k]=objects
epsilon=system("system-epsilon-eridani","Epsilon Eridani",[64,-96],"K",[
    body("ee-meridian","Meridian","planet",2.1,720,30,"terrestrial",{"ore":.52,"ice":.32}),
    body("ee-ember","Ember","planet",1.1,400,170,"desert",{"ore":.65,"gas":.12}),
    body("ee-borealis","Borealis","planet",4.4,1550,260,"ice",{"ice":.85,"gas":.3}),
    body("ee-maelstrom","Maelstrom","planet",6.4,2200,70,"gas_giant",{"gas":.88}),
    body("ee-belt","Epsilon Belt","asteroid",3.3,1150,315,"asteroid",{"ore":.77,"ice":.25}),
])
factions=read(base/"factions.json")
p=[f for f in factions if f["id"]=="pirates"]
if len(p)!=1 or p[0]["home_system"]!="system-sol": raise RuntimeError("Unexpected pirate home")
p[0]["home_system"]="system-nadir"

# Validate references and self-sufficiency before writing any data.
all_worlds=[sol,existing["alpha_centauri"],nadir,epsilon,
    existing["barnard"],existing["lalande"],existing["tau_ceti"],existing["vega"]]
ids=[b["id"] for w in all_worlds for b in w["bodies"]]
if len(ids)!=len(set(ids)):raise RuntimeError("Duplicate celestial body ids")
for w in all_worlds:
    local_ids={b["id"] for b in w["bodies"]}
    for f in w["facilities"]:
        if f["body"] not in local_ids:
            raise RuntimeError(f"Orphan facility {f['id']} in {w['system']['name']}")
    if w["system"]["name"] in {"Sol","Alpha Centauri","Nadir"}:
        raw={k for b in w["bodies"] for k,v in b["resources"].items() if v>0}
        if not {"ore","ice","gas"}<=raw:raise RuntimeError("Not self-sufficient: "+w["system"]["name"])
if any(f["faction_id"]=="pirates" for f in sol["facilities"]):
    raise RuntimeError("Pirates still have starting assets in Sol")
save(worlds/"sol.json",sol)
save(worlds/"nadir.json",nadir)
save(worlds/"epsilon_eridani.json",epsilon)
save(base/"factions.json",factions)

# Non-active planning grades: independent of existing 0..1 raw richness.
# Changing richness today changes existing production; never repurpose it.
def grade(r):return 1 if r<.25 else 2 if r<.45 else 3 if r<.65 else 4 if r<.85 else 5
metadata={"active":False,"coefficients":{"1":.75,"2":.90,"3":1.0,"4":1.15,"5":1.30},
    "systems":{w["system"]["id"]:{b["id"]:{k:grade(v) for k,v in b["resources"].items() if v>0}
    for b in w["bodies"]} for w in all_worlds}}
save(base/"resource_grades.json",metadata)
print(f"Galaxy B1: eight systems, pirates moved: {len(pirate['facilities'])} facilities, "
    f"{len(pirate['markets'])} market, {len(pirate['ships'])} ships, "
    f"{len(pirate['populations'])} populations; raw multipliers unchanged")
