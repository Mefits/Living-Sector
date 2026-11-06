//! Strategic construction administrator over native sites and prepaid deliveries.
//! No second wallet, inventory, or construction completion mechanism.
use super::*;
use crate::agents::{construction::ConstructionSite, celestial_body::{BodyIdentity, BodyOrbit, BodyResources}};
use crate::economy::{contracts::ContractType, recipes};

pub const PROJECT_TAG: &str = "strategy.construction.v1";
#[derive(Clone, Debug, Serialize)]
pub struct ConstructionView {
    pub observed_tick: u64,
    pub status: String,
    pub reason: String,
    pub selected_goal: Option<Goal>,
    pub site_id: Option<String>,
    pub facility_type: Option<String>,
    pub progress_delivered: u32,
    pub progress_required: u32,
    pub contract_id: Option<String>,
}
impl ConstructionView {
    fn new(tick: u64) -> Self {
        Self { observed_tick: tick, status: "idle".into(), reason: "no_chronic_shortage".into(),
            selected_goal: None, site_id: None, facility_type: None,
            progress_delivered: 0, progress_required: 0, contract_id: None }
    }
}

/// New sites use actual producer definitions; existing saves retain their type.
fn producer(commodity: Commodity) -> Option<&'static str> {
    recipes::RECIPES.iter().find(|r| r.outputs.iter().any(|(c,_)| *c == commodity))
        .map(|r| r.facility_type).or_else(|| match commodity {
            Commodity::Ore | Commodity::Ice | Commodity::Gas => Some("mining_rig"), _ => None,
        })
}

