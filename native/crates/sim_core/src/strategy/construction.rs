//! Strategic construction administrator over native sites and prepaid deliveries.
//! No second wallet, inventory, or construction completion mechanism.
use super::*;
use crate::agents::{construction::ConstructionSite, celestial_body::{BodyIdentity, BodyOrbit, BodyResources}};
use crate::economy::{contracts::ContractType, recipes};

pub const PROJECT_TAG: &str = "strategy.construction.v1";
/// Working capital transferred to the completed facility by sim_server.
pub const STARTUP_CAPITAL: i64 = 20_000;

#[derive(Clone, Debug)]
pub(super) struct Offer {
    pub goal: Goal,
    pub facility_type: Option<String>,
    pub source: Option<String>,
    pub material: Commodity,
    pub remaining: u32,
    pub raw_richness: f32,
    pub site_id: Option<String>,
    pub reason: &'static str,
}

impl Offer {
    pub fn shipments(&self) -> u32 {
        self.remaining.div_ceil(faction::CONSTRUCTION_QUANTITY)
    }

    pub fn total_cost(&self) -> i64 {
        i64::from(self.shipments()) * faction::CONSTRUCTION_BASE_PAYMENT + STARTUP_CAPITAL + i64::from(crate::agents::construction::LABOR_REQUIRED)
    }
}

fn target_commodity(site: &ConstructionSite) -> Commodity {
    // Native sites use site-<target>-<location>-<tick>. S6 keeps the
    // target in this ID even when the persisted delivery cargo differs.
    site.id.strip_prefix("site-")
        .and_then(|id| id.split_once('-'))
        .and_then(|(target, _)| Commodity::ALL.iter().find(|c| c.as_str() == target))
        .copied()
        .unwrap_or(site.commodity)
}
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
    pub labor_completed: u32,
    pub labor_required: u32,
    pub labor_blocked_reason: Option<String>,
    pub contract_id: Option<String>,
    /// Native contract phase, separate from strategic head option semantics.
    pub delivery_status: Option<String>,
    /// Why the station dispatcher cannot currently appoint/execute a carrier.
    /// The StrategyView.reason stays "existing_contract" to avoid reposting.
    pub delivery_block_reason: Option<String>,
    pub delivery_commodity: Option<Commodity>,
    #[serde(skip)]
    pub(super) offers: Vec<Offer>,
}
impl ConstructionView {
    fn new(tick: u64) -> Self {
        Self { observed_tick: tick, status: "idle".into(), reason: "no_chronic_shortage".into(),
            selected_goal: None, site_id: None, facility_type: None,
            progress_delivered: 0, progress_required: 0, labor_completed: 0, labor_required: 0, labor_blocked_reason: None,
            contract_id: None, delivery_status: None, delivery_block_reason: None,
            delivery_commodity: None, offers: Vec::new() }
    }
}

