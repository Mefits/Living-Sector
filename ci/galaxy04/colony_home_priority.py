"""Galaxy B2: select viable specialized colonies; prefer local development
without hardcoded destination coordinates or scripted target IDs.
"""
from pathlib import Path
path=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2/crates/sim_core/src/strategy/colony.rs"
s=path.read_text(encoding="utf-8")
def once(old,new):
    global s
    if s.count(old)!=1:raise RuntimeError(f"B2: source changed ({s.count(old)} matches) {old[:70]!r}")
    s=s.replace(old,new,1)
once("""                if (ore <= 0.0 && gas<=0.0) || ice <= 0.0 {
                    continue;
                }""",
"""                // A colony can specialize: e.g. Refuge produces ice and gas
                // while ore arrives from another body in Alpha Centauri.
                // There is no requirement to have ALL raw resources at one
                // landing site. A barren body with no extraction prospect is
                // skipped for now.
                if ore <= 0.0 && ice <= 0.0 && gas <= 0.0 {
                    continue;
                }""")
once("""                    let gas_need=stock.supply.get(&Commodity::Gas).copied().unwrap_or(0.0)<50.0;
                    let score = (ore.min(ice)+if gas_need {gas*2.0}else{gas*0.2}) / (1.0 + distance as f32);""",
"""                    let gas_need=stock.supply.get(&Commodity::Gas).copied().unwrap_or(0.0)<50.0;
                    // Prefer growing around an existing owned STATION
                    // in the same star system. No hard-coded star/system ID:
                    // works for each faction and later player colonies.
                    // A faraway expedition remains possible when its real
                    // value + logistics justify it.
                    let same_local_system = ports.iter().any(|(_, own, _)| {
                        own.faction_id == f.id
                            && own.facility_type == "station"
                            && bodies.iter().any(|(home,_,_)| {
                                home.body_id == own.body_id
                                    && home.star_system_id == body.star_system_id
                            })
                    });
                    let specialty = ore.max(ice).max(gas);
                    let gas_value = if gas_need {gas * 0.55} else {gas * 0.10};
                    let local_factor = if same_local_system { 4.0 } else { 1.0 };
                    let score = (0.1 + specialty + gas_value) * local_factor
                        / (1.0 + distance as f32);""")
path.write_text(s,encoding="utf-8")
print("Galaxy B2: specialized bodies are eligible; same-system development preferred")