pub fn run_cycle(world: &mut World, board: &mut ContractBoard,
    relations: &FactionRelations, events: &mut Vec<serde_json::Value>, tick: u64, mult: u32) {
    super::refresh(world, board, tick);
    let execute = executing(world);
    let mut factions: Vec<_> = world.query::<(Entity, &FactionData)>().iter(world)
        .map(|(e,f)| (e,f.clone())).collect();
    factions.sort_by(|a,b| a.1.id.cmp(&b.1.id));
    let facilities: Vec<_> = world.query::<(&FacilityIdentity,&FacilityLocation)>().iter(world)
        .map(|(i,l)| (i.clone(),l.clone())).collect();
    let markets: Vec<_> = world.query::<(&MarketIdentity,&MarketHistory,&MarketPricing)>().iter(world)
        .map(|(i,h,p)| (i.facility_location.clone(),h.shortage_ticks.clone(),p.supply.clone())).collect();
    let supply: HashMap<_,_> = markets.iter().map(|(l,_,s)| (l.clone(),s.clone())).collect();
    let owners = crate::agents::faction_relations::market_controllers(world);
    for (entity, account) in factions {
        let mut view = ConstructionView::new(tick);
        let members: Vec<_> = facilities.iter().filter(|(i,_)| i.faction_id == account.id)
            .map(|(_,l)| l.location_name.clone()).collect();
        let mut sites: Vec<_> = world.query::<&ConstructionSite>().iter(world)
            .filter(|s| s.faction_id == account.id && !s.completed).cloned().collect();
        sites.sort_by(|a,b| a.spawned_at_tick.cmp(&b.spawned_at_tick).then_with(|| a.id.cmp(&b.id)));
        let held = board.iter().filter(|c| c.requestor_id == account.id &&
            c.contract_type == ContractType::Construction && outstanding(c))
            .min_by(|a,b| a.posted_at_tick.cmp(&b.posted_at_tick).then_with(|| a.id.cmp(&b.id)));
        // Resume existing work before considering fresh deficits, including after restart.
        let mut goals: Vec<Goal> = if let Some(site) = sites.first() {
            vec![Goal { goal_id: "expand_production".into(), commodity: site.commodity,
                destination: site.location_name.clone(), shortage_ticks: 0, score: 0.0 }]
        } else {
            markets.iter().filter(|(l,_,_)| members.contains(l)).flat_map(|(l,h,_)| h.iter()
                .filter(|(_,age)| **age >= faction::CONSTRUCTION_TRIGGER_TICKS)
                .map(|(&c,&age)| Goal { goal_id: "expand_production".into(), commodity: c,
                    destination: l.clone(), shortage_ticks: age,
                    score: faction::shortage_priority(c,age,Some(&account.personality)) })).collect()
        };
        goals.sort_by(|a,b| b.score.total_cmp(&a.score).then_with(|| a.commodity.as_str().cmp(b.commodity.as_str()))
            .then_with(|| a.destination.cmp(&b.destination)));
        if let Some(c) = held {
            view.status = "waiting".into(); view.reason = "existing_contract".into();
            view.contract_id = Some(c.id.clone());
            view.selected_goal = Some(Goal { goal_id: "expand_production".into(), commodity: c.commodity,
                destination: c.destination_location.clone(), shortage_ticks: 0, score: 0.0 });
        } else {
            for goal in goals {
                let mut candidate = ConstructionView::new(tick);
                candidate.selected_goal = Some(goal.clone());
                let existing = sites.iter().find(|s| s.location_name == goal.destination && s.commodity == goal.commodity);
                let kind = existing.map(|s| s.facility_type.as_str()).or_else(|| producer(goal.commodity));
                candidate.facility_type = kind.map(str::to_string);
                let mut anchors: Vec<_> = facilities.iter().filter(|(i,l)| i.faction_id == account.id &&
                    l.location_name == goal.destination).collect();
                anchors.sort_by(|a,b| a.0.id.cmp(&b.0.id));
                let body = existing.map(|s| s.body_id.as_str()).or_else(|| anchors.first().map(|(i,_)| i.body_id.as_str()));
                let placeable = body.is_some_and(|body| world.query::<(&BodyIdentity,&BodyOrbit)>().iter(world)
                    .any(|(i,_)| i.body_id == body));
                let raw_available = body.is_some_and(|body| world.query::<(&BodyIdentity,&BodyResources)>().iter(world)
                    .any(|(i,r)| i.body_id == body && r.resources.get(&goal.commodity)
                        .is_some_and(|v| v.is_finite() && *v > 0.0)));
                let conflict = world.query::<&ConstructionSite>().iter(world).any(|s|
                    s.location_name == goal.destination && s.commodity == goal.commodity && s.faction_id != account.id);
                let amount = existing.map_or(faction::CONSTRUCTION_QUANTITY, |s| s.remaining().min(faction::CONSTRUCTION_QUANTITY));
                let source = faction::choose_logistics_source(&supply,&members,&owners,relations,
                    &account.id,&goal.destination,goal.commodity,amount as f32);
                let already_built = existing.is_none() && facilities.iter().any(|(i,l)|
                    i.faction_id == account.id && l.location_name == goal.destination && Some(i.facility_type.as_str()) == kind);
                let reason = if conflict { "site_owned_by_other_faction" }
                    else if kind.is_none() { "no_producer" }
                    else if already_built { "producer_already_present" }
                    else if !placeable || !members.contains(&goal.destination) { "invalid_site_location" }
                    else if existing.is_none() && kind == Some("mining_rig") && !raw_available { "no_local_resource" }
                    else if amount == 0 { "awaiting_materialization" }
                    else if source.is_none() { "no_accessible_stock" }
                    else if account.treasury < faction::CONSTRUCTION_MIN_TREASURY { "insufficient_budget" }
                    else { "ready" };
                if reason != "ready" {
                    candidate.status = "blocked".into(); candidate.reason = reason.into();
                    if view.selected_goal.is_none() { view = candidate; }
                    continue;
                }
                if !execute {
                    candidate.status = "proposed".into(); candidate.reason = "shadow_no_mutation".into();
                } else if !coordination::authorized(world, &account.id, "construction") {
                    candidate.status = "waiting".into(); candidate.reason = "head_priority".into();
                } else {
                    // Site must exist before any advance is taken. Reuse native placement.
                    faction::ensure_site_spawned(world,events,&account.id,goal.commodity,&goal.destination,tick);
                    let site_entity = crate::agents::construction::find_site(world,&goal.destination,goal.commodity);
                    let Some(_site_entity) = site_entity else {
                        candidate.status = "blocked".into(); candidate.reason = "invalid_site_location".into();
                        view = candidate; continue;
                    };
                    let mut payer = world.get_mut::<FactionData>(entity).unwrap();
                    payer.treasury -= faction::CONSTRUCTION_BASE_PAYMENT; payer.dirty = true;
                    let id = board.post_construction(account.id.clone(),Some(account.id.clone()),goal.commodity,
                        amount,source.unwrap(),goal.destination.clone(),faction::CONSTRUCTION_BASE_PAYMENT,tick,
                        faction::CONSTRUCTION_LIFESPAN_BASE * mult as u64);
                    board.register_prepaid(&id,FundingSource::Faction);
                    board.get_mut(&id).unwrap().mission_category = Some(PROJECT_TAG.into());
                    candidate.contract_id = Some(id); candidate.status = "commissioned".into();
                    candidate.reason = "funded_native_contract".into();
                }
                view = candidate; break;
            }
        }
        world.resource_mut::<StrategyState>().factions.get_mut(&account.id).unwrap().construction = Some(view);
    }
    super::refresh(world,board,tick);
}

