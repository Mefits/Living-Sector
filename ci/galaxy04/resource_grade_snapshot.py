"""B3: expose stable resource grades in the actual /api/report body snapshots,
using seed max_resources, without changing production, mining, or depletion.
The preliminary grade configuration is inactive throughout Galaxy 0.4.
"""
from pathlib import Path
root=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2"
core=root/"crates/sim_core/src/agents/celestial_body.rs"
snap=root/"crates/sim_server/src/snapshot.rs"
def update(path,edits):
    data=path.read_text(encoding="utf-8")
    for old,new in edits:
        n=data.count(old)
        if n!=1:raise RuntimeError(f"Grade patch source drift: {path.name} anchor count {n}: {old[:90]!r}")
        data=data.replace(old,new,1)
    path.write_text(data,encoding="utf-8")
update(core,[
("""    pub biome: String,
    /// Bundle D: faction with the most non-gate facilities here""",
"""    pub biome: String,
    /// Seed-defined resource presence and richness. Quality tier itself
    /// does NOT multiply output in Galaxy 0.4; existing mining remains.
    pub resource_grades: HashMap<Commodity,u8>,
    /// Bundle D: faction with the most non-gate facilities here"""),
("""        biome: &BodyBiome,
        territory: Option<&BodyTerritory>,
    ) -> Self {""",
"""        biome: &BodyBiome,
        territory: Option<&BodyTerritory>,
        resources: Option<&BodyResources>,
    ) -> Self {"""),
("""            biome: biome.biome.clone(),
            controlling_faction:""",
"""            biome: biome.biome.clone(),
            resource_grades: resources.map(|r|r.max_resources.iter()
                .filter_map(|(&commodity,&value)| resource_grade(value)
                    .map(|grade|(commodity,grade))).collect()).unwrap_or_default(),
            controlling_faction:"""),
("""impl BodySnapshot {
    pub fn build(""",
"""/// Frozen, descriptive grades I–V. The prospective economic
/// multipliers .75/.90/1.0/1.15/1.3 are NOT active in Galaxy 0.4.
pub fn resource_grade(seed_richness: f32) -> Option<u8> {
    if !seed_richness.is_finite() || seed_richness <= 0.0 {return None;}
    Some(if seed_richness < 0.25 {1}
         else if seed_richness < 0.45 {2}
         else if seed_richness < 0.65 {3}
         else if seed_richness < 0.85 {4}
         else {5})
}

impl BodySnapshot {
    pub fn build("""),
("""    #[test]
    fn biome_food_multiplier_lookup()""",
"""    #[test]
    fn galaxy04_resource_grades_are_descriptive_only() {
        assert_eq!(resource_grade(0.0),None);
        assert_eq!(resource_grade(0.2),Some(1));
        assert_eq!(resource_grade(0.3),Some(2));
        assert_eq!(resource_grade(0.5),Some(3));
        assert_eq!(resource_grade(0.7),Some(4));
        assert_eq!(resource_grade(0.9),Some(5));
    }

    #[test]
    fn biome_food_multiplier_lookup()""")
])
update(snap,[
("""celestial_body::{BodyBiome, BodyIdentity, BodyOrbit, BodySnapshot, BodyTerritory}""",
"""celestial_body::{BodyBiome, BodyIdentity, BodyOrbit, BodyResources, BodySnapshot, BodyTerritory}"""),
("""world.query::<(&BodyIdentity, &BodyOrbit, &BodyBiome, Option<&BodyTerritory>)>();
        for (identity, orbit, biome, territory) in q.iter(&world) {
            let snap = BodySnapshot::build(identity, orbit, biome, territory);""",
"""world.query::<(&BodyIdentity, &BodyOrbit, &BodyBiome, Option<&BodyTerritory>, Option<&BodyResources>)>();
        for (identity, orbit, biome, territory, resources) in q.iter(&world) {
            let snap = BodySnapshot::build(identity, orbit, biome, territory, resources);""")
])
print("Galaxy B3: non-active I-V grades added to body HTTP/WS snapshots")
