"""Galaxy 0.4 A3: prevent free-market cargo unloading at insolvent markets.

This is a *planning preflight*. The live engine still owns every credit
transaction and revalidates actual buyer cash and market price.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[2] / "work/source/Living-Sector-Galaxy-0.2"
path = root / "crates/sim_core/src/agents/ship/behavior.rs"
source = path.read_text(encoding="utf-8")

def replace_once(old: str, new: str):
    global source
    n = source.count(old)
    if n != 1:
        raise RuntimeError(f"Expected one ship AI anchor, got {n}: {old[:100]!r}")
    source = source.replace(old, new, 1)

marker = "/// Find the best profitable trade route from memory."
if source.count(marker) != 1:
    raise RuntimeError("Cannot identify ship cargo sale planner position")
source = source.replace(marker, r"""
/// Actual owning MARKET facility and spendable cash. A contested location
/// with multiple markets is None: the planner must not guess which market the
/// transaction engine will select.
type BuyerLedger = StdHashMap<String, Option<(String, i64)>>;

/// Find a market that can *actually* buy at least a small cargo lot. The
/// engine still checks prices, reputation and cash at settlement time.
/// Avoid re-issuing the same doomed sell every time an insolvent station is
/// visited, and allow unloading at a reachable alternative station.
fn cargo_liquidation_target(
    at: &str,
    cargo: &ShipCargo,
    memory: &ShipMemory,
    ledger: &BuyerLedger,
    faction: &str,
    economy: &ShipEconomy,
    registry: &WorldRegistry,
    relations: &crate::agents::faction_relations::FactionRelations,
) -> Option<String> {
    let mut choices = Vec::new();
    for (location, record) in ledger {
        let Some((owner, available_credits)) = record else { continue; };
        if *available_credits <= 0 || !crate::agents::faction_relations::commerce_allowed(
            relations, faction, owner
        ) { continue; }
        let Some(prices) = memory.price_knowledge.get(location) else { continue; };
        // SellAll uses this same first-known-commodity ordering. Never
        // recommend a market that will immediately reject its first lot.
        let first = cargo.cargo.iter()
            .filter(|(_, quantity)| **quantity > 0)
            .filter(|(commodity, _)| prices.contains_key(*commodity))
            .min_by_key(|(commodity, _)| commodity.as_str());
        let Some((commodity, quantity)) = first else { continue; };
        let price = prices[commodity].price
            * crate::agents::faction_relations::market_buy_multiplier(
                relations, faction,
                economy.faction_reputation.get(owner).copied().unwrap_or(0),
                owner,
            );
        if !price.is_finite() || price <= 0.0 { continue; }
        // SellAll submits the whole commodity stack as one atomic sale.
        // Checking only a 10-unit lot would still cause an infinite
        // rejection when the market cannot pay for the full request.
        let required = (f64::from(price) * f64::from(*quantity)).ceil();
        if !required.is_finite() || required < 1.0 || required > *available_credits as f64 {
            continue;
        }
        let distance = if location == at { 0 } else {
            let Some(d) = registry.travel_distance(at, location) else { continue; };
            d
        };
        choices.push((distance, std::cmp::Reverse(*available_credits), location.clone()));
    }
    choices.sort();
    choices.into_iter().next().map(|(_, _, location)| location)
}

""" + marker, 1)

marker = "    // Bundle D: contested-destination snapshot."
if source.count(marker) != 1:
    raise RuntimeError("Cannot find pre-parallel market snapshot position")
source = source.replace(marker, """    // Galaxy 0.4 A3: look up the actual market buyer's cash, rather than
    // inferring liquidity from posted prices or the faction treasury.
    // Ambiguous multi-market locations are rejected conservatively.
    let market_buyer_ledger: BuyerLedger = {
        use crate::agents::facility::{FacilityIdentity, FacilityOperations};
        use crate::agents::market::MarketIdentity;
        let mut buyers: BuyerLedger = StdHashMap::new();
        let mut query = world.query::<&MarketIdentity>();
        for market in query.iter(world) {
            let candidate = world.get::<FacilityIdentity>(market.facility)
                .zip(world.get::<FacilityOperations>(market.facility))
                .map(|(owner, wallet)| (owner.faction_id.clone(), wallet.credits));
            match buyers.entry(market.facility_location.clone()) {
                std::collections::hash_map::Entry::Vacant(entry) => {
                    entry.insert(candidate);
                },
                std::collections::hash_map::Entry::Occupied(mut entry) => {
                    entry.insert(None);
                },
            }
        }
        buyers
    };

