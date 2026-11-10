"""Galaxy 0.4.1: unify life-support relief and service-fuel aftercare.

Still purely real balances & native cargo contracts: no fictional wages,
invented food, or automatic fuel creation. Applied after unified.py.
"""
from pathlib import Path
root=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2"
core=root/"crates/sim_core/src"

def one(path,a,b):
    s=path.read_text(encoding="utf-8")
    if s.count(a)!=1:raise RuntimeError(f"0.4.1 anchor drift in {path} ({s.count(a)} matches): {a[:90]!r}")
    path.write_text(s.replace(a,b,1),encoding="utf-8")

relief=core/"agents/faction/relief.rs"
one(relief,
"""pub const MAX_SPEND_PER_FACTION: i64 = 2_400;
pub const HOUSEHOLD_MINIMUM: i64 = 20;
pub const HOUSEHOLD_TARGET: i64 = 120;
pub const MARKET_MINIMUM: i64 = 200;
pub const MARKET_TARGET: i64 = 700;""",
"""// The original 120 CR each 400 ticks lasted only a few purchase cycles
// at a struggling colony. Allow targeted transition support, financed by
// faction treasury and bounded by the recovered real ship earnings.
pub const MAX_SPEND_PER_FACTION: i64 = 8_000;
pub const HOUSEHOLD_MINIMUM: i64 = 100;
pub const HOUSEHOLD_TARGET: i64 = 120;
pub const COLONY_EMERGENCY_TARGET: i64 = 2_000;
pub const MARKET_MINIMUM: i64 = 600;
pub const MARKET_TARGET: i64 = 3_000;""")
one(relief,
"""        if wallet.total_wealth < 0 || wallet.total_wealth >= HOUSEHOLD_MINIMUM { continue; }
        if !accounts.contains_key(&id.faction_id) { continue; }
        let starving = world.get::<PopSentiment>(entity)
            .is_some_and(|s| s.food_satisfaction < 40);
        requests.push(Request {""",
"""        if wallet.total_wealth < 0 || wallet.total_wealth >= HOUSEHOLD_MINIMUM { continue; }
        if !accounts.contains_key(&id.faction_id) { continue; }
        let starving = world.get::<PopSentiment>(entity)
            .is_some_and(|s| s.food_satisfaction < 40);
        let emergency = starving && id.facility_location.ends_with("-colony");
        let target = if emergency {COLONY_EMERGENCY_TARGET} else {HOUSEHOLD_TARGET};
        requests.push(Request {""")
one(relief,
"""            needed: HOUSEHOLD_TARGET - wallet.total_wealth,""",
"""            needed: target - wallet.total_wealth,""")
one(relief,
"""        assert_eq!(w.get::<PopEconomy>(people).unwrap().total_wealth,120);
        assert_eq!(w.get::<FacilityOperations>(station).unwrap().credits,700);""",
"""        assert_eq!(w.get::<PopEconomy>(people).unwrap().total_wealth,COLONY_EMERGENCY_TARGET);
        assert_eq!(w.get::<FacilityOperations>(station).unwrap().credits,MARKET_TARGET);""")
# Fleet funds and colony payments still sum zero across source/dest. This
# existing test already checks both accounts before and after. Add a
# regression against unfunded grants in an empty treasury.
s=relief.read_text(encoding="utf-8")
before="    #[test]\n    fn preserve_treasury_floor_and_working_cadence()"
if s.count(before)!=1:raise RuntimeError("Missing targeted relief test position")
s=s.replace(before,"""    #[test]
    fn no_faction_reserve_means_no_colony_welfare_emission() {
        let (mut w,faction,station,people,market)=scenario(FACTION_WORKING_CAPITAL_FLOOR);
        let mut events=vec![];
        tick_relief(&mut w,&mut events,25,1);
        assert!(events.is_empty());
        assert_eq!(w.get::<FactionData>(faction).unwrap().treasury,FACTION_WORKING_CAPITAL_FLOOR);
        assert_eq!(w.get::<FacilityOperations>(station).unwrap().credits,0);
        assert_eq!(w.get::<PopEconomy>(people).unwrap().total_wealth,0);
        assert_eq!(w.get::<MarketPricing>(market).unwrap().supply[&Commodity::Food],7.0);
    }

"""+before,1)
relief.write_text(s,encoding="utf-8")

# Keep provisioning real fuel at colonies: delivery has to be fully paid,
# carried by a ship and successfully landed. Only when essential food/water
# priorities are already covered may the colony ask for service fuel.
aftercare=core/"strategy/colony_development.rs"
one(aftercare,
"""    pub electronics: Option<f32>,
    pub water_reserve_target:""",
"""    pub electronics: Option<f32>,
    /// Actual market fuel; not a station's invisible free fuel reserve.
    pub fuel: Option<f32>,
    pub water_reserve_target:""")
one(aftercare,
"""        let pricing = market.map(|(_, _, p)| p);
        let (water, food, electronics, water_target, food_target)""",
"""        let pricing = market.map(|(_, _, p)| p);
        let fuel=pricing.and_then(|p|stock(p,Commodity::Fuel));
        let (water, food, electronics, water_target, food_target)""")
one(aftercare,
"""            water, food, electronics, water_reserve_target:water_target,""",
"""            water, food, electronics, fuel, water_reserve_target:water_target,""")
one(aftercare,
"""        // The electronics objective is real only if a factory has materialised,""",
"""        // Ships refuel from the real dock reserve, with additional fuel now
        // transferable from the dock's OWN market stock (0.4.1). Until a
        // carrier physically delivers it, an empty colony still has none.
        // Lower priority than food and water so rescue ships are not used
        // for fuel while residents are starving.
        if c.fuel.is_some_and(|f|f<20.0)
            && !board.iter().any(|contract|contract.destination_location==c.location
                && contract.commodity==Commodity::Fuel
                && super::outstanding(contract)
                && contract.contract_type!=ContractType::Passenger) {
            options.push(Goal{goal_id:"colony_service_fuel".into(),
                commodity:Commodity::Fuel,destination:c.location.clone(),
                shortage_ticks:0,score:600.0});
        }
        // The electronics objective is real only if a factory has materialised,""")

print("Galaxy 0.4.1 colony aftercare: paid transition income + physically shipped port fuel")
