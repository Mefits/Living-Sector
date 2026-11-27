"""Galaxy 0.4 A2: estimate life-support buffer from real household recipes.

This overlay extends the existing colony shortage snapshot; it never
adds goods or marks an undelivered contract as completed. All changes
are guarded by exact source matches.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[2] / "work/source/Living-Sector-Galaxy-0.2"
path = root / "crates/sim_core/src/strategy/colony_development.rs"
source = path.read_text(encoding="utf-8")

def replace_once(old: str, new: str):
    global source
    if source.count(old) != 1:
        raise RuntimeError(f"Expected one colony code anchor, got {source.count(old)}: {old[:70]!r}")
    source = source.replace(old, new, 1)

replace_once(
    "    population::{PopDemographics, PopIdentity, PASSENGER_PAYMENT_PER_HEAD},",
    """    population::{PopDemographics, PopEconomy, PopIdentity, PopSentiment,
        CONSUMPTION_INTERVAL_BASE, EMERGENCY_WATER_RATE,
        EMERGENCY_WATER_THRESHOLD, PASSENGER_PAYMENT_PER_HEAD},""",
)

replace_once(
    "const MIN_LIFE_SUPPORT_STOCK: f32 = 20.0;",
    """const MIN_LIFE_SUPPORT_STOCK: f32 = 20.0;
/// Forecast is deliberately conservative but bounded: 80 native purchase
/// cycles = 400 base ticks, multiplied by world speed just like purchases.
/// Route ETA is not accurately known until a carrier is dispatched, so
/// use a stable buffer now; never pretend a receipt equals future stock.
const LIFE_SUPPORT_BUFFER_CYCLES: f32 = 80.0;
const MAX_FORECAST_RESERVE: f32 = 180.0;""",
)

replace_once(
    """fn reserve(market: &MarketPricing, commodity: Commodity) -> Option<f32> {
    let demand = market.demand.get(&commodity).copied().unwrap_or(0.0);
    (demand.is_finite() && demand >= 0.0)
        .then_some((demand * 2.0).max(MIN_LIFE_SUPPORT_STOCK))
}""",
    """fn reserve(market: &MarketPricing, commodity: Commodity, per_purchase: f32) -> Option<f32> {
    let demand = market.demand.get(&commodity).copied().unwrap_or(0.0);
    if !demand.is_finite() || demand < 0.0 || !per_purchase.is_finite() || per_purchase < 0.0 {
        return None;
    }
    // Demand history alone misses starving households that cannot afford a
    // purchase. Derive an additional floor from the ACTUAL consumption
    // coefficients of all local households, including emergency water.
    let history_floor = (demand * 2.0).max(MIN_LIFE_SUPPORT_STOCK);
    let forecast_floor = (per_purchase * LIFE_SUPPORT_BUFFER_CYCLES)
        .min(MAX_FORECAST_RESERVE);
    let target = history_floor.max(forecast_floor);
    target.is_finite().then_some(target)
}""",
)

replace_once(
    """    let people: Vec<_> = world.query::<(&PopIdentity, &PopDemographics)>()
        .iter(world).map(|(identity, demo)|
            (identity.faction_id.clone(), identity.facility_location.clone(), demo.population_count.max(0))).collect();""",
    """    let people: Vec<_> = world.query::<(&PopIdentity, &PopDemographics, &PopEconomy, &PopSentiment)>()
        .iter(world).map(|(identity, demo, economy, sentiment)| {
            let count = demo.population_count.max(0);
            let share = count as f32 / 1000.0;
            let food = economy.consumption.get(&Commodity::Food).copied().unwrap_or(0.0)
                .max(0.0) * share;
            let emergency_water = if sentiment.food_satisfaction < EMERGENCY_WATER_THRESHOLD {
                EMERGENCY_WATER_RATE * share
            } else { 0.0 };
            let water = economy.consumption.get(&Commodity::Water).copied().unwrap_or(0.0)
                .max(0.0) * share + emergency_water;
            (identity.faction_id.clone(), identity.facility_location.clone(), count, food, water)
        }).collect();""",
)

replace_once(
    """        let population: i64 = people.iter().filter(|(f, loc, _)|
            f == &station.faction_id && loc == location).map(|(_, _, count)| *count).sum();""",
    """        let local_people: Vec<_> = people.iter().filter(|(f, loc, _, _, _)|
            f == &station.faction_id && loc == location).collect();
        let population: i64 = local_people.iter().map(|(_, _, count, _, _)| *count).sum();
        let food_per_purchase: f32 = local_people.iter().map(|(_, _, _, food, _)| *food).sum();
        let water_per_purchase: f32 = local_people.iter().map(|(_, _, _, _, water)| *water).sum();""",
)

replace_once(
    """             reserve(pricing, Commodity::Water), reserve(pricing, Commodity::Food))""",
    """             reserve(pricing, Commodity::Water, water_per_purchase),
             reserve(pricing, Commodity::Food, food_per_purchase))""",
)

# A documented constant is an executable contract; ensure it still tracks
# real consumption cadence instead of becoming a stale guessed metric.
replace_once(
    """const LIFE_SUPPORT_BUFFER_CYCLES: f32 = 80.0;""",
    """const LIFE_SUPPORT_BUFFER_CYCLES: f32 = 80.0;
// Native consumption is paid every CONSUMPTION_INTERVAL_BASE × tick_multiplier.
const _: u64 = CONSUMPTION_INTERVAL_BASE;""",
)

source += r"""

#[cfg(test)]
mod galaxy04_life_support_reserve_tests {
    use super::*;
    use std::collections::HashMap;

    fn market(demand: f32) -> MarketPricing {
        MarketPricing {
            price_elasticity: 0.02,
            spread: 0.1,
            prices: HashMap::new(),
            supply: HashMap::new(),
            demand: [(Commodity::Food, demand)].into(),
        }
    }

    #[test]
    fn unpurchased_hunger_still_requires_physical_stock() {
        let m = market(0.0);
        assert_eq!(reserve(&m, Commodity::Food, 0.75), Some(60.0));
        assert_eq!(reserve(&m, Commodity::Food, 0.0), Some(20.0));
    }

    #[test]
    fn market_demand_is_not_reduced_by_forecast_ceiling() {
        let m = market(150.0);
        assert_eq!(reserve(&m, Commodity::Food, 10.0), Some(300.0));
        assert_eq!(reserve(&m, Commodity::Food, f32::INFINITY), None);
    }
}
"""
path.write_text(source, encoding="utf-8")
print("Applied Galaxy 0.4 A2 population-grounded colony reserves")
