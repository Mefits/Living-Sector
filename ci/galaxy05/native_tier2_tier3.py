"""Galaxy 0.5 E2–E4: native commodity, technology and production foundations.

Apply after Galaxy 0.4.1 overlays on the extracted Genesis project.
All goods flow through real Commodity, MarketPricing, ShipCargo,
ContractBoard and native paid facility shifts. No shadow resource
creation or invented balance. New resource strata are discovered only
by a faction with the appropriate researched drill/survey techs.

This is a FUNCTIONAL INTEGRATION SLICE, not a claim that core upgrades
and the long-game AI campaign (E5–E8) have been completed.
"""
from pathlib import Path
import json
root=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2"
core=root/"crates/sim_core/src"

def one(path,old,new):
    data=path.read_text(encoding="utf8")
    count=data.count(old)
    if count!=1:
        raise RuntimeError(f"Galaxy05 native source drift in {path}: found {count}: {old[:115]!r}")
    path.write_text(data.replace(old,new,1),encoding="utf8")

# E2: canonical resource enum: the only thing storage, cargo, markets and
# contract settlement use. These prices are conservative first-pass
# reference quotes, NOT artificial income or instant technology grants.
p=core/"economy/commodities.rs"
one(p,"""    Gas,
    // Tier 2""",
      """    Gas,
    // Later station tiers: geological inputs gated by faction research.
    RareOre,
    CrystalOre,
    // Tier 2""")
one(p,"""    Water,
    // Tier 3""",
      """    Water,
    Alloys,
    // Tier 3""")
one(p,"""    Electronics,
    Tools,""",
      """    Electronics,
    QuantumCores,
    Tools,""")
one(p,"""        Commodity::Gas,
        Commodity::Metals,""",
      """        Commodity::Gas,
        Commodity::RareOre,
        Commodity::CrystalOre,
        Commodity::Metals,""")
one(p,"""        Commodity::Water,
        Commodity::Components,""",
      """        Commodity::Water,
        Commodity::Alloys,
        Commodity::Components,""")
one(p,"""        Commodity::Electronics,
        Commodity::Tools,""",
      """        Commodity::Electronics,
        Commodity::QuantumCores,
        Commodity::Tools,""")
one(p,"""            Commodity::Ore | Commodity::Ice | Commodity::Gas => 1,
            Commodity::Metals | Commodity::Fuel | Commodity::Polymers | Commodity::Water => 2,
            Commodity::Components | Commodity::Electronics | Commodity::Tools => 3,""",
      """            Commodity::Ore | Commodity::Ice | Commodity::Gas |
                Commodity::RareOre | Commodity::CrystalOre => 1,
            Commodity::Metals | Commodity::Fuel | Commodity::Polymers |
                Commodity::Water | Commodity::Alloys => 2,
            Commodity::Components | Commodity::Electronics |
                Commodity::QuantumCores | Commodity::Tools => 3,""")
one(p,"""            Commodity::Gas => 20.0,
            Commodity::Metals => 45.0,""",
      """            Commodity::Gas => 20.0,
            Commodity::RareOre => 75.0,
            Commodity::CrystalOre => 140.0,
            Commodity::Metals => 45.0,""")
one(p,"""            Commodity::Water => 12.0,
            Commodity::Components => 80.0,""",
      """            Commodity::Water => 12.0,
            Commodity::Alloys => 145.0,
            Commodity::Components => 80.0,""")
one(p,"""            Commodity::Electronics => 120.0,
            Commodity::Tools => 90.0,""",
      """            Commodity::Electronics => 120.0,
            Commodity::QuantumCores => 320.0,
            Commodity::Tools => 90.0,""")
one(p,"""            Commodity::Gas => "gas",
            Commodity::Metals => "metals",""",
      """            Commodity::Gas => "gas",
            Commodity::RareOre => "rare_ore",
            Commodity::CrystalOre => "crystal_ore",
            Commodity::Metals => "metals",""")
one(p,"""            Commodity::Water => "water",
            Commodity::Components => "components",""",
      """            Commodity::Water => "water",
            Commodity::Alloys => "alloys",
            Commodity::Components => "components",""")
one(p,"""            Commodity::Electronics => "electronics",
            Commodity::Tools => "tools",""",
      """            Commodity::Electronics => "electronics",
            Commodity::QuantumCores => "quantum_cores",
            Commodity::Tools => "tools",""")
one(p,"""            "gas" => Some(Commodity::Gas),
            "metals" => Some(Commodity::Metals),""",
      """            "gas" => Some(Commodity::Gas),
            "rare_ore" => Some(Commodity::RareOre),
            "crystal_ore" => Some(Commodity::CrystalOre),
            "metals" => Some(Commodity::Metals),""")
