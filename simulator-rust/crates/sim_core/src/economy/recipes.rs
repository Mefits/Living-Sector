//! Production recipes: input commodities → output commodities at facility types.

use crate::economy::commodities::Commodity;
use std::collections::HashMap;

#[derive(Debug, Clone)]
pub struct Recipe {
    pub id: &'static str,
    pub facility_type: &'static str,
    pub inputs: &'static [(Commodity, u32)],
    pub outputs: &'static [(Commodity, u32)],
}

pub const RECIPES: &[Recipe] = &[
    // Refinery: raw → refined
    Recipe {
        id: "smelt_metals",
        facility_type: "refinery",
        inputs: &[(Commodity::Ore, 10), (Commodity::Fuel, 1)],
        outputs: &[(Commodity::Metals, 8)],
    },
    Recipe {
        id: "process_ice",
        facility_type: "refinery",
        inputs: &[(Commodity::Ice, 8)],
        outputs: &[(Commodity::Water, 6), (Commodity::Fuel, 5)],
    },
    Recipe {
        id: "crack_fuel",
        facility_type: "refinery",
        inputs: &[(Commodity::Gas, 6)],
        outputs: &[(Commodity::Fuel, 4)],
    },
    Recipe {
        id: "refine_polymers",
        facility_type: "refinery",
        inputs: &[(Commodity::Gas, 6)],
        outputs: &[(Commodity::Polymers, 5)],
    },
    // Factory: refined → manufactured
    Recipe {
        id: "assemble_components",
        facility_type: "factory",
        inputs: &[(Commodity::Metals, 3), (Commodity::Polymers, 1)],
        outputs: &[(Commodity::Components, 5)],
    },
    Recipe {
        id: "build_electronics",
        facility_type: "factory",
        inputs: &[(Commodity::Components, 2), (Commodity::Metals, 1)],
        outputs: &[(Commodity::Electronics, 3)],
    },
    Recipe {
        id: "forge_tools",
        facility_type: "factory",
        inputs: &[(Commodity::Metals, 2), (Commodity::Polymers, 1)],
        outputs: &[(Commodity::Tools, 4)],
    },
    Recipe {
        id: "produce_medical",
        facility_type: "factory",
        inputs: &[(Commodity::Water, 2), (Commodity::Components, 1)],
        outputs: &[(Commodity::Medical, 4)],
    },
    Recipe {
        id: "craft_luxury",
        facility_type: "factory",
        inputs: &[(Commodity::Components, 2), (Commodity::Polymers, 1)],
        outputs: &[(Commodity::Luxury, 1)],
    },
    // Farm
    Recipe {
        id: "grow_food",
        facility_type: "farm",
        inputs: &[(Commodity::Water, 3)],
        outputs: &[(Commodity::Food, 10)],
    },
];

pub fn for_facility_type(facility_type: &str) -> impl Iterator<Item = &'static Recipe> + use<'_> {
    RECIPES.iter().filter(move |r| r.facility_type == facility_type)
}

/// Bundle (H): profitability gate threshold (default). Recipes
/// whose outputs are worth less than this fraction of their inputs
/// are skipped. 0.5 = "skip when we'd lose half or more"; leaves
/// generous headroom for normal price fluctuation so facilities
/// don't idle on transient dips. Live-tunable via
/// `WorldTuning::current().min_recipe_margin_ratio` (see
/// `sim_core/src/simulation/tuning.rs`).
pub const MIN_RECIPE_MARGIN_RATIO: f32 = 0.5;

