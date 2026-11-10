"""Galaxy 0.4 A6: avoid choosing a speculative trade run whose destination
cannot pay for the advertised cargo lot. The live transaction remains native.
Applied AFTER ship_liquidity.py, which introduces BuyerLedger snapshot.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[2] / "work/source/Living-Sector-Galaxy-0.2"
path = root / "crates/sim_core/src/agents/ship/behavior.rs"
s = path.read_text(encoding="utf-8")

def one(before, after):
    global s
    n = s.count(before)
    if n != 1:
        raise RuntimeError(f"A6 unexpected source anchor: {n} matches of {before[:90]!r}")
    s = s.replace(before, after, 1)

one(
    """    ship_faction: &str,
    controller_by_location: &StdHashMap<String, String>,
    relations: &crate::agents::faction_relations::FactionRelations,
) -> Option<TradeRunCandidate> {""",
    """    ship_faction: &str,
    controller_by_location: &StdHashMap<String, String>,
    buyer_ledger: &BuyerLedger,
    relations: &crate::agents::faction_relations::FactionRelations,
) -> Option<TradeRunCandidate> {""",
)
one(
    """        best_trade_route_with_ownership(memory, current_tick, ship_faction, controller_by_location, relations)?;""",
    """        best_trade_route_with_ownership(memory, current_tick, ship_faction,
            controller_by_location, relations, Some(buyer_ledger))?;""",
)
one(
    """        &crate::agents::faction_relations::FactionRelations::new(),
    )
}""",
    """        &crate::agents::faction_relations::FactionRelations::new(),
        None,
    )
}""",
)
one(
    """    controllers: &StdHashMap<String, String>,
    relations: &crate::agents::faction_relations::FactionRelations,
) -> Option<(Commodity, String, String, f32)> {""",
    """    controllers: &StdHashMap<String, String>,
    relations: &crate::agents::faction_relations::FactionRelations,
    buyer_ledger: Option<&BuyerLedger>,
) -> Option<(Commodity, String, String, f32)> {""",
)
one(
    """                    // Bundle 1.2: freshness decay — discount routes""",
    """                    // The speculative trade-run BT buys up to
                    // TRADE_QTY_DEFAULT units then uses one atomic Sell.
                    // Never choose an insolvent destination just because
                    // its posted price is high. Check a full lot, not a
                    // token partial sale, and select a different route if
                    // this one cannot settle. No simulated transaction.
                    if let Some(ledger) = buyer_ledger {
                        let Some((_, buyer_cash)) = ledger.get(&sell)
                            .and_then(Option::as_ref) else { continue; };
                        let required = (f64::from(hi) *
                            f64::from(TRADE_QTY_DEFAULT)).ceil();
                        if !required.is_finite() || required <= 0.0
                            || required > *buyer_cash as f64 { continue; }
                    }
                    // Bundle 1.2: freshness decay — discount routes""",
)
one(
    """        ship_faction, controller_by_location, relations,
    ) {
        // Bundle D: trade run counts as contested""",
    """        ship_faction, controller_by_location, market_buyer_ledger, relations,
    ) {
        // Bundle D: trade run counts as contested""",
)
s += r"""

#[cfg(test)]
mod galaxy04_trade_market_liquidity_tests {
    use super::*;
    use crate::economy::commodities::PriceMemory;

    fn prices() -> ShipMemory {
        ShipMemory {
            price_knowledge: [
                ("home".into(),[(Commodity::Ore,PriceMemory{price:2.0,tick:10})].into()),
                ("far".into(),[(Commodity::Ore,PriceMemory{price:20.0,tick:10})].into()),
            ].into(),
            visited:vec![],recent_systems:Default::default(),
            route_performance:Default::default(),contract_rejections:Default::default(),
        }
    }
    #[test]
    fn trade_run_rejects_insolvent_high_price_destination() {
        let memory=prices();
        let relations=crate::agents::faction_relations::FactionRelations::new();
        let controller=StdHashMap::new();
        let broke:BuyerLedger=[("far".into(),Some(("civ".into(),0)))].into();
        assert!(best_trade_route_with_ownership(&memory,10,"civ",
            &controller,&relations,Some(&broke)).is_none());
        let solvent:BuyerLedger=[("far".into(),Some(("civ".into(),100_000)))].into();
        let route=best_trade_route_with_ownership(&memory,10,"civ",
            &controller,&relations,Some(&solvent)).unwrap();
        assert_eq!(route.1,"home");
        assert_eq!(route.2,"far");
    }
}
"""
path.write_text(s, encoding="utf-8")
print("Galaxy 0.4 A6 installed: cash-aware market choice for speculative trade runs")