one(p,"""            "water" => Some(Commodity::Water),
            "components" => Some(Commodity::Components),""",
      """            "water" => Some(Commodity::Water),
            "alloys" => Some(Commodity::Alloys),
            "components" => Some(Commodity::Components),""")
one(p,"""            "electronics" => Some(Commodity::Electronics),
            "tools" => Some(Commodity::Tools),""",
      """            "electronics" => Some(Commodity::Electronics),
            "quantum_cores" => Some(Commodity::QuantumCores),
            "tools" => Some(Commodity::Tools),""")

# E3: paid native recipes (no special recipe interpreter).
p=core/"economy/recipes.rs"
one(p,"""    // Farm
    Recipe {
        id: "grow_food",""",
      """    // T2 — one rare mined input and two real existing resources.
    Recipe {
        id: "smelt_alloys_t2",
        facility_type: "alloyplant2",
        inputs: &[(Commodity::RareOre, 4), (Commodity::Metals, 4),
                  (Commodity::Fuel, 2)],
        outputs: &[(Commodity::Alloys, 5)],
    },
    // T3 — dependent on T2 output and one second surveyed mineral.
    Recipe {
        id: "fabricate_quantum_cores_t3",
        facility_type: "qfab3",
        inputs: &[(Commodity::CrystalOre, 3), (Commodity::Alloys, 2),
                  (Commodity::Electronics, 2)],
        outputs: &[(Commodity::QuantumCores, 2)],
    },
    // Farm
    Recipe {
        id: "grow_food",""")

# E2: all research is still done by a real paid native research shift.
# Existing Director serialization and checkpoint already persist these
# technology IDs and issued work receipts across a restart.
p=core/"strategy/director.rs"
one(p,
  """    Technology{id:"automation",name:"Промышленная автоматизация",prerequisite:Some("industrial_methods"),work:90,field:"industry",effect:"Ещё +1 партия за производственный цикл, с расходом сырья"},
];""",
  """    Technology{id:"automation",name:"Промышленная автоматизация",prerequisite:Some("industrial_methods"),work:90,field:"industry",effect:"Ещё +1 партия за производственный цикл, с расходом сырья"},
    Technology{id:"alloytech2",name:"Металлургия сплавов T2",prerequisite:Some("automation"),work:110,field:"industry",effect:"Разрешение оплачиваемого производства сплавов"},
    Technology{id:"survey2",name:"Геологическая разведка T2",prerequisite:Some("deep_navigation"),work:110,field:"science",effect:"Открытие месторождений редкой руды"},
    Technology{id:"drilltech2",name:"Глубинная добыча T2",prerequisite:Some("alloytech2"),work:120,field:"industry",effect:"Добыча редкой руды после разведки"},
    Technology{id:"structuretech2",name:"Модульное ядро T2",prerequisite:Some("alloytech2"),work:160,field:"industry",effect:"Разрешение проекта улучшения станции T2"},
    Technology{id:"survey3",name:"Геологическая разведка T3",prerequisite:Some("survey2"),work:160,field:"science",effect:"Открытие кристаллической руды"},
    Technology{id:"drill3",name:"Глубинная добыча T3",prerequisite:Some("drilltech2"),work:180,field:"industry",effect:"Добыча кристаллической руды после разведки"},
    Technology{id:"quantumtech3",name:"Квантовое производство T3",prerequisite:Some("structuretech2"),work:220,field:"science",effect:"Разрешение производства квантовых ядер"},
    Technology{id:"structuretech3",name:"Модульное ядро T3",prerequisite:Some("quantumtech3"),work:250,field:"industry",effect:"Разрешение проекта улучшения станции T3"},
];""")
one(p,
  """if t.field=="expansion"{c.profile.expansion}else{c.profile.industry};""",
  """match t.field{"expansion"=>c.profile.expansion,"science"=>c.profile.science,_=>c.profile.industry};""")

# Native construction of new factories is prohibited until the relevant
# technology is bought and learned (never based on requested output alone).
p=core/"strategy/construction.rs"
one(p,
  """Commodity::Ore | Commodity::Ice | Commodity::Gas => Some("mining_rig"), _ => None,""",
  """Commodity::Ore | Commodity::Ice | Commodity::Gas |
                Commodity::RareOre | Commodity::CrystalOre => Some("mining_rig"), _ => None,""")