""" + marker, 1)

replace_once(
    """                &controller_by_location,
                registry,
                gate_pairs,
                retrofit_plan.as_ref(),""",
    """                &controller_by_location,
                &market_buyer_ledger,
                registry,
                gate_pairs,
                retrofit_plan.as_ref(),""",
)

replace_once(
    """    controller_by_location: &StdHashMap<String, String>,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
    retrofit: Option<&RetrofitPlan>,""",
    """    controller_by_location: &StdHashMap<String, String>,
    market_buyer_ledger: &BuyerLedger,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
    retrofit: Option<&RetrofitPlan>,""",
)

replace_once(
    """    if cargo.used() > 0 {
        let frac = cargo.used() as f32 / cargo.capacity.max(1) as f32;""",
    """    if cargo.used() > 0 {
        if let Some(buyer) = cargo_liquidation_target(&at_loc, cargo, memory,
            market_buyer_ledger, ship_faction, economy, registry, relations) {
        let frac = cargo.used() as f32 / cargo.capacity.max(1) as f32;""",
)

replace_once(
    """            bt: build_sell_cargo_bt(),
        });
    }
    // 4. Retrofit opportunity""",
    """            bt: build_sell_cargo_bt_to(&at_loc, &buyer, registry, gate_pairs),
        });
        }
    }
    // 4. Retrofit opportunity""",
)

replace_once(
    """fn build_sell_cargo_bt() -> BtNode<ShipAction> {
    BtNode::sequence(vec![
        BtNode::action(ShipAction::Dock),
        BtNode::action(ShipAction::DockDwell { seconds: DOCK_ARRIVE_DWELL_SECS }),
        BtNode::action(ShipAction::SellAll),
        BtNode::action(ShipAction::DockDwell { seconds: DOCK_DEPART_DWELL_SECS }),
        BtNode::action(ShipAction::Undock),
    ])
}""",
    """fn build_sell_cargo_bt_to(
    from: &str, buyer: &str, registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> BtNode<ShipAction> {
    let mut steps = Vec::new();
    if from != buyer {
        steps.push(BtNode::action(ShipAction::Undock));
        steps.extend(route_actions(from, buyer, registry, gate_pairs)
            .into_iter().map(BtNode::action));
    }
    steps.extend([
        BtNode::action(ShipAction::Dock),
        BtNode::action(ShipAction::DockDwell { seconds: DOCK_ARRIVE_DWELL_SECS }),
        BtNode::action(ShipAction::SellAll),
        BtNode::action(ShipAction::DockDwell { seconds: DOCK_DEPART_DWELL_SECS }),
        BtNode::action(ShipAction::Undock),
    ]);
    BtNode::sequence(steps)
}""",
)

# Existing call inside the test is positional and must receive a preflight
# snapshot. It tests a funded assigned mission (which does not use this path).
replace_once(
    """&Default::default(),&WorldRegistry::default(),&Default::default(),None,1000.,&Default::default(),""",
    """&Default::default(),&Default::default(),&WorldRegistry::default(),&Default::default(),None,1000.,&Default::default(),""",
)

source += r"""

#[cfg(test)]
mod galaxy04_liquidation_tests {
    use super::*;
    use crate::economy::commodities::PriceMemory;

    #[test]
    fn avoid_infinite_repeated_sale_when_buyer_is_broke() {
        let mut memory = ShipMemory {
            price_knowledge: [("mars".into(),[(
                Commodity::Food,PriceMemory{price:20.0,tick:0}
            )].into())].into(),
            visited: vec![], recent_systems:Default::default(),
            route_performance:Default::default(), contract_rejections:Default::default(),
        };
        let cargo = ShipCargo {
            cargo:[(Commodity::Food,100)].into(),capacity:100,
            cargo_age:Default::default(),cargo_origin:Default::default()
        };
        let economy=ShipEconomy {
            transaction:Default::default(),credits:1000,efficiency:1.,
            active_contract_id:None,faction_reputation:Default::default(),
            dock_dwell_start_tick:None,rest_start_tick:None,dock_attempt_start_tick:None
        };
        let mut balances:BuyerLedger = [("mars".into(),Some(("civ".into(),0)))].into();
        let relations=crate::agents::faction_relations::FactionRelations::new();
        assert_eq!(cargo_liquidation_target("mars",&cargo,&memory,&balances,"civ",
            &economy,&WorldRegistry::default(),&relations),None);
        balances.insert("mars".into(),Some(("civ".into(),3000)));
        assert_eq!(cargo_liquidation_target("mars",&cargo,&memory,&balances,"civ",
            &economy,&WorldRegistry::default(),&relations),Some("mars".into()));
        // Known quotes are required: the SellAll action cannot use unknown
        // prices even if the station happens to have cash.
        memory.price_knowledge.clear();
        assert_eq!(cargo_liquidation_target("mars",&cargo,&memory,&balances,"civ",
            &economy,&WorldRegistry::default(),&relations),None);
    }
}
"""
path.write_text(source, encoding="utf-8")
print("Applied Galaxy 0.4 A3 solvent cargo-sale candidate")
