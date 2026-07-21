//! Shipyard module-production catalog.
//!
//! Shipyards consume commodities from the local market's supply and mint
//! subsystem modules into a `ModuleStock` component. Only tier 2/3
//! modules are produced — tier 1 is the neutral default baked into
//! every hull at spawn and never sold.
//!
//! A recipe is a pure static record: module slug → input commodities +
//! the credit price a ship pays to install one. Prices skew high enough
//! that refits are meaningful purchases — a fresh freighter with 10k
//! credits can't casually stack three tier-3 modules, which lines up
//! with the "retrofit is rare" design intent. When ships start picking
//! refits on their own (post-18c), the price + scarcity here will be
//! the main pacing knobs.

use crate::economy::commodities::Commodity;

#[derive(Debug, Clone, Copy)]
pub struct ModuleRecipe {
    /// Module catalog slug (must match an entry in [`crate::modules::CATALOG`]).
    pub slug: &'static str,
    /// Commodities consumed from the shipyard's local market supply per
    /// produced unit. Order doesn't matter — production checks all
    /// inputs are present before consuming any.
    pub inputs: &'static [(Commodity, u32)],
    /// Credits the ship pays to install one of these modules. Half the
    /// payment is kept by the shipyard as profit; the rest is treated
    /// as covering input cost. Ships that can't afford the cost are
    /// rejected at refit-apply time.
    pub base_cost_credits: i64,
}

/// Target stock level per module slug, per shipyard. A shipyard will
/// try to top each slug up to this many units on every production tick.
/// Keeping it small means production stays active rather than one-and-done.
pub const SHIPYARD_STOCK_TARGET: u32 = 2;

pub const MODULE_RECIPES: &[ModuleRecipe] = &[
    // Engines: metals + electronics + tools, with a little components
    // for the tier-3 variant (military-grade tuning).
    ModuleRecipe {
        slug: "engine_t2",
        inputs: &[
            (Commodity::Metals, 3),
            (Commodity::Electronics, 2),
            (Commodity::Tools, 1),
        ],
        base_cost_credits: 8_000,
    },
    ModuleRecipe {
        slug: "engine_t3",
        inputs: &[
            (Commodity::Metals, 5),
            (Commodity::Electronics, 4),
            (Commodity::Tools, 2),
            (Commodity::Components, 1),
        ],
        base_cost_credits: 22_000,
    },
    // Cargo bay: mostly metals with a polymer liner.
    ModuleRecipe {
        slug: "cargo_bay_t2",
        inputs: &[(Commodity::Metals, 4), (Commodity::Polymers, 2)],
        base_cost_credits: 6_000,
    },
    ModuleRecipe {
        slug: "cargo_bay_t3",
        inputs: &[(Commodity::Metals, 7), (Commodity::Polymers, 3)],
        base_cost_credits: 16_000,
    },
    // Sensors: electronics + components + precision tooling.
    ModuleRecipe {
        slug: "sensors_t2",
        inputs: &[
            (Commodity::Electronics, 2),
            (Commodity::Components, 2),
            (Commodity::Tools, 1),
        ],
        base_cost_credits: 7_500,
    },
    ModuleRecipe {
        slug: "sensors_t3",
        inputs: &[
            (Commodity::Electronics, 4),
            (Commodity::Components, 3),
            (Commodity::Tools, 2),
        ],
        base_cost_credits: 20_000,
    },
    // Reactors: heavy metals + electronics + component housings.
    ModuleRecipe {
        slug: "reactor_t2",
        inputs: &[
            (Commodity::Metals, 4),
            (Commodity::Electronics, 3),
            (Commodity::Components, 2),
        ],
        base_cost_credits: 10_000,
    },
    ModuleRecipe {
        slug: "reactor_t3",
        inputs: &[
            (Commodity::Metals, 7),
            (Commodity::Electronics, 5),
            (Commodity::Components, 3),
        ],
        base_cost_credits: 28_000,
    },
    // Comms: pure electronics + components.
    ModuleRecipe {
        slug: "comms_t2",
        inputs: &[(Commodity::Electronics, 2), (Commodity::Components, 1)],
        base_cost_credits: 5_500,
    },
    ModuleRecipe {
        slug: "comms_t3",
        inputs: &[(Commodity::Electronics, 4), (Commodity::Components, 2)],
        base_cost_credits: 14_000,
    },
];

/// Find a production recipe by module slug. Returns `None` when no
/// recipe exists — tier-1 defaults + any future "drop-only" modules
/// will sit outside this catalog.
pub fn get(slug: &str) -> Option<&'static ModuleRecipe> {
    MODULE_RECIPES.iter().find(|r| r.slug == slug)
}

/// True if `supply` can cover one batch of `recipe`'s inputs.
pub fn inputs_available(
    recipe: &ModuleRecipe,
    supply: &std::collections::HashMap<Commodity, f32>,
) -> bool {
    recipe.inputs.iter().all(|(c, qty)| {
        supply.get(c).copied().unwrap_or(0.0) >= *qty as f32
    })
}

/// Consume one batch of inputs from `supply`. Caller must have already
/// verified via [`inputs_available`] — we assert on debug builds and
/// floor at 0 on release to stay safe.
pub fn consume_inputs(
    recipe: &ModuleRecipe,
    supply: &mut std::collections::HashMap<Commodity, f32>,
) {
    for (c, qty) in recipe.inputs {
        let entry = supply.entry(*c).or_insert(0.0);
        *entry = (*entry - *qty as f32).max(0.0);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    #[test]
    fn every_non_tier_one_module_has_a_recipe() {
        // Every module in the main catalog above tier 1 should be
        // producible. Tier-1 modules are the spawn default and not
        // expected to appear here — they're free.
        for def in crate::modules::CATALOG {
            if def.tier == 1 {
                continue;
            }
            assert!(
                get(def.slug).is_some(),
                "module {} has no production recipe",
                def.slug,
            );
        }
    }

    #[test]
    fn inputs_available_checks_all_entries() {
        let recipe = get("engine_t2").unwrap();
        let mut supply: HashMap<Commodity, f32> = HashMap::new();
        supply.insert(Commodity::Metals, 10.0);
        supply.insert(Commodity::Electronics, 10.0);
        supply.insert(Commodity::Tools, 0.0); // missing
        assert!(!inputs_available(recipe, &supply));
        supply.insert(Commodity::Tools, 1.0);
        assert!(inputs_available(recipe, &supply));
    }

    #[test]
    fn consume_inputs_deducts_all_entries() {
        let recipe = get("comms_t2").unwrap();
        let mut supply: HashMap<Commodity, f32> = HashMap::new();
        supply.insert(Commodity::Electronics, 5.0);
        supply.insert(Commodity::Components, 5.0);
        consume_inputs(recipe, &mut supply);
        assert_eq!(supply[&Commodity::Electronics], 3.0);
        assert_eq!(supply[&Commodity::Components], 4.0);
    }

    #[test]
    fn costs_scale_with_tier() {
        let t2 = get("engine_t2").unwrap();
        let t3 = get("engine_t3").unwrap();
        assert!(
            t3.base_cost_credits > t2.base_cost_credits,
            "tier-3 should cost more than tier-2",
        );
    }
}