one(p,
  """                    else if already_built { "producer_already_present" }""",
  """                    else if kind==Some("alloyplant2") &&
                        !super::director::has(world,&account.id,"alloytech2") { "research_required_alloytech2" }
                    else if kind==Some("qfab3") &&
                        !super::director::has(world,&account.id,"quantumtech3") { "research_required_quantumtech3" }
                    else if goal.commodity==Commodity::RareOre &&
                        !(super::director::has(world,&account.id,"drilltech2") &&
                          super::director::has(world,&account.id,"survey2")) { "research_required_rare_ore" }
                    else if goal.commodity==Commodity::CrystalOre &&
                        !(super::director::has(world,&account.id,"drill3") &&
                          super::director::has(world,&account.id,"survey3")) { "research_required_crystal_ore" }
                    else if already_built { "producer_already_present" }""")

# Construction-site naming and native materialization continue using
# the existing native creation protocol.
p=core/"agents/construction.rs"
one(p,
  """        Ore | Ice | Gas => "mining_rig",""",
  """        Ore | Ice | Gas | RareOre | CrystalOre => "mining_rig",""")
one(p,
  """        Metals | Water | Polymers | Fuel => "refinery",""",
  """        Metals | Water | Polymers | Fuel => "refinery",
        Alloys => "alloyplant2",
        QuantumCores => "qfab3",""")

# E4: actual mine output is blocked by faction research. No passive
# deposits or cargo spawn just because rare_ore is in world JSON.
p=core/"agents/facility/mod.rs"
one(p,
  """        body_id: String,
        level: u8,
        abandoned: bool,
    }""",
  """        body_id: String,
        faction_id: String,
        level: u8,
        abandoned: bool,
    }""")
one(p,
  """                body_id: id.body_id.clone(),
                level: life.level,""",
  """                body_id: id.body_id.clone(),
                faction_id: id.faction_id.clone(),
                level: life.level,""")
one(p,
  """            // Bundle 1.5: LOD gate — off-screen facilities skip
            // recipes on ticks they aren't firing.""",
  """            // Paid T2/T3 recipes cannot be operated by an unresearched
            // faction, even if a stale save contains such a facility.
            if (fac.facility_type=="alloyplant2" &&
                !crate::strategy::director::has(world,&fac.faction_id,"alloytech2")) ||
               (fac.facility_type=="qfab3" &&
                !crate::strategy::director::has(world,&fac.faction_id,"quantumtech3")) {
                workforce::blocked(world,fac.entity,"research_required");
                continue;
            }
            // Bundle 1.5: LOD gate — off-screen facilities skip
            // recipes on ticks they aren't firing.""")
one(p,
  """            for (commodity, richness) in body_resources {
                if !richness.is_finite() || richness <= 0.0 { continue; }""",
  """            for (commodity, richness) in body_resources {
                if !richness.is_finite() || richness <= 0.0 { continue; }
                if commodity==Commodity::RareOre &&
                    !(crate::strategy::director::has(world,&fac.faction_id,"survey2") &&
                      crate::strategy::director::has(world,&fac.faction_id,"drilltech2")) {
                    continue;
                }
                if commodity==Commodity::CrystalOre &&
                    !(crate::strategy::director::has(world,&fac.faction_id,"survey3") &&
                      crate::strategy::director::has(world,&fac.faction_id,"drill3")) {
                    continue;
                }""")

# E4: raw deposits are PRESENT in the seeded body JSON (not in a
# merchant starting wallet/market), discovered after survey only.
# Compatible with the source archive + B-layer added Nadir bodies.
places={
    "sol.json":{"mars":{"rare_ore":0.28},"belt":{"rare_ore":0.45}},
    "alpha_centauri.json":{"proxima":{"rare_ore":0.42}},
    "tau_ceti.json":{"tau-ceti-belt":{"rare_ore":0.48,"crystal_ore":0.16}},
    "vega.json":{"vega-rim-belt":{"rare_ore":0.56,"crystal_ore":0.26}},
}
worlds=root/"priv/galaxy/data/worlds"
seeded=[]
for filename,target_ids in places.items():
    path=worlds/filename
    data=json.loads(path.read_text(encoding="utf8"))
    for body in data["bodies"]:
        target=target_ids.get(body.get("id"))
        if target:
            for key,value in target.items():
                if key in body["resources"]:
                    raise RuntimeError(f"Galaxy05 seed already has {key} on {body['id']}")
                body["resources"][key]=value
                seeded.append((filename,body["id"],key))
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n",encoding="utf8")
if len(seeded)<3:
    raise RuntimeError(f"Galaxy05 no rare deposits seeded: {seeded}")
print("Galaxy05 E2-E4: four native commodities, paid research+recipes, tech-gated extraction and seeded geology",seeded)