/// Refresh physical progress every snapshot; decision age stays observed_tick.
pub(super) fn refresh(world: &mut World) {
    let sites: Vec<_> = world.query::<&ConstructionSite>().iter(world).cloned().collect();
    let mut state = world.resource_mut::<StrategyState>();
    for (id, faction) in &mut state.factions {
        if let Some(view) = &mut faction.construction {
            view.site_id = None;
            view.progress_delivered = 0; view.progress_required = 0;
            if let Some(goal) = &view.selected_goal {
                if let Some(site) = sites.iter().find(|s| s.faction_id == *id &&
                    s.location_name == goal.destination && s.commodity == goal.commodity) {
                    view.site_id = Some(site.id.clone()); view.facility_type = Some(site.facility_type.clone());
                    view.progress_delivered = site.progress_delivered; view.progress_required = site.progress_required;
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn fixture() -> (World, ContractBoard, Entity, Entity, Entity) {
        let (mut w,b,owner,port,source) = super::super::tests::fixture(Mode::Execute);
        w.get_mut::<FactionData>(owner).unwrap().treasury = 80_000;
        w.get_mut::<MarketPricing>(source).unwrap().supply.insert(Commodity::Food,600.0);
        w.spawn((BodyIdentity { db_id: 1, body_id: "earth".into(), name: "Earth".into(),
            body_type: "planet".into(), star_system_id: 1, system_name: "sol".into() },
            BodyOrbit { orbit_radius: 1.0, orbit_period: 100, current_angle: 0.0, universe_offset: (0.0,0.0), dirty: false }));
        (w,b,owner,port,source)
    }
    #[test]
    fn strategy_block_construction_shadow_then_funded_site_and_hold() {
        let (mut w,mut b,owner,_,_) = fixture(); let mut events = Vec::new(); let relations = FactionRelations::new();
        w.resource_mut::<StrategyState>().mode = Mode::Shadow;
        run_cycle(&mut w,&mut b,&relations,&mut events,200,1);
        assert_eq!(w.resource::<StrategyState>().factions["own"].construction.as_ref().unwrap().status,"proposed");
        assert_eq!(w.query::<&ConstructionSite>().iter(&w).count(),0);
        assert_eq!(b.iter().count(),0); assert!(events.is_empty());
        assert_eq!(w.get::<FactionData>(owner).unwrap().treasury,80_000);
        w.resource_mut::<StrategyState>().mode = Mode::Execute;
        run_cycle(&mut w,&mut b,&relations,&mut events,400,1);
        assert_eq!(w.query::<&ConstructionSite>().iter(&w).count(),1);
        assert_eq!(w.query::<&ConstructionSite>().iter(&w).next().unwrap().facility_type,"farm");
        assert_eq!(b.iter().next().unwrap().funding.as_ref().unwrap().reserved,10_000);
        assert_eq!(w.get::<FactionData>(owner).unwrap().treasury,70_000);
        run_cycle(&mut w,&mut b,&relations,&mut events,600,1);
        assert_eq!(b.iter().count(),1);
        assert_eq!(w.resource::<StrategyState>().factions["own"].projects[0].administrator,"construction");
    }
    #[test]
    fn strategy_block_construction_resume_partial_site_without_shortage() {
        let (mut w,mut b,owner,port,_) = fixture(); let mut events = Vec::new(); let relations = FactionRelations::new();
        run_cycle(&mut w,&mut b,&relations,&mut events,200,1);
        let id = b.iter().next().unwrap().id.clone();
        b.get_mut(&id).unwrap().status = ContractStatus::Paid;
        b.get_mut(&id).unwrap().funding.as_mut().unwrap().reserved = 0;
        w.get_mut::<MarketHistory>(port).unwrap().shortage_ticks.clear();
        let site = w.query::<(Entity,&ConstructionSite)>().iter(&w).next().unwrap().0;
        w.get_mut::<ConstructionSite>(site).unwrap().progress_delivered = 550;
        w.insert_resource(StrategyState { mode: Mode::Execute, ..Default::default() });
        run_cycle(&mut w,&mut b,&relations,&mut events,400,1);
        let next = b.iter().find(|c| c.id != id).unwrap();
        assert_eq!(next.quantity,50,"last shipment must fit remaining progress");
        assert_eq!(w.query::<&ConstructionSite>().iter(&w).count(),1);
        let view = w.resource::<StrategyState>().factions["own"].construction.as_ref().unwrap();
        assert_eq!(view.progress_delivered,550); assert_eq!(view.progress_required,600);
        assert_eq!(w.get::<FactionData>(owner).unwrap().treasury,60_000);
        // A removed site must not leave an apparently active scaffold in diagnostics.
        w.despawn(site); super::super::refresh(&mut w,&b,401);
        assert!(w.resource::<StrategyState>().factions["own"].construction.as_ref().unwrap().site_id.is_none());
    }
    #[test]
    fn strategy_block_construction_checks_location_budget_and_actual_producer() {
        let (mut w,mut b,owner,port,source) = fixture(); let mut events = Vec::new(); let relations = FactionRelations::new();
        w.get_mut::<MarketHistory>(port).unwrap().shortage_ticks = [(Commodity::Water,700)].into();
        w.get_mut::<MarketPricing>(source).unwrap().supply.insert(Commodity::Water,200.0);
        w.get_mut::<FactionData>(owner).unwrap().treasury = 29_999;
        run_cycle(&mut w,&mut b,&relations,&mut events,200,1);
        assert_eq!(w.resource::<StrategyState>().factions["own"].construction.as_ref().unwrap().reason,"insufficient_budget");
        assert_eq!(w.query::<&ConstructionSite>().iter(&w).count(),0);
        w.get_mut::<FactionData>(owner).unwrap().treasury = 80_000;
        let body = w.query::<(Entity,&BodyIdentity)>().iter(&w).next().unwrap().0;
        w.entity_mut(body).remove::<BodyOrbit>();
        run_cycle(&mut w,&mut b,&relations,&mut events,400,1);
        assert_eq!(w.resource::<StrategyState>().factions["own"].construction.as_ref().unwrap().reason,"invalid_site_location");
        assert_eq!(w.get::<FactionData>(owner).unwrap().treasury,80_000); assert_eq!(b.iter().count(),0);
        w.entity_mut(body).insert(BodyOrbit { orbit_radius: 1.0, orbit_period: 100, current_angle: 0.0, universe_offset: (0.0,0.0), dirty: false });
        run_cycle(&mut w,&mut b,&relations,&mut events,600,1);
        assert_eq!(w.query::<&ConstructionSite>().iter(&w).next().unwrap().facility_type,"refinery");
    }
    #[test]
    fn strategy_block_construction_does_not_take_another_factions_site() {
        let (mut w,mut b,owner,_,_) = fixture(); let mut events = Vec::new(); let relations = FactionRelations::new();
        faction::ensure_site_spawned(&mut w,&mut events,"own",Commodity::Food,"port",1);
        let site = w.query::<(Entity,&ConstructionSite)>().iter(&w).next().unwrap().0;
        w.get_mut::<ConstructionSite>(site).unwrap().faction_id = "other".into();
        run_cycle(&mut w,&mut b,&relations,&mut events,200,1);
        assert_eq!(w.resource::<StrategyState>().factions["own"].construction.as_ref().unwrap().reason,"site_owned_by_other_faction");
        assert_eq!(b.iter().count(),0); assert_eq!(w.get::<FactionData>(owner).unwrap().treasury,80_000);
    }
}