/// Execute a recipe against available supply. Returns produced outputs
/// and mutates supply in place. Scales down if inputs are insufficient.
/// `max_batches` caps how many cycles run per tick.
///
/// Bundle (H): when `prices` is `Some`, the recipe is skipped if
/// its output value falls below `MIN_RECIPE_MARGIN_RATIO` of its
/// input value at those prices. Makes facilities respond to local
/// economics — refineries idle when ore is cheap elsewhere, farms
/// slow when food over-supplies. Pass `None` to disable the gate
/// (used by unit tests that construct synthetic scenarios).
pub fn execute(
    recipe: &Recipe,
    supply: &mut HashMap<Commodity, f32>,
    efficiency: f32,
    max_batches: u32,
    prices: Option<&HashMap<Commodity, f32>>,
) -> HashMap<Commodity, f32> {
    // Find limiting factor
    let scale = recipe
        .inputs
        .iter()
        .map(|(commodity, needed)| {
            let available = supply.get(commodity).copied().unwrap_or(0.0);
            if *needed > 0 {
                available / (*needed as f32)
            } else {
                999.0
            }
        })
        .fold(f32::MAX, |acc, v| acc.min(v))
        .min(max_batches as f32)
        .max(0.0);

    if scale <= 0.0 {
        return HashMap::new();
    }

    let effective_scale = scale * efficiency;

    // Skip if any output would round to zero — don't waste inputs
    let outputs_viable = recipe
        .outputs
        .iter()
        .all(|(_, amount)| (*amount as f32 * effective_scale).round() > 0.0);
    if !outputs_viable {
        return HashMap::new();
    }

    // Bundle (H): profitability gate. When prices are supplied,
    // compare the expected input value to the expected output
    // value at current market rates. Skip recipes that would be a
    // severe loss (ratio below MIN_RECIPE_MARGIN_RATIO). Ignores
    // commodities the price map doesn't know about, so synthetic
    // tests + early-boot ticks without price data still run.
    if let Some(p) = prices {
        let input_value: f32 = recipe
            .inputs
            .iter()
            .map(|(c, n)| p.get(c).copied().unwrap_or(0.0) * (*n as f32 * scale))
            .sum();
        let output_value: f32 = recipe
            .outputs
            .iter()
            .map(|(c, n)| p.get(c).copied().unwrap_or(0.0) * (*n as f32 * effective_scale))
            .sum();
        let ratio = crate::simulation::tuning::WorldTuning::current().min_recipe_margin_ratio;
        if input_value > 0.0 && output_value < input_value * ratio {
            return HashMap::new();
        }
    }

    // Consume inputs
    for (commodity, needed) in recipe.inputs {
        let consumed = (*needed as f32 * scale).round();
        let entry = supply.entry(*commodity).or_insert(0.0);
        *entry = (*entry - consumed).max(0.0);
    }

    // Produce outputs
    let mut produced = HashMap::new();
    for (commodity, amount) in recipe.outputs {
        let out = (*amount as f32 * effective_scale).round();
        *supply.entry(*commodity).or_insert(0.0) += out;
        produced.insert(*commodity, out);
    }

    produced
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn refinery_recipes_exist() {
        let count = for_facility_type("refinery").count();
        assert!(count >= 4, "refinery should have at least 4 recipes, got {count}");
    }

    #[test]
    fn smelt_metals_converts() {
        let recipe = RECIPES.iter().find(|r| r.id == "smelt_metals").unwrap();
        let mut supply = HashMap::new();
        supply.insert(Commodity::Ore, 100.0);
        supply.insert(Commodity::Fuel, 50.0);

        let produced = execute(recipe, &mut supply, 1.0, 5, None);
        assert_eq!(produced.get(&Commodity::Metals), Some(&40.0)); // 5 batches × 8 metals
        assert_eq!(supply[&Commodity::Ore], 50.0);
        assert_eq!(supply[&Commodity::Fuel], 45.0);
    }

    #[test]
    fn insufficient_input_scales_down() {
        let recipe = RECIPES.iter().find(|r| r.id == "smelt_metals").unwrap();
        let mut supply = HashMap::new();
        supply.insert(Commodity::Ore, 15.0); // enough for 1.5 batches
        supply.insert(Commodity::Fuel, 100.0);

        let produced = execute(recipe, &mut supply, 1.0, 10, None);
        // scale = min(15/10, 100/1) = 1.5 → produces 1.5 * 8 = 12 metals
        assert_eq!(produced.get(&Commodity::Metals), Some(&12.0));
    }

    #[test]
    fn zero_input_produces_nothing() {
        let recipe = RECIPES.iter().find(|r| r.id == "smelt_metals").unwrap();
        let mut supply = HashMap::new();

        let produced = execute(recipe, &mut supply, 1.0, 5, None);
        assert!(produced.is_empty());
    }

    #[test]
    fn profitability_gate_skips_loss_recipes() {
        // smelt_metals needs Ore×10 + Fuel×1, produces Metals×8.
        // Price it so outputs are worth far less than inputs: Ore
        // 100, Fuel 500, Metals 1 (absurd). Gate should skip.
        let recipe = RECIPES.iter().find(|r| r.id == "smelt_metals").unwrap();
        let mut supply = HashMap::new();
        supply.insert(Commodity::Ore, 100.0);
        supply.insert(Commodity::Fuel, 50.0);
        let mut prices = HashMap::new();
        prices.insert(Commodity::Ore, 100.0);
        prices.insert(Commodity::Fuel, 500.0);
        prices.insert(Commodity::Metals, 1.0);

        let produced = execute(recipe, &mut supply, 1.0, 5, Some(&prices));
        assert!(produced.is_empty(), "loss-making recipe should be skipped");
        // Supply unchanged because we bailed before consuming.
        assert_eq!(supply[&Commodity::Ore], 100.0);
        assert_eq!(supply[&Commodity::Fuel], 50.0);
    }

    #[test]
    fn profitability_gate_allows_profitable_recipe() {
        // Normal base prices — smelt_metals is strongly profitable
        // (Ore=10, Fuel=50, Metals=80 → outputs easily worth > inputs).
        let recipe = RECIPES.iter().find(|r| r.id == "smelt_metals").unwrap();
        let mut supply = HashMap::new();
        supply.insert(Commodity::Ore, 100.0);
        supply.insert(Commodity::Fuel, 50.0);
        let mut prices = HashMap::new();
        prices.insert(Commodity::Ore, 10.0);
        prices.insert(Commodity::Fuel, 50.0);
        prices.insert(Commodity::Metals, 80.0);

        let produced = execute(recipe, &mut supply, 1.0, 5, Some(&prices));
        assert!(!produced.is_empty(), "profitable recipe should run");
        assert_eq!(produced.get(&Commodity::Metals), Some(&40.0));
    }
}
