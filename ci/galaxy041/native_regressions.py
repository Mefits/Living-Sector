"""Targeted Rust regressions for the single Galaxy 0.4.1 economy fix.
Run with cargo test -p sim_server --lib galaxy041. No long sim here.
"""
from pathlib import Path
root=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2"
p=root/"crates/sim_server/src/engine/transactions/tests.rs"
source=p.read_text(encoding="utf8")
if "fn galaxy041_sale_with_fractional_market_stock_preserves_real_money()" in source:
    raise RuntimeError("0.4.1 transaction tests already installed")
source+=r"""

#[test]
fn galaxy041_sale_with_fractional_market_stock_preserves_real_money() {
    use sim_core::economy::money::MoneySnapshot;
    // Refineries leave fractional f32 stocks. The old exact difference
    // comparison rejected legitimate trades.
    let mut f=Fixture::new(100.12345,0.0);
    let ship=f.ships[0];
    f.world.get_mut::<FacilityOperations>(f.facility).unwrap().credits=100_000;
    f.world.get_mut::<ShipCargo>(ship).unwrap().cargo.insert(Commodity::Ore,30);
    let before=MoneySnapshot::capture(&mut f.world,&f.store.contracts).total;
    let request=f.submit(ship,sale(30));
    f.apply(ship,request);
    assert_eq!(f.result(ship),Ok(()));
    assert!(f.world.get::<MarketPricing>(f.market).unwrap().supply[&Commodity::Ore]>130.0);
    assert_eq!(f.world.get::<ShipCargo>(ship).unwrap()
        .cargo.get(&Commodity::Ore).copied().unwrap_or(0),0);
    assert_eq!(MoneySnapshot::capture(&mut f.world,&f.store.contracts).total,before);
}

#[test]
fn galaxy041_refuel_consumes_market_fuel_and_transfers_existing_credits() {
    use sim_core::economy::money::MoneySnapshot;
    let mut f=Fixture::new(0.0,0.0);
    let ship=f.ships[0];
    f.world.get_mut::<MarketPricing>(f.market).unwrap()
        .supply.insert(Commodity::Fuel,20.0);
    let credits_before=MoneySnapshot::capture(&mut f.world,&f.store.contracts).total;
    let fuel_before=f.world.get::<ShipFuel>(ship).unwrap().fuel;
    let req=f.submit(ship,ShipTransaction::Refuel{location:"port".into()});
    f.apply(ship,req);
    assert_eq!(f.result(ship),Ok(()));
    let ship_fuel=f.world.get::<ShipFuel>(ship).unwrap().fuel;
    let market_fuel=f.world.get::<MarketPricing>(f.market).unwrap()
        .supply[&Commodity::Fuel];
    assert!(ship_fuel>fuel_before);
    assert!((fuel_before+20.0-ship_fuel-market_fuel).abs()<0.0001);
    assert_eq!(MoneySnapshot::capture(&mut f.world,&f.store.contracts).total,
        credits_before);
}
"""
p.write_text(source,encoding="utf8")
print("Galaxy 0.4.1: two real transaction regressions added")
