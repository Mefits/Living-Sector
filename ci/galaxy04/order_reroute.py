"""Galaxy 0.4 A4: recover a fully escrowed, unaccepted station delivery
if another reachable source can fulfill it. Native purchasing, inventory,
transport and settlement remain the sole authoritative mechanisms.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[2] / "work/source/Living-Sector-Galaxy-0.2"
path = root / "crates/sim_core/src/strategy/orders.rs"
source = path.read_text(encoding="utf-8")

old = """        let o=board.get_mut(&id).unwrap().funding.as_mut().unwrap().station_order.as_mut().unwrap();
        if let Some(ship)=selected {used.insert(ship.clone());o.assign(ship,tick);}
        else {o.release("no_viable_local_carrier",tick,cooldown);}"""
new = """        // Galaxy 0.4 A4: a prepaid station contract is a commitment to
        // deliver the commodity, not a commitment to buy it from one mine.
        // Re-source only an unaccepted, fully funded offer, and only when an
        // alternative market and a specific idle carrier can execute it.
        // Do NOT move money, create goods or change an accepted contract.
        let mut assignment = selected.map(|ship| (c.source_location.clone(), ship));
        if assignment.is_none() && c.contract_type != ContractType::Passenger {
            let mut viable: Vec<(bool, u32, i64, String, String)> = Vec::new();
            for (other_source, market) in &markets {
                if other_source == &c.source_location || other_source == &c.destination_location {
                    continue;
                }
                let owner = owners.get(other_source).map_or("", String::as_str);
                let stock = market.supply.get(&c.commodity).copied().unwrap_or(0.0);
                if !stock.is_finite() || stock < c.quantity as f32 ||
                    !commerce_allowed(relations, faction, owner) { continue; }
                for ship in ships.iter().filter(|s|
                    s.faction == faction && !s.busy && !used.contains(&s.id) &&
                    s.free >= c.quantity &&
                    commerce_allowed(relations, &s.faction, destination_owner)) {
                    let Some(route) = distance(registry, &ship.location, other_source)
                        .and_then(|a| distance(registry, other_source, &c.destination_location)
                            .map(|b| a.saturating_add(b))) else { continue; };
                    if c.mission_category.as_deref() == Some(super::colony::PROJECT_TAG)
                        && !reachable(&c.destination_location, ship.speed) { continue; }
                    let Some(cost) = super::sourcing::purchase_cost(
                        market.price(c.commodity), c.quantity, relations, &ship.faction,
                        ship.reputation.get(owner).copied().unwrap_or(0), owner,
                    ) else { continue; };
                    if cost >= c.initial_payment || cost > ship.credits { continue; }
                    viable.push((owner != faction, route, cost, other_source.clone(), ship.id.clone()));
                }
            }
            // Own-faction supply wins; then shortest viable route, then
            // the actual purchase quote, with stable tie-breaking.
            viable.sort();
            if let Some((_, _, _, alternative, ship)) = viable.into_iter().next() {
                assignment = Some((alternative, ship));
            }
        }
        let contract = board.get_mut(&id).unwrap();
        if let Some((source, ship)) = assignment {
            if contract.source_location != source { contract.source_location = source; }
            used.insert(ship.clone());
            contract.funding.as_mut().unwrap().station_order.as_mut().unwrap().assign(ship,tick);
        } else {
            let reason = match markets.get(&contract.source_location) {
                None => "source_market_missing",
                Some(m) if m.supply.get(&contract.commodity).copied().unwrap_or(0.0)
                    < contract.quantity as f32 => "source_stock_short",
                _ => "no_viable_local_carrier",
            };
            contract.funding.as_mut().unwrap().station_order.as_mut().unwrap()
                .release(reason,tick,cooldown);
        }"""
if source.count(old) != 1:
    raise RuntimeError("Original station-dispatch block changed; refusing unsafe patch")
source = source.replace(old, new, 1)
path.write_text(source, encoding="utf-8")

tests = root / "crates/sim_core/src/strategy/orders/tests.rs"
data = tests.read_text(encoding="utf-8")
if "fn station_order_recovers_to_a_real_alternative_market()" in data:
    raise RuntimeError("A4 tests already applied")
data += r"""

#[test]
fn station_order_recovers_to_a_real_alternative_market() {
    let (mut world,mut board,mut registry,_,_)=fixture();
    let id=contract(&mut board);
    // Original source goes dry after funding, before a pilot accepts.
    let src=world.query::<(Entity,&MarketIdentity)>().iter(&world)
        .find(|(_,m)|m.facility_location=="source").unwrap().0;
    world.get_mut::<MarketPricing>(src).unwrap().supply.insert(Commodity::Ore,0.0);
    let market_owner=world.spawn_empty().id();
    let backup=world.spawn((
        MarketIdentity{db_id:2,id:"backup-market".into(),
            facility:market_owner,facility_location:"backup".into()},
        MarketPricing{price_elasticity:1.,spread:0.,
            prices:[(Commodity::Ore,8.0)].into(),
            supply:[(Commodity::Ore,100.0)].into(),demand:Default::default()}
    )).id();
    registry.routes.get_mut("source").unwrap().push(
        crate::world::registry::Route{to:"backup".into(),distance:2});
    registry.routes.insert("backup".into(),vec![
        crate::world::registry::Route{to:"port".into(),distance:2}]);
    let before=crate::economy::money::MoneySnapshot::capture(&mut world,&board).total;
    cycle(&mut world,&mut board,&registry,1);
    let c=board.get(&id).unwrap();
    assert_eq!(c.source_location,"backup");
    assert_eq!(contract_order(c).unwrap().executor_id.as_deref(),Some("a"));
    assert_eq!(c.status,ContractStatus::Posted);
    assert_eq!(world.get::<MarketPricing>(backup).unwrap().supply[&Commodity::Ore],100.0);
    assert_eq!(crate::economy::money::MoneySnapshot::capture(&mut world,&board).total,before);
}

#[test]
fn station_order_keeps_existing_source_when_a_carrier_is_eligible() {
    let (mut world,mut board,registry,_,_)=fixture();
    let id=contract(&mut board);
    cycle(&mut world,&mut board,&registry,1);
    assert_eq!(board.get(&id).unwrap().source_location,"source");
}
"""
tests.write_text(data, encoding="utf-8")
print("Galaxy 0.4 A4 installed: alternative source dispatch + 2 native tests")