/// New sites use actual producer definitions; existing saves retain their type.
fn producer(commodity: Commodity) -> Option<&'static str> {
    recipes::RECIPES.iter().find(|r| r.outputs.iter().any(|(c,_)| *c == commodity))
        .map(|r| r.facility_type).or_else(|| match commodity {
            Commodity::Ore | Commodity::Ice | Commodity::Gas |
                Commodity::RareOre | Commodity::CrystalOre => Some("mining_rig"), _ => None,
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
        .map(|(i,h,p)| (i.facility_location.clone(),h.shortage_ticks.clone(),p.clone())).collect();
    let sources = sourcing::Sources::new(
        markets.iter().map(|(location, _, pricing)| (location.as_str(), pricing)),
        crate::agents::faction_relations::market_controllers(world), relations,
    );
    for (entity, account) in factions {
        let mut view = ConstructionView::new(tick);
        let members: Vec<_> = facilities.iter().filter(|(i,_)| i.faction_id == account.id && i.facility_type != super::colony::DOCK_TYPE)
            .map(|(_,l)| l.location_name.clone()).collect();
        let mut sites: Vec<_> = world.query::<&ConstructionSite>().iter(world)
            .filter(|s| s.faction_id == account.id && !s.completed && s.labor.colony_source.is_none()).cloned().collect();
        sites.sort_by(|a,b| a.spawned_at_tick.cmp(&b.spawned_at_tick).then_with(|| a.id.cmp(&b.id)));
        let held = board.iter().filter(|c| c.requestor_id == account.id &&
            c.contract_type == ContractType::Construction && c.mission_category.as_deref() != Some(super::colony::PROJECT_TAG) && outstanding(c))
            .min_by(|a,b| a.posted_at_tick.cmp(&b.posted_at_tick).then_with(|| a.id.cmp(&b.id)));
        // Prefer the oldest viable site. Keep blocked sites and their
        // delivered material while evaluating other shortages.
        let existing_goals = sites.iter().map(|site| {
            let commodity = target_commodity(site);
            let age = markets.iter().find(|(location, _, _)| *location == site.location_name)
                .and_then(|(_, shortages, _)| shortages.get(&commodity)).copied().unwrap_or(0);
            Goal {
                goal_id: "expand_production".into(), commodity,
                destination: site.location_name.clone(), shortage_ticks: age,
                score: faction::shortage_priority(commodity, age, Some(&account.personality)),
            }
        });
        let mut new_goals: Vec<_> = markets.iter().filter(|(l,_,_)| members.contains(l))
            .flat_map(|(l,h,_)| h.iter()
                .filter(|(_,age)| **age >= faction::CONSTRUCTION_TRIGGER_TICKS)
                .map(|(&c,&age)| Goal { goal_id: "expand_production".into(), commodity: c,
                    destination: l.clone(), shortage_ticks: age,
                    score: faction::shortage_priority(c,age,Some(&account.personality)) }))
            .filter(|goal| !sites.iter().any(|s| s.location_name == goal.destination && target_commodity(s) == goal.commodity))
            .collect();
        // A settled colony needs a causal production chain even before a
        // failed purchase has accumulated enough market shortage history.
        if world.get_resource::<super::director::Director>().is_some() {
            for (port,loc) in facilities.iter().filter(|(i,l)|i.faction_id==account.id&&i.facility_type=="station"&&l.location_name.ends_with("-colony")) {
                let has=|kind:&str|facilities.iter().any(|(i,l)|i.faction_id==account.id&&i.facility_type==kind&&l.location_name==loc.location_name);
                let raw=world.query::<(&BodyIdentity,&BodyResources)>().iter(world).find(|(i,_)|i.body_id==port.body_id).map(|(_,r)|r.resources.clone()).unwrap_or_default();
                let target=if !has("mining_rig") {
                    [Commodity::Ice,Commodity::Gas,Commodity::Ore].into_iter().find(|c|raw.get(c).copied().unwrap_or(0.0)>0.0)
                } else if !has("refinery") {Some(Commodity::Water)}
                  else if !has("farm") {Some(Commodity::Food)}
                  // Reuse the real factory and native electronics recipes.
                  // No virtual technology, no instantaneous facility creation.
                  else if !has("factory") {Some(Commodity::Electronics)} else {None};
                if let Some(commodity)=target {
                    // Finish prerequisites before constructing later-stage producers.
                    new_goals.retain(|goal|goal.destination!=loc.location_name);
                    if !sites.iter().any(|s|s.location_name==loc.location_name) {
                        new_goals.push(Goal{goal_id:"develop_colony".into(),commodity,destination:loc.location_name.clone(),shortage_ticks:0,score:100.0});
                    }
                }
            }
        }
        // T2/T3 production investments. All prerequisites must be
        // researched and a truly paid upgrade must be completed first.
        // These goals enter the same native administrator portfolio as
        // all ordinary shortages; they do NOT create free buildings.
        for (station,loc) in facilities.iter().filter(|(id,_)|
            id.faction_id==account.id && id.facility_type=="station") {
            let tier=world.get_resource::<super::director::Director>()
                .and_then(|d|d.station_progress.get(&station.id))
                .map_or(super::progression::StationTier::T1,|s|s.tier);
            let candidate=if tier>=super::progression::StationTier::T3 &&
                super::director::has(world,&account.id,"quantumtech3") {
                Some((Commodity::QuantumCores,"qfab3",75.0))
            } else if tier>=super::progression::StationTier::T2 &&
                super::director::has(world,&account.id,"alloytech2") {
                Some((Commodity::Alloys,"alloyplant2",60.0))
            } else {None};
            let Some((commodity,kind,score))=candidate else {continue;};
            if facilities.iter().any(|(i,l)|i.faction_id==account.id &&
                l.location_name==loc.location_name && i.facility_type==kind) ||
               sites.iter().any(|site|site.location_name==loc.location_name &&
                site.facility_type==kind) {
                continue;
            }
            new_goals.push(Goal{
                goal_id:"progression_industry".into(),commodity,
                destination:loc.location_name.clone(),shortage_ticks:0,score,
            });
        }
        if let Some(m)=world.get_resource::<super::director::Director>()
            .and_then(|d|d.economic_mandates.get(&account.id)).cloned() {
            if m.kind==super::economic_mandate::EconomicKind::Industry &&
                members.contains(&m.location) &&
                super::charter::may_direct(world,&account.id,
                    super::charter::Department::Economy) &&
                !world.get_resource::<super::director::Director>()
                    .and_then(|d|d.commanders.get(&account.id))
                    .is_some_and(|c|c.crisis) &&
                super::economic_mandate::may_commission(
                    &m,account.treasury,faction::CONSTRUCTION_BASE_PAYMENT).is_ok() {
                if let Some((_,_,market))=markets.iter().find(|(loc,_,_)|*loc==m.location){
                    let stock=market.supply.get(&m.commodity).copied().unwrap_or(0.0);
                    if let Some(goal)=m.goal(stock) {
                        if !super::economic_mandate::native_producer_exists(
                            world,&account.id,&m.location,m.commodity) &&
                            !new_goals.iter().any(|g|
                                g.destination==goal.destination && g.commodity==goal.commodity) {
                            new_goals.push(goal);
                        }
                    }
                }
            }
        }
        new_goals.sort_by(|a,b| b.score.total_cmp(&a.score).then_with(|| a.commodity.as_str().cmp(b.commodity.as_str()))
            .then_with(|| a.destination.cmp(&b.destination)));
        let goals = existing_goals.chain(new_goals);
        let mut offers = Vec::new();
        if let Some(c) = held {
            view.delivery_commodity = Some(c.commodity);
            // Keep the existing-contract marker: the head's option
            // comparator relies on it to prevent duplicate commitments.
            view.status = "waiting".into(); view.reason = "existing_contract".into();
            view.contract_id = Some(c.id.clone());
            view.delivery_status = Some(match c.status {
                crate::economy::contracts::ContractStatus::Posted => "posted",
                crate::economy::contracts::ContractStatus::Accepted => "accepted",
                crate::economy::contracts::ContractStatus::PickedUp => "picked_up",
                crate::economy::contracts::ContractStatus::Delivered => "delivered",
                crate::economy::contracts::ContractStatus::Paid => "paid",
                crate::economy::contracts::ContractStatus::Expired => "expired",
            }.into());
            view.delivery_block_reason = super::orders::contract_order(c)
                .and_then(|order| order.blocked_reason.clone());
            let target = sites.iter().find(|s| s.location_name == c.destination_location && s.commodity == c.commodity)
                .map_or(c.commodity, target_commodity);
            view.selected_goal = Some(Goal { goal_id: "expand_production".into(), commodity: target,
                destination: c.destination_location.clone(), shortage_ticks: 0, score: 0.0 });
        } else {
            for goal in goals {
                let mut candidate = ConstructionView::new(tick);
                candidate.selected_goal = Some(goal.clone());
                let existing = sites.iter().find(|s| s.location_name == goal.destination && target_commodity(s) == goal.commodity);
                let kind = existing.map(|s| s.facility_type.as_str()).or_else(|| producer(goal.commodity));
                candidate.facility_type = kind.map(str::to_string);
                let mut anchors: Vec<_> = facilities.iter().filter(|(i,l)| i.faction_id == account.id &&
                    l.location_name == goal.destination).collect();
                anchors.sort_by(|a,b| a.0.id.cmp(&b.0.id));
                let body = existing.map(|s| s.body_id.as_str()).or_else(|| anchors.first().map(|(i,_)| i.body_id.as_str()));
                let placeable = body.is_some_and(|body| world.query::<(&BodyIdentity,&BodyOrbit)>().iter(world)
                    .any(|(i,_)| i.body_id == body));
                let raw_richness = body.and_then(|body| world.query::<(&BodyIdentity, &BodyResources)>()
                    .iter(world).find(|(id, _)| id.body_id == body)
                    .and_then(|(_, resources)| resources.resources.get(&goal.commodity).copied()))
                    .filter(|richness| richness.is_finite() && *richness > 0.0)
                    .unwrap_or(0.0);
                let conflict = world.query::<&ConstructionSite>().iter(world).any(|s|
                    s.location_name == goal.destination && s.commodity == goal.commodity && s.faction_id != account.id);
                let remaining = existing.map_or(
                    crate::agents::construction::CONSTRUCTION_PROGRESS_REQUIRED,
                    ConstructionSite::remaining,
                );
                let amount = remaining.min(faction::CONSTRUCTION_QUANTITY);
                let direct_material = existing.map_or(if goal.goal_id=="develop_colony"{Commodity::Metals}else{goal.commodity}, |site| site.commodity);
                let direct = sources.choose(&account.id, &goal.destination, direct_material,
                    amount, faction::CONSTRUCTION_BASE_PAYMENT);
                let (material, source) = if existing.is_none() && direct.is_err() && !conflict {
                    // A refinery can be commissioned with feedstock from a
                    // recipe the destination can actually run. Keep native
                    // delivery, material accounting and escrow for that cargo.
                    commissioning_supply(
                        &sources, &sites, &account.id, &goal, kind, amount,
                    ).map_or((goal.commodity, direct), |(material, source)| (material, Ok(source)))
                } else {
                    (direct_material, direct)
                };
                let material_conflict = existing.is_none() && material != goal.commodity && world.query::<&ConstructionSite>().iter(world)
                    .any(|site| site.location_name == goal.destination && site.commodity == material);
                let already_planned = existing.is_none() && sites.iter().any(|s|
                    s.location_name == goal.destination && Some(s.facility_type.as_str()) == kind);
                let already_built = existing.is_none() && facilities.iter().any(|(i,l)|
                    i.faction_id == account.id && l.location_name == goal.destination && Some(i.facility_type.as_str()) == kind);
                // True T1=4, T2=5, T3=6 station core cap. This is
                // independent of dock capacity and factory XP level.
                let full_station_core=existing.is_none() && facilities.iter()
                    .find(|(i,l)|i.facility_type=="station"
                        && i.faction_id==account.id
                        && l.location_name==goal.destination)
                    .is_some_and(|(station,_)|{
                        let tier=world.get_resource::<super::director::Director>()
                            .and_then(|d|d.station_progress.get(&station.id))
                            .map_or(super::progression::StationTier::T1,|d|d.tier);
                        let built=facilities.iter().filter(|(i,l)|
                            i.faction_id==account.id &&
                            l.location_name==goal.destination &&
                            i.facility_type!="station" && i.facility_type!="gate")
                            .count();
                        let in_progress=world.query::<&ConstructionSite>().iter(world)
                            .filter(|site|site.faction_id==account.id &&
                                site.location_name==goal.destination && !site.completed
                                && site.facility_type!="station").count();
                        matches!(super::progression::available_slot(tier,built,in_progress),
                            super::progression::SlotAvailability::Full{..})
                    });
                let reason = if conflict { "site_owned_by_other_faction" }
                    else if kind.is_none() { "no_producer" }
                    else if kind==Some("alloyplant2") &&
                        !super::director::has(world,&account.id,"alloytech2") { "research_required_alloytech2" }
                    else if kind==Some("qfab3") &&
                        !super::director::has(world,&account.id,"quantumtech3") { "research_required_quantumtech3" }
                    else if goal.commodity==Commodity::RareOre &&
                        !(super::director::has(world,&account.id,"drilltech2") &&
                          super::director::has(world,&account.id,"survey2")) { "research_required_rare_ore" }
                    else if goal.commodity==Commodity::CrystalOre &&
                        !(super::director::has(world,&account.id,"drill3") &&
                          super::director::has(world,&account.id,"survey3")) { "research_required_crystal_ore" }
                    else if already_built { "producer_already_present" }
                    else if full_station_core { "no_free_station_slot" }
                    else if already_planned || material_conflict { "producer_already_planned" }
                    else if !placeable || !members.contains(&goal.destination) { "invalid_site_location" }
                    else if existing.is_none() && kind == Some("mining_rig") && raw_richness == 0.0 { "no_local_resource" }
                    else if amount == 0 { "awaiting_paid_labor" }
                    else if let Err(reason) = source { reason }
                    else if account.treasury < faction::CONSTRUCTION_MIN_TREASURY { "insufficient_budget" }
                    else { "ready" };
                let mut offer = Offer {
                    goal: goal.clone(), facility_type: candidate.facility_type.clone(),
                    source: source.as_ref().ok().cloned(), material, remaining, raw_richness,
                    site_id: existing.map(|site| site.id.clone()), reason,
                };
                if offer.reason == "ready" && offer.total_cost() >
                    account.treasury.saturating_sub(faction::FACTION_SUBSIDY_FLOOR)
                {
                    offer.reason = "insufficient_project_budget";
                }
                let reason = offer.reason;
                offers.push(offer);
                candidate.delivery_commodity = Some(material);
                if reason != "ready" {
                    candidate.status = "blocked".into(); candidate.reason = reason.into();
                    if view.selected_goal.is_none() { view = candidate; }
                    continue;
                }
                if !execute {
                    candidate.status = "proposed".into(); candidate.reason = "shadow_no_mutation".into();
                    if view.status != "proposed" { view = candidate; }
                    continue;
                } else if !coordination::authorized(world, &account.id, "construction", &goal) {
                    candidate.status = "waiting".into(); candidate.reason = "head_priority".into();
                    if view.status != "waiting" { view = candidate; }
                    continue;
                } else {
                    // Site must exist before any advance is taken. Reuse native placement.
                    faction::ensure_site_spawned_with_material(
                        world, events, &account.id, goal.commodity, material,
                        kind.unwrap(), &goal.destination, tick,
                    );
                    let site_entity = crate::agents::construction::find_site(world,&goal.destination,material);
                    let Some(_site_entity) = site_entity else {
                        candidate.status = "blocked".into(); candidate.reason = "invalid_site_location".into();
                        view = candidate; continue;
                    };
                    let distance=world.get_resource::<super::colony::Navigation>().and_then(|n|source.as_ref().ok().and_then(|src|n.0.shortest_distance(src,&goal.destination))).unwrap_or(0);
                    let lifespan=if world.get_resource::<super::director::Director>().is_some(){faction::CONSTRUCTION_LIFESPAN_BASE.max(u64::from(distance)*100+1200)}else{faction::CONSTRUCTION_LIFESPAN_BASE};
                    let mut payer = world.get_mut::<FactionData>(entity).unwrap();
                    payer.treasury -= faction::CONSTRUCTION_BASE_PAYMENT; payer.dirty = true;
                    let id = board.post_construction(account.id.clone(),Some(account.id.clone()),material,
                        amount,source.unwrap(),goal.destination.clone(),faction::CONSTRUCTION_BASE_PAYMENT,tick,
                        lifespan * mult as u64);
                    board.register_prepaid(&id,FundingSource::Faction);
                    board.get_mut(&id).unwrap().mission_category = Some(PROJECT_TAG.into());
                    candidate.contract_id = Some(id); candidate.status = "commissioned".into();
                    candidate.reason = "funded_native_contract".into();
                }
                view = candidate; break;
            }
        }
        view.offers = offers;
        world.resource_mut::<StrategyState>().factions.get_mut(&account.id).unwrap().construction = Some(view);
    }
    super::refresh(world,board,tick);
}

/// Choose a real input to the intended production recipe as commissioning
/// cargo. Only try this for new sites, so a saved site's material never changes.
fn commissioning_supply(
    sources: &sourcing::Sources<'_>,
    sites: &[ConstructionSite],
    faction: &str,
    goal: &Goal,
    facility_type: Option<&str>,
    quantity: u32,
) -> Option<(Commodity, String)> {
    let local = sources.market(&goal.destination)?;
    for recipe in recipes::RECIPES {
        if Some(recipe.facility_type) != facility_type
            || !recipe.outputs.iter().any(|&(commodity, _)| commodity == goal.commodity)
            || !recipe.inputs.iter().all(|&(commodity, amount)| {
                local.supply.get(&commodity).is_some_and(|&stock| stock.is_finite() && stock >= amount as f32)
            })
        {
            continue;
        }
        for &(material, _) in recipe.inputs {
            if sites.iter().any(|site| site.location_name == goal.destination && site.commodity == material) {
                continue;
            }
            if let Ok(source) = sources.choose(faction, &goal.destination, material, quantity,
                faction::CONSTRUCTION_BASE_PAYMENT) {
                return Some((material, source));
            }
        }
    }
    None
}

/// Refresh physical progress every snapshot; decision age stays observed_tick.
pub(super) fn refresh(world: &mut World) {
    let sites: Vec<_> = world.query::<&ConstructionSite>().iter(world).cloned().collect();
    let mut state = world.resource_mut::<StrategyState>();
    for (id, faction) in &mut state.factions {
        if let Some(view) = &mut faction.construction {
            view.site_id = None;
            view.progress_delivered = 0; view.progress_required = 0;
            view.labor_completed = 0; view.labor_required = 0; view.labor_blocked_reason = None;
            if let Some(goal) = &view.selected_goal {
                if let Some(site) = sites.iter().find(|s| s.faction_id == *id &&
                    s.location_name == goal.destination && s.commodity == view.delivery_commodity.unwrap_or(goal.commodity)) {
                    view.site_id = Some(site.id.clone()); view.facility_type = Some(site.facility_type.clone());
                    view.progress_delivered = site.progress_delivered; view.progress_required = site.progress_required;
                    view.labor_completed = site.labor.completed; view.labor_required = site.labor.required;
                    view.labor_blocked_reason = site.labor.blocked_reason.clone();
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
    fn strategy_block_replans_unprofitable_offer_without_discarding_the_site() {
        let (mut world, mut board, owner, port, source) = fixture();
        let relations = FactionRelations::new();
        let mut events = Vec::new();
        run_cycle(&mut world, &mut board, &relations, &mut events, 200, 1);
        let old_id = board.iter().next().unwrap().id.clone();
        let (site_entity, site) = world.query::<(Entity, &ConstructionSite)>()
            .iter(&world).next().unwrap();
        let site_id = site.id.clone();
        world.get_mut::<ConstructionSite>(site_entity).unwrap().progress_delivered = 200;

        world.get_mut::<MarketPricing>(source).unwrap().prices.insert(Commodity::Food, 500.0);
        world.get_mut::<MarketHistory>(port).unwrap().shortage_ticks.insert(Commodity::Ore, 700);
        let body = world.query::<(Entity, &BodyIdentity)>().iter(&world).next().unwrap().0;
        world.entity_mut(body).insert(BodyResources {
            resources: [(Commodity::Ore, 1.0)].into(),
            max_resources: [(Commodity::Ore, 1.0)].into(),
        });

        sourcing::withdraw_unprofitable(&mut world, &mut board, &relations, &mut events, 400);
        let expired = board.get(&old_id).unwrap();
        assert_eq!(expired.status, ContractStatus::Expired);
        assert_eq!(expired.funding.as_ref().unwrap().reserved, 10_000);
        assert!(board.posted_for_ship(&HashMap::new()).is_empty());
        run_cycle(&mut world, &mut board, &relations, &mut events, 400, 1);
        assert_eq!(board.iter().count(), 1, "wait for native escrow refund");

        // Mirror the native refund here. The actual server owns the transfer.
        board.get_mut(&old_id).unwrap().funding.as_mut().unwrap().reserved = 0;
        world.get_mut::<FactionData>(owner).unwrap().treasury += 10_000;
        run_cycle(&mut world, &mut board, &relations, &mut events, 600, 1);
        let next = board.iter().find(|c| c.status == ContractStatus::Posted).unwrap();
        assert_eq!(next.commodity, Commodity::Ore);
        let next_id = next.id.clone();
        let old_site = world.get::<ConstructionSite>(site_entity).unwrap();
        assert_eq!(old_site.id, site_id);
        assert_eq!(old_site.progress_delivered, 200);

        assert!(board.accept(&next_id, "carrier".into(), 601));
        world.get_mut::<MarketPricing>(source).unwrap().prices.insert(Commodity::Ore, 500.0);
        sourcing::withdraw_unprofitable(&mut world, &mut board, &relations, &mut events, 800);
        assert_eq!(board.get(&next_id).unwrap().status, ContractStatus::Accepted);
        assert_eq!(events.iter().filter(|e| e["kind"] == "strategy_offer_withdrawn").count(), 1);
    }

    #[test]
    fn strategy_block_commissions_refinery_with_affordable_recipe_feedstock() {
        let (mut world, mut board, _, port, source) = fixture();
        let relations = FactionRelations::new();
        let mut events = Vec::new();
        world.get_mut::<MarketHistory>(port).unwrap().shortage_ticks =
            [(Commodity::Fuel, 700)].into();
        {
            let mut market = world.get_mut::<MarketPricing>(source).unwrap();
            market.supply.extend([(Commodity::Fuel, 200.0), (Commodity::Ice, 600.0)]);
            market.prices.extend([(Commodity::Fuel, 500.0), (Commodity::Ice, 1.0)]);
        }
        run_cycle(&mut world, &mut board, &relations, &mut events, 200, 1);
        assert_eq!(board.iter().count(), 0, "destination cannot run a fuel recipe yet");
        world.get_mut::<MarketPricing>(port).unwrap().supply.insert(Commodity::Ice, 8.0);

        run_cycle(&mut world, &mut board, &relations, &mut events, 400, 1);
        let contract = board.iter().next().unwrap();
        assert_eq!(contract.commodity, Commodity::Ice);
        assert_eq!(contract.funding.as_ref().unwrap().reserved, 10_000);
        let site = world.query::<&ConstructionSite>().iter(&world).next().unwrap();
        assert_eq!(site.commodity, Commodity::Ice);
        assert_eq!(site.facility_type, "refinery");
        let view = world.resource::<StrategyState>().factions["own"].construction.as_ref().unwrap();
        assert_eq!(view.site_id.as_deref(), Some(site.id.as_str()));
        assert_eq!(view.selected_goal.as_ref().unwrap().commodity, Commodity::Fuel);
        assert_eq!(view.delivery_commodity, Some(Commodity::Ice));
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
