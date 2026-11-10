"""Galaxy 0.4.1 unified economic-circulation and life-support patch.

Apply only AFTER all existing Galaxy 0.4 A/B/C/D overlays. New, isolated
integration branch. No free CR, stock, jobs, or fuel are ever created.
Fail closed if inherited sources change. The final CI validates behavior.
"""
from pathlib import Path

root=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2"
core=root/"crates/sim_core/src"
server=root/"crates/sim_server/src"

def replace_once(path:Path,old:str,new:str):
    content=path.read_text(encoding="utf-8")
    n=content.count(old)
    if n!=1:
        raise RuntimeError(f"0.4.1 source drift in {path}: expected exactly one anchor, found {n}: {old[:90]!r}")
    path.write_text(content.replace(old,new,1),encoding="utf-8")

# 1. Funds accumulated on faction ships return to its treasury as a bounded
# fleet operating levy. The original seller still keeps a 40k liquidity buffer.
# Transfer, never mint. Economy's real market receipts remain authoritative.
faction=core/"agents/faction.rs"
replace_once(faction,
    "    // --- Subsidy posting ---\n",
    """    // Galaxy 0.4.1: real ship earnings re-enter the faction economy,
    // permitting payroll, local buy orders and life-support contracts.
    ship_operating_levy(world, events, tick, tick_multiplier);

    // --- Subsidy posting ---
""")
replace_once(faction,
    "/// Faction treasury floor observed by bailouts.",
    """/// Fleet operating contribution, charged only on liquid balance ABOVE
/// the working reserve. Real CR transfer to treasury, not artificial income.
const SHIP_LEVY_INTERVAL_BASE: u64 = 50;
const SHIP_WORKING_RESERVE: i64 = 40_000;
const SHIP_LEVY_PERCENT: i64 = 10;
const SHIP_LEVY_PER_SHIP_CAP: i64 = 3_000;
const SHIP_LEVY_PER_FACTION_CAP: i64 = 24_000;

fn ship_levy_amount(credits: i64, already_assessed: i64) -> i64 {
    if credits <= SHIP_WORKING_RESERVE || already_assessed >= SHIP_LEVY_PER_FACTION_CAP {
        return 0;
    }
    (credits - SHIP_WORKING_RESERVE).saturating_mul(SHIP_LEVY_PERCENT) / 100
        .min(SHIP_LEVY_PER_SHIP_CAP)
        .min(SHIP_LEVY_PER_FACTION_CAP - already_assessed)
}

// Standalone function so a normal faction tick sees the recovered treasury
// immediately. Sort by actual ship ID for determinism across ECS iteration.
fn ship_operating_levy(
    world: &mut World, events: &mut Vec<serde_json::Value>,
    tick: u64, multiplier: u32,
) {
    use crate::agents::ship::{ShipEconomy, ShipIdentity, ShipLifecycle};
    use std::collections::{BTreeMap, HashMap};
    let cadence=SHIP_LEVY_INTERVAL_BASE.saturating_mul(u64::from(multiplier.max(1)));
    if tick==0 || tick%cadence!=0 {return;}
    let treasuries:HashMap<String,Entity> = world.query::<(Entity,&FactionData)>()
        .iter(world).map(|(e,f)|(f.id.clone(),e)).collect();
    let mut ships:Vec<_>=world.query::<(Entity,&ShipIdentity,&ShipEconomy)>()
        .iter(world).filter(|(_,id,_)|treasuries.contains_key(&id.faction_id))
        .map(|(e,id,c)|(id.id.clone(),e,id.faction_id.clone(),c.credits)).collect();
    ships.sort_by(|a,b|a.0.cmp(&b.0));
    let mut spending:BTreeMap<String,i64>=BTreeMap::new();
    for (id,ship,faction_id,cash) in ships {
        let spent=*spending.get(&faction_id).unwrap_or(&0);
        let amount=ship_levy_amount(cash,spent);
        if amount<=0 {continue;}
        let Some(&faction)=treasuries.get(&faction_id) else{continue;};
        if world.get::<FactionData>(faction)
            .is_none_or(|f|f.treasury.checked_add(amount).is_none()) {continue;}
        world.get_mut::<ShipEconomy>(ship).unwrap().credits-=amount;
        if let Some(mut life)=world.get_mut::<ShipLifecycle>(ship) {life.dirty=true;}
        let mut treasury=world.get_mut::<FactionData>(faction).unwrap();
        treasury.treasury+=amount;treasury.dirty=true;
        *spending.entry(faction_id.clone()).or_default()+=amount;
        events.push(serde_json::json!({
            "kind":"ship_operating_levy","tick":tick,"faction_id":faction_id,
            "ship_id":id,"amount":amount
        }));
    }
}

#[cfg(test)]
mod galaxy041_fleet_levy_tests {
    use super::*;
    #[test]
    fn leaves_operating_reserve_and_never_mints_cash() {
        assert_eq!(ship_levy_amount(35_000,0),0);
        assert_eq!(ship_levy_amount(40_000,0),0);
        assert_eq!(ship_levy_amount(41_000,0),100);
        assert_eq!(ship_levy_amount(100_000,0),3_000);
        assert_eq!(ship_levy_amount(100_000,23_999),1);
        assert_eq!(ship_levy_amount(100_000,24_000),0);
    }
}

/// Faction treasury floor observed by bailouts.""")
# Important Rust precedence: parenthesise the division before .min methods.
replace_once(faction,
    """    (credits - SHIP_WORKING_RESERVE).saturating_mul(SHIP_LEVY_PERCENT) / 100
        .min(SHIP_LEVY_PER_SHIP_CAP)""",
    """    ((credits - SHIP_WORKING_RESERVE).saturating_mul(SHIP_LEVY_PERCENT) / 100)
        .min(SHIP_LEVY_PER_SHIP_CAP)""")

