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
    RECIPES
        .iter()
        .filter(move |r| r.facility_type == facility_type)
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
    execute_with_output_cap(recipe, supply, efficiency, max_batches, prices, None)
}

/// A physically limited production run. The optional output cap constrains
/// scale BEFORE either inputs or outputs are mutated, including a fractional
/// final batch. It is intentionally opt-in until full station warehouse
/// capacity applies consistently to all commodity flows.
pub fn execute_with_output_cap(
    recipe: &Recipe,
    supply: &mut HashMap<Commodity, f32>,
    efficiency: f32,
    max_batches: u32,
    prices: Option<&HashMap<Commodity, f32>>,
    output_cap: Option<(Commodity, f32)>,
) -> HashMap<Commodity, f32> {
    if !efficiency.is_finite()
        || efficiency <= 0.0
        || max_batches == 0
        || recipe.inputs.is_empty()
        || recipe.outputs.is_empty()
    {
        return HashMap::new();
    }
    // Markets store fractional quantities. Rounding an input such as 0.4 fuel
    // to zero while emitting whole output used to make that input free.
    let mut scale = max_batches as f64;
    for &(commodity, needed) in recipe.inputs {
        let available = supply.get(&commodity).copied().unwrap_or(0.0);
        if needed == 0 || !available.is_finite() || available < 0.0 {
            return HashMap::new();
        }
        scale = scale.min(available as f64 / needed as f64);
    }
    if let Some((capped, limit)) = output_cap {
        let current = supply.get(&capped).copied().unwrap_or(0.0);
        if !limit.is_finite() || limit <= 0.0 || !current.is_finite() || current < 0.0 {
            return HashMap::new();
        }
        if current >= limit {
            return HashMap::new();
        }
        for &(commodity, amount) in recipe.outputs {
            if commodity == capped {
                let output_per_batch = amount as f64 * efficiency as f64;
                if output_per_batch <= 0.0 || !output_per_batch.is_finite() {
                    return HashMap::new();
                }
                scale = scale.min(((limit as f64 - current as f64) / output_per_batch).max(0.0));
            }
        }
    }
    if scale <= 0.0 {
        return HashMap::new();
    }
    let effective_scale = scale * efficiency as f64;
    // Validate every output before consuming any input.
    for &(commodity, amount) in recipe.outputs {
        let current = supply.get(&commodity).copied().unwrap_or(0.0);
        let out = (amount as f64 * effective_scale) as f32;
        if !current.is_finite()
            || current < 0.0
            || !out.is_finite()
            || out <= 0.0
            || !(current + out).is_finite()
        {
            return HashMap::new();
        }
    }

    // Bundle (H): profitability gate. When prices are supplied,
    // compare the expected input value to the expected output
    // value at current market rates. Skip recipes that would be a
    // severe loss (ratio below MIN_RECIPE_MARGIN_RATIO). Ignores
    // commodities the price map doesn't know about, so synthetic
    // tests + early-boot ticks without price data still run.
    if let Some(p) = prices {
        // If any input OR output commodity has no price data (missing
        // from the map or 0 — "never observed / price hasn't settled"),
        // skip the gate. Without this guard the output_value collapses
        // to 0 whenever an output commodity is unpriced, falsely
        // classifying a perfectly valid recipe as "severe loss" and
        // stalling farms / refineries on the exact markets that most
        // needed them. Observed live (tick 21k, 16/39 markets at
        // food_supply=0 with water_price=0 tanking grow_food).
        let any_unpriced = recipe
            .inputs
            .iter()
            .chain(recipe.outputs.iter())
            .any(|(c, _)| p.get(c).copied().unwrap_or(0.0) <= 0.0);
        if !any_unpriced {
            let input_value: f64 = recipe
                .inputs
                .iter()
                .map(|(c, n)| p.get(c).copied().unwrap_or(0.0) as f64 * (*n as f64 * scale))
                .sum();
            let output_value: f64 = recipe
                .outputs
                .iter()
                .map(|(c, n)| {
                    p.get(c).copied().unwrap_or(0.0) as f64 * (*n as f64 * effective_scale)
                })
                .sum();
            let ratio = crate::simulation::tuning::WorldTuning::current().min_recipe_margin_ratio;
            if input_value > 0.0 && output_value < input_value * ratio as f64 {
                return HashMap::new();
            }
        }
    }

    // Consume inputs
    for (commodity, needed) in recipe.inputs {
        let consumed = (*needed as f64 * scale) as f32;
        let entry = supply.entry(*commodity).or_insert(0.0);
        *entry -= consumed;
    }

    // Produce outputs
    let mut produced = HashMap::new();
    for (commodity, amount) in recipe.outputs {
        let out = (*amount as f64 * effective_scale) as f32;
        *supply.entry(*commodity).or_insert(0.0) += out;
        produced.insert(*commodity, out);
    }

    produced
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn supply_flow_fractional_batches_consume_every_input_and_keep_fractional_output() {
        let recipe = RECIPES.iter().find(|r| r.id == "smelt_metals").unwrap();
        let mut supply = HashMap::from([(Commodity::Ore, 4.0), (Commodity::Fuel, 0.4)]);
        let produced = execute(recipe, &mut supply, 1.0, 5, None);
        assert!((produced[&Commodity::Metals] - 3.2).abs() < 0.00001);
        assert_eq!(supply[&Commodity::Ore], 0.0);
        assert!(supply[&Commodity::Fuel] < 0.00001);
        assert!(execute(recipe, &mut supply, 1.0, 5, None).is_empty());

        for efficiency in [0.0, -1.0, f32::NAN, f32::INFINITY] {
            let mut supply = HashMap::from([(Commodity::Ore, 10.0), (Commodity::Fuel, 1.0)]);
            let before = supply.clone();
            assert!(execute(recipe, &mut supply, efficiency, 5, None).is_empty());
            assert_eq!(supply, before);
        }
    }

    #[test]
    fn refinery_recipes_exist() {
        let count = for_facility_type("refinery").count();
        assert!(
            count >= 4,
            "refinery should have at least 4 recipes, got {count}"
        );
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