# 2. Own-faction source is the first sourcing criterion, not the cheapest
# price across the entire galaxy. Native ship dispatch still checks routes,
# remaining stock, costs, embargoes and actual escrow.
sourcing=core/"strategy/sourcing.rs"
replace_once(sourcing,
    "            let candidate = (cost, owner != faction, location);",
    """            // First keep food, water and construction inputs within the
            // faction's own production network. Only when it cannot supply
            // a profitable quantity are external markets candidates.
            let candidate = (owner != faction, cost, location);""")
replace_once(sourcing,
    "        best.map(|(_, _, location)| location.to_owned()).ok_or(if has_stock {",
    "        best.map(|(_, _, location)| location.to_owned()).ok_or(if has_stock {")

# 3. Station dispatcher assigns scarce, free transport to paid essentials
# before regular industry deliveries. No new special-case contract type.
orders=core/"strategy/orders.rs"
replace_once(orders,
    "    ids.sort();\n    let mut sites:",
    """    ids.sort_by(|a,b| {
        let urgent=|id:&String|{
            let c=board.get(id).unwrap();
            let priority=if matches!(c.commodity,Commodity::Food|Commodity::Water)
                && c.contract_type!=ContractType::Passenger {0u8}
                else if c.contract_type==ContractType::Passenger {1} else {2};
            (priority,id)
        };
        urgent(a).cmp(&urgent(b))
    });
    let mut sites:""")

# 4. Repair precision-only trading failures. A market's floating-point stock
# can contain fractions from recipes; exact subtraction of two f32 values
# is NOT a correct stock accounting check. Keep rejecting NaN, overflow,
# negative stock, or quantity changes larger than rounding tolerance.
tx=server/"engine/transactions.rs"
replace_once(tx,
    """    if !stock.is_finite() || stock < 0.0 || !after.is_finite()
        || after - stock != sold as f32 { return Err("invalid_destination_stock"); }""",
    """    let delta=(f64::from(after)-f64::from(stock)-f64::from(sold)).abs();
    let tolerance=(f64::from(sold)*0.000_01).max(0.001);
    if !stock.is_finite() || stock<0.0 || !after.is_finite() || after<=stock
        || delta>tolerance {return Err("invalid_destination_stock");}""")

# 5. Replenish a real dock's fuel reserve from the fuel on ITS OWN local
# market. The transaction takes genuine market fuel and debits ship CR.
# A remote dock with neither market fuel nor storage fuel still can't refuel;
# the administrator must supply it via an actual cargo delivery.
replace_once(tx,
    """    let amount = REFUEL_UNITS_PER_TICK
        .min(fuel.fuel_capacity - fuel.fuel)
        .min(reserve);
    if amount <= 0.0 {
        return Err("no_fuel_transfer");
    }""",
    """    let backed_market=market_at(world,store,ship,location).ok()
        .filter(|(_,seller)|*seller==facility)
        .and_then(|(market,_)|world.get::<MarketPricing>(market)
            .map(|pricing|(market,pricing.supply.get(&Commodity::Fuel)
                .copied().unwrap_or(0.0))));
    let market_fuel=backed_market.map_or(0.0,|(_,stock)|stock);
    if !market_fuel.is_finite() || market_fuel<0.0 {return Err("invalid_fuel_state");}
    let amount=REFUEL_UNITS_PER_TICK
        .min(fuel.fuel_capacity-fuel.fuel).min(reserve+market_fuel);
    if amount <= 0.0 {return Err("no_fuel_transfer");}
    let from_reserve=amount.min(reserve);
    let from_market=amount-from_reserve;""")
replace_once(tx,
    """        .reserves
        .insert(Commodity::Fuel, reserve - amount);
    let mut ops = world.get_mut::<FacilityOperations>(facility).unwrap();""",
    """        .reserves
        .insert(Commodity::Fuel, reserve - from_reserve);
    if from_market>0.0 {
        if let Some((market,_))=backed_market {
            world.get_mut::<MarketPricing>(market).unwrap()
                .supply.insert(Commodity::Fuel, market_fuel-from_market);
            dirty_market(world,market);
        }
    }
    let mut ops = world.get_mut::<FacilityOperations>(facility).unwrap();""")

print("Galaxy 0.4.1 unified: fleet revenue, own-source priority, urgent dispatch, "
      "f32-safe trading, physical local-market fuel transfer installed.")
