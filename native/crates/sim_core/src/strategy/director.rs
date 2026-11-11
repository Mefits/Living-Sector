//! Galaxy director: policy and durable intent; native ECS remains the economy.
use super::*;
use crate::agents::{facility::{FacilityOperations, workforce}, population::{PopIdentity,PopDemographics,PopEconomy,PopSentiment}};
use crate::ai::personality::Personality;
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Profile { pub archetypes: BTreeMap<String,f64>, pub industry:f64, pub science:f64, pub expansion:f64, pub caution:f64, pub aggression:f64 }
impl Profile {
    pub fn from_personality(p:&Personality)->Self {
        let mut mix:BTreeMap<String,f64>=["economist","pacifist","aggressor","expansionist","technocrat","isolationist"].into_iter()
            .filter_map(|k|p.prefer_goals.get(&format!("leader_{k}")).filter(|v|v.is_finite()&&**v>0.0).map(|v|(k.to_string(),f64::from(*v)))).collect();
        if mix.is_empty() {mix.insert("economist".into(),1.0);mix.insert(if p.aggression>0.6 {"aggressor"}else{"pacifist"}.into(),1.0);}
        let sum:f64=mix.values().sum(); for v in mix.values_mut(){*v/=sum;}
        let w=|s:&str|mix.get(s).copied().unwrap_or(0.0);
        Self {industry:1.0+1.4*w("economist")+0.3*w("technocrat"),science:0.65+2.0*w("technocrat")+0.3*w("pacifist"),
            expansion:(0.7+1.6*w("expansionist")+0.7*w("aggressor")-0.5*w("isolationist")).max(0.2),
            caution:0.6+0.9*w("pacifist")+1.0*w("isolationist"),aggression:w("aggressor"),archetypes:mix}
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Candidate {
    /// Stable strategic category: supply/research/expand; not a planner ID.
    pub action:String,
    pub score:f64,
    pub reason:String,
    pub available:bool,
    #[serde(default, skip_serializing_if="Option::is_none")]
    pub target:Option<String>,
}

/// Leader's *strategic* commitment, independent of HTN/GOAP/Beam executor mode.
/// Only derived preferences and a stable target are stored here; actual orders,
/// contracts and stocks remain exclusively in Genesis and NativeExecution.
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct StrategicMemory {
    pub kind:String,
    pub target:Option<String>,
    pub score:f64,
    pub since:u64,
    pub reason:String,
    pub pending:Option<PendingStrategy>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct PendingStrategy {
    pub kind:String,
    pub target:Option<String>,
    pub consecutive_cycles:u8,
    pub first_seen_tick:u64,
}

/// Stronger alternative in two consecutive *real decision cycles* (not ticks).
/// Separate from native contracts: this never cancels/creates an order.
#[derive(Clone, Copy, Debug)]
pub struct StrategySwitchPolicy { pub superiority:f64, pub confirmations:u8 }
impl Default for StrategySwitchPolicy {
    fn default()->Self { Self {superiority:1.20, confirmations:2} }
}
/// Only allow bounded, finite configuration values; invalid values use defaults.
pub fn strategy_switch_policy()->StrategySwitchPolicy {
    let mut p=StrategySwitchPolicy::default();
    if let Ok(value)=std::env::var("LIVING_SECTOR_STRATEGY_SWITCH_ADVANTAGE") {
        if let Ok(v)=value.parse::<f64>() { if v.is_finite() && (0.05..=2.0).contains(&v) {p.superiority=1.0+v;} }
    }
    if let Ok(value)=std::env::var("LIVING_SECTOR_STRATEGY_SWITCH_CYCLES") {
        if let Ok(v)=value.parse::<u8>() {if (1..=8).contains(&v) {p.confirmations=v;} }
    }
    p
}
fn same_choice(a:&Candidate,b:&Candidate)->bool {a.action==b.action && a.target==b.target}

/// Returns the chosen strategic category/target and diagnostic reason. Caller
/// must provide a freshly revalidated incumbent, never assume yesterday's
/// stored score or orders are still viable.
pub fn supply_target(goal:&Goal)->String {
    format!("{}|{}|{}",goal.goal_id,goal.destination,goal.commodity.as_str())
}
pub fn retain_or_switch(memory:&mut StrategicMemory, offers:&[Candidate], tick:u64,
    urgent_life_support:bool, native_plan_outstanding:bool, policy:StrategySwitchPolicy,
) -> Option<(Candidate,&'static str)> {
    let best=offers.iter().filter(|a|a.available && a.score.is_finite() && a.score>0.0)
        .max_by(|a,b|a.score.total_cmp(&b.score)
            .then_with(||b.action.cmp(&a.action)).then_with(||b.target.cmp(&a.target)))?;
    let incumbent=offers.iter().find(|a|a.available && a.score.is_finite() && a.score>0.0 &&
        a.action==memory.kind && a.target==memory.target);
    let choose_new=|m:&mut StrategicMemory, offer:&Candidate, reason:&'static str| {
        if m.kind!=offer.action || m.target!=offer.target {m.since=tick;}
        m.kind=offer.action.clone();m.target=offer.target.clone();m.score=offer.score;
        m.reason=reason.into();m.pending=None;
        (offer.clone(),reason)
    };
    let Some(old)=incumbent else {return Some(choose_new(memory,best,"previous_goal_unavailable"));};
    if same_choice(best,old) {return Some(choose_new(memory,old,"viable_commitment_retained"));}
    // No automatic revocation of a native prepaid contract: let its receipts
    // finish or fail first, then reconsider the strategic choice.
    if native_plan_outstanding && old.action=="supply" {
        return Some(choose_new(memory,old,"outstanding_native_plan_retained"));
    }
    // Survival priority bypasses hysteresis only for a genuinely viable life-
    // support candidate, not for an unavailable or speculative plan.
    if urgent_life_support && best.action=="supply" && !same_choice(best,old) {
        return Some(choose_new(memory,best,"urgent_life_support"));
    }
    if best.score<old.score*policy.superiority {
        return Some(choose_new(memory,old,"alternative_not_strong_enough"));
    }
    let next=match &memory.pending {
        Some(p) if p.kind==best.action && p.target==best.target =>p.consecutive_cycles.saturating_add(1),
        _=>1,
    };
    if next>=policy.confirmations {
        return Some(choose_new(memory,best,"sustained_higher_utility"));
    }
    let first_seen_tick=memory.pending.as_ref().filter(|p|p.kind==best.action && p.target==best.target)
        .map_or(tick,|p|p.first_seen_tick);
    memory.pending=Some(PendingStrategy{kind:best.action.clone(),target:best.target.clone(),
        consecutive_cycles:next,first_seen_tick});
    memory.score=old.score;
    memory.reason="alternative_pending_confirmation".into();
    Some((old.clone(),"alternative_pending_confirmation"))
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Record {pub tick:u64,pub action:String,pub reason:String,pub outcome:String}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Commander {
    pub profile:Profile, pub intent:String, pub since:u64, pub reason:String, pub candidates:Vec<Candidate>,
    pub technologies:Vec<String>, pub research:Option<String>, pub progress:u32, pub research_required:u32,
    pub last_research_tick:Option<u64>, pub history:Vec<Record>, pub crisis:bool,
    pub stations:usize, pub colonies:usize, pub completed_contracts:usize, pub blocked_cycles:u32,
    pub last_shift:Option<workforce::WorkShift>, pub next_crisis_tick:u64,
    /// Optional to preserve checkpoints written before Block III.
    #[serde(default)] pub strategic:StrategicMemory,
}
#[derive(Resource,Default,Clone,Debug,Serialize,Deserialize)]
pub struct Director {
    pub schema_version:u32,
    pub commanders:BTreeMap<String,Commander>,
    /// Saved atomically in the existing director + contract-board economic frame.
    /// Old Galaxy 0.2 checkpoints transparently default to no HTN plans.
    #[serde(default)]
    pub ai_execution: planning::NativeExecution,
    /// Saved atomically with native credits, stock and receipts.
    #[serde(default)]
    pub station_progress: BTreeMap<String,super::progression::StationDevelopment>,
    /// No directive in old checkpoints means normal independent faction AI.
    #[serde(default)]
    pub research_mandates:BTreeMap<String,super::governance::ResearchMandate>,
    /// The player can authorize one real economic goal per faction.
    #[serde(default)]
    pub economic_mandates:BTreeMap<String,super::economic_mandate::EconomicMandate>,
    /// Optional player charter. No charter preserves Galaxy 0.6.1 behaviour.
    #[serde(default)]
    pub faction_charters:BTreeMap<String,super::charter::FactionCharter>,
}
#[derive(Clone,Copy,Debug,Serialize)]
pub struct Technology {pub id:&'static str,pub name:&'static str,pub prerequisite:Option<&'static str>,pub work:u32,pub field:&'static str,pub effect:&'static str}
pub const TECHNOLOGIES:&[Technology]=&[
    Technology{id:"industrial_methods",name:"Промышленная организация",prerequisite:None,work:40,field:"industry",effect:"+1 партия за производственный цикл, с расходом сырья"},
    Technology{id:"orbital_habitats",name:"Орбитальные поселения",prerequisite:None,work:50,field:"expansion",effect:"Основание новых станций"},
    Technology{id:"deep_navigation",name:"Межзвёздная навигация",prerequisite:Some("orbital_habitats"),work:70,field:"expansion",effect:"Колонизация за пределами стартовой системы"},
    Technology{id:"automation",name:"Промышленная автоматизация",prerequisite:Some("industrial_methods"),work:90,field:"industry",effect:"Ещё +1 партия за производственный цикл, с расходом сырья"},
    Technology{id:"alloytech2",name:"Металлургия сплавов T2",prerequisite:Some("automation"),work:110,field:"industry",effect:"Разрешение оплачиваемого производства сплавов"},
    Technology{id:"survey2",name:"Геологическая разведка T2",prerequisite:Some("deep_navigation"),work:110,field:"science",effect:"Открытие месторождений редкой руды"},
    Technology{id:"drilltech2",name:"Глубинная добыча T2",prerequisite:Some("alloytech2"),work:120,field:"industry",effect:"Добыча редкой руды после разведки"},
    Technology{id:"structuretech2",name:"Модульное ядро T2",prerequisite:Some("alloytech2"),work:160,field:"industry",effect:"Разрешение проекта улучшения станции T2"},
    Technology{id:"survey3",name:"Геологическая разведка T3",prerequisite:Some("survey2"),work:160,field:"science",effect:"Открытие кристаллической руды"},
    Technology{id:"drill3",name:"Глубинная добыча T3",prerequisite:Some("drilltech2"),work:180,field:"industry",effect:"Добыча кристаллической руды после разведки"},
    Technology{id:"quantumtech3",name:"Квантовое производство T3",prerequisite:Some("structuretech2"),work:220,field:"science",effect:"Разрешение производства квантовых ядер"},
    Technology{id:"structuretech3",name:"Модульное ядро T3",prerequisite:Some("quantumtech3"),work:250,field:"industry",effect:"Разрешение проекта улучшения станции T3"},
];
pub fn has(world:&World,id:&str,tech:&str)->bool {world.get_resource::<Director>().and_then(|s|s.commanders.get(id)).is_some_and(|c|c.technologies.iter().any(|t|t==tech))}
pub fn production_bonus(world:&World,id:&str)->u32 {u32::from(has(world,id,"industrial_methods"))+u32::from(has(world,id,"automation"))}
pub fn record(c:&mut Commander,tick:u64,action:&str,reason:&str,outcome:&str){
    if c.history.last().is_some_and(|r|r.action==action&&r.reason==reason&&r.outcome==outcome){return;}
    c.history.push(Record{tick,action:action.into(),reason:reason.into(),outcome:outcome.into()});
    if c.history.len()>100 {c.history.remove(0);}
}
/// Observations are reconstructed from real stations, households and contract outcomes.
pub fn observe(world:&mut World,board:&ContractBoard,tick:u64,mult:u32){
    if world.get_resource::<Director>().is_none(){return;}
    let factions:Vec<_>=world.query::<&FactionData>().iter(world).cloned().collect();
    let ports:Vec<_>=world.query::<(&FacilityIdentity,&FacilityLocation)>().iter(world).map(|(i,l)|(i.clone(),l.location_name.clone())).collect();
    let markets:HashMap<_,_>=world.query::<(&MarketIdentity,&MarketPricing)>().iter(world).map(|(i,p)|(i.facility_location.clone(),p.clone())).collect();
    let people:Vec<_>=world.query::<(&PopIdentity,&PopDemographics)>().iter(world).map(|(i,p)|(i.faction_id.clone(),i.facility_location.clone(),p.population_count)).collect();
    let mut d=world.resource_mut::<Director>();d.schema_version=1;
    for f in factions {
        // Take a snapshot of the voluntary player rule before taking the
        // mutable commander slot from the same native Director resource.
        let mandate=d.research_mandates.get(&f.id).cloned();
        let charter_can_direct_research=d.faction_charters.get(&f.id)
            .is_none_or(|c|c.research_authority!=super::charter::Authority::Autonomous);
        let c=d.commanders.entry(f.id.clone()).or_insert_with(||Commander{profile:Profile::from_personality(&f.personality),intent:"stabilize".into(),since:tick,reason:String::new(),candidates:vec![],technologies:vec![],research:None,progress:0,research_required:0,last_research_tick:None,history:vec![],crisis:false,stations:0,colonies:0,completed_contracts:0,blocked_cycles:0,last_shift:None,next_crisis_tick:tick+1800*u64::from(mult.max(1)),strategic:StrategicMemory::default()});
        // Personality comes from the actual faction data, not from a second
        // mutable AI profile. Older checkpoints keep their strategic choices.
        c.profile=Profile::from_personality(&f.personality);
        c.crisis=people.iter().filter(|(id,_,n)|id==&f.id&&*n>0).any(|(_,loc,n)|markets.get(loc).is_some_and(|p|[Commodity::Food,Commodity::Water].iter().any(|r|p.supply.get(r).copied().unwrap_or(0.0)<(*n as f32*0.15).max(8.0))));
        let station_count=ports.iter().filter(|(i,_)|i.faction_id==f.id&&i.facility_type=="station").count();
        let colonies=ports.iter().filter(|(i,l)|i.faction_id==f.id&&i.facility_type=="station"&&l.ends_with("-colony")).count();
        let paid=board.iter().filter(|x|x.requestor_id==f.id&&x.status==ContractStatus::Paid).count();
        if colonies>c.colonies {record(c,tick,"colony_completed","Доставка материалов, переселенцев и оплаченный труд завершены","completed");}
        if paid>c.completed_contracts {record(c,tick,"contract_completed","Исполнитель завершил оплаченный контракт","completed");}
        c.stations=station_count;c.colonies=colonies;c.completed_contracts=paid;
        if let Some(ref m)=mandate {
            // A science mandate only selects a target when not replacing a
            // shift already paid for. The engine never rolls research back.
            if m.mode==super::governance::MandateMode::Delegated &&
                charter_can_direct_research &&
                !m.completed(&c.technologies) && c.progress==0 {
                if let Ok(Some(next))=super::governance::next_technology(
                    &m.target_technology,&c.technologies) {
                    if c.research.as_deref()!=Some(next.id) {
                        c.research=Some(next.id.to_string());
                        c.research_required=next.work;
                        c.progress=0;
                    }
                }
            }
        }
        if c.research.is_none(){
            let chosen=TECHNOLOGIES.iter().filter(|t|!c.technologies.iter().any(|id|id==t.id)&&t.prerequisite.is_none_or(|p|c.technologies.iter().any(|id|id==p)))
                .max_by(|a,b|{let score=|t:&Technology|match t.field{"expansion"=>c.profile.expansion,"science"=>c.profile.science,_=>c.profile.industry};score(a).total_cmp(&score(b)).then_with(||b.id.cmp(a.id))});
            if let Some(t)=chosen {c.research=Some(t.id.into());c.research_required=t.work;c.progress=0;}
        }
    }
}
/// Positive native benefit is required; personality cannot legalize an invalid action.
pub fn option_score(c:&Commander,goal:&Goal,a:&options::Alternative)->f64{
    let survival=matches!(goal.commodity,Commodity::Food|Commodity::Water);
    if a.action=="build"&&a.status=="ready"&&(goal.goal_id=="develop_colony"||goal.goal_id=="player_industry"||
        (goal.destination.ends_with("-colony")&&a.site_id.is_some())) {
        // Capability investment, not an imaginary sales forecast. All native
        // placement, stock, carrier and budget checks still precede this score.
        return 35.0*c.profile.industry+if a.site_id.is_some(){8.0}else{0.0};
    }
    if a.status!="ready"||a.covered_units<=0.0 {return -1.0;}
    let net=a.estimated_net_value.filter(|v|v.is_finite()).unwrap_or(0.0);
    if net<=0.0 && !(survival&&c.crisis) {return -1.0;}
    let weight=if a.action=="build"{c.profile.industry}else{1.0};
    let benefit=net.max(0.0).ln_1p()*weight;
    benefit+if survival&&c.crisis{1000.0}else{0.0}+f64::from(goal.shortage_ticks.min(1000))*0.01
        +if a.site_id.is_some(){5.0}else{0.0}
}
/// Research is a paid local shift; no virtual score is used as money or goods.
pub fn research(world:&mut World,faction_id:&str,tick:u64)->Result<i64,&'static str>{
    let c=world.resource::<Director>().commanders.get(faction_id).ok_or("missing_commander")?;
    if c.last_research_tick.is_some_and(|t|t>=tick){return Err("already_researched");}
    if c.research.is_none(){return Err("research_complete");}
    if c.crisis{return Err("survival_first");}
    let (payer,treasury)=world.query::<(Entity,&FactionData)>().iter(world).find(|(_,f)|f.id==faction_id).map(|(e,f)|(e,f.treasury)).ok_or("missing_faction")?;
    let mut markets:Vec<_>=world.query::<(Entity,&MarketIdentity,&MarketPricing)>().iter(world)
        .map(|(e,i,p)|(i.facility_location.clone(),e,i.facility,p.clone())).collect();markets.sort_by(|a,b|a.0.cmp(&b.0));
    for (location,market,owner,pricing) in markets {
        if world.get::<FacilityIdentity>(owner).is_none_or(|i|i.faction_id!=faction_id||i.facility_type!="station"){continue;}
        if !pricing.supply.get(&Commodity::Electronics).is_some_and(|v|v.is_finite()&&*v>=1.0){continue;}
        let price=f64::from(pricing.price(Commodity::Electronics));
        if !price.is_finite()||price<0.0||price>10000.0{continue;}
        let charter_mandated_shift=super::governance::active(world,faction_id)
            .is_some_and(|m|m.mode==super::governance::MandateMode::Delegated) &&
            super::charter::may_direct(world,faction_id,
                super::charter::Department::Research);
        let cost=price.ceil() as i64+10;
        if treasury<cost+10_000 {return Err("research_reserve");}
        // Revalidate the ENTIRE directive budget against today's actual
        // quote, before moving a single electron or real credit.
        super::governance::authorize_research(world,faction_id,cost,treasury)?;
        let occupied=workforce::occupied_workers(world,tick);
        let mut people:Vec<_>=world.query::<(Entity,&PopIdentity,&PopDemographics,&PopEconomy)>().iter(world)
            .filter(|(_,i,d,_)|i.faction_id==faction_id&&i.facility_location==location&&d.population_count*3/5-occupied.get(&i.id).copied().unwrap_or(0)>=10)
            .map(|(e,i,_,cash)|(i.id.clone(),e,cash.total_wealth)).collect();people.sort_by(|a,b|a.0.cmp(&b.0));
        let Some((pop_id,pop,wealth))=people.first() else{continue;};
        let Some(wealth_after)=wealth.checked_add(10) else{continue;};
        let Some(owner_after)=world.get::<FacilityOperations>(owner).and_then(|o|o.credits.checked_add(cost-10)) else{continue;};
        // All preconditions checked; atomic synchronous ECS mutation.
        {let mut f=world.get_mut::<FactionData>(payer).unwrap();f.treasury-=cost;f.dirty=true;}
        {let mut p=world.get_mut::<MarketPricing>(market).unwrap();*p.supply.get_mut(&Commodity::Electronics).unwrap()-=1.0;}
        if let Some(mut h)=world.get_mut::<MarketHistory>(market){h.dirty=true;}
        {let mut o=world.get_mut::<FacilityOperations>(owner).unwrap();o.credits=owner_after;o.dirty=true;}
        world.get_mut::<PopEconomy>(*pop).unwrap().total_wealth=wealth_after;
        if let Some(mut s)=world.get_mut::<PopSentiment>(*pop){s.dirty=true;}
        let mut d=world.resource_mut::<Director>();let c=d.commanders.get_mut(faction_id).unwrap();
        c.last_shift=Some(workforce::WorkShift{tick,workers:vec![(pop_id.clone(),10)],wages:10,input_payment:cost-10,processing_fee:0,last_recipe_ticks:Default::default(),produced_outputs:Default::default()});
        c.last_research_tick=Some(tick);c.progress+=10;
        if c.progress>=c.research_required {let tech=c.research.take().unwrap();c.technologies.push(tech.clone());record(c,tick,"technology_completed",&tech,"completed");}
        drop(d);
        super::governance::paid_research(world,faction_id,cost,charter_mandated_shift);
        return Ok(cost);
    }
    Err("needs_local_electronics_and_free_workers")
}
/// Low-frequency, bounded environmental damage. No gifts or automatic recovery.
pub fn environmental_events(world:&mut World,tick:u64,mult:u32){
    if world.get_resource::<Director>().is_none(){return;}
    let due:Vec<_>=world.resource::<Director>().commanders.iter().filter(|(_,c)|tick>=c.next_crisis_tick).map(|(id,_)|id.clone()).collect();
    for id in due {
        let mut ports:Vec<_>=world.query::<(Entity,&FacilityIdentity,&FacilityOperations)>().iter(world).filter(|(_,i,o)|i.faction_id==id&&i.facility_type=="refinery"&&o.condition>0.35).map(|(e,i,_)|(i.id.clone(),e)).collect();ports.sort_by(|a,b|a.0.cmp(&b.0));
        if let Some((name,e))=ports.first(){let mut o=world.get_mut::<FacilityOperations>(*e).unwrap();o.condition=(o.condition-0.3).max(0.1);o.dirty=true;
            record(world.resource_mut::<Director>().commanders.get_mut(&id).unwrap(),tick,"industrial_accident",name,"condition_minus_0.30");}
        world.resource_mut::<Director>().commanders.get_mut(&id).unwrap().next_crisis_tick=tick+2400*u64::from(mult.max(1));
    }
}

pub fn research_ready(world:&mut World,id:&str,tick:u64)->bool {
    let Some(c)=world.get_resource::<Director>().and_then(|d|d.commanders.get(id)) else{return false;};
    if c.research.is_none()||c.crisis{return false;}
    if super::governance::active(world,id)
        .is_some_and(|m|m.mode==super::governance::MandateMode::Hold) {
        return false;
    }
    let occupied=workforce::occupied_workers(world,tick);
    let treasury=world.query::<&FactionData>().iter(world).find(|f|f.id==id).map_or(0,|f|f.treasury);
    let markets:Vec<_>=world.query::<(&MarketIdentity,&MarketPricing)>().iter(world).map(|(i,p)|(i.clone(),p.clone())).collect();
    markets.iter().any(|(m,p)|world.get::<FacilityIdentity>(m.facility).is_some_and(|f|f.faction_id==id&&f.facility_type=="station")&&
        p.supply.get(&Commodity::Electronics).copied().unwrap_or(0.0)>=1.0&&
        treasury>(p.price(Commodity::Electronics)).ceil() as i64+10010&&
        super::governance::authorize_research(world,id,
            (p.price(Commodity::Electronics)).ceil() as i64+10,treasury).is_ok()&&
        world.query::<(&PopIdentity,&PopDemographics)>().iter(world).any(|(i,d)|i.faction_id==id&&i.facility_location==m.facility_location&&d.population_count*3/5-occupied.get(&i.id).copied().unwrap_or(0)>=10))
}

#[cfg(test)] mod tests {
    use super::*;
    #[test] fn personality_blends_are_normalized_and_different(){
        let mut p=Personality::balanced_trader();p.prefer_goals.insert("leader_technocrat".into(),2.0);p.prefer_goals.insert("leader_isolationist".into(),1.0);
        let a=Profile::from_personality(&p);assert!((a.archetypes.values().sum::<f64>()-1.0).abs()<1e-9);assert!(a.science>a.expansion);
        p.prefer_goals.clear();p.prefer_goals.insert("leader_aggressor".into(),1.0);p.prefer_goals.insert("leader_expansionist".into(),2.0);
        let b=Profile::from_personality(&p);assert!(b.expansion>b.science);assert!(b.expansion>a.expansion);assert!(a.caution>b.caution);
    }
    #[test] fn technology_graph_is_closed_and_acyclic(){
        let mut reached=vec![];
        for _ in 0..TECHNOLOGIES.len(){for t in TECHNOLOGIES{if t.prerequisite.is_none_or(|p|reached.contains(&p))&&!reached.contains(&t.id){reached.push(t.id);}}}
        assert_eq!(reached.len(),TECHNOLOGIES.len());
    }
}

#[cfg(test)] mod payment_tests {
    use super::*;
    #[test] fn research_conserves_money_consumes_goods_and_cannot_repeat(){
        let (mut w,board,faction,market,_)=super::super::tests::fixture(Mode::Execute);
        let owner=w.get::<MarketIdentity>(market).unwrap().facility;
        w.entity_mut(owner).insert(FacilityOperations{docking_capacity:10,services:vec![],condition:1.0,reputation:50,credits:1000,dirty:false,starving_notified:false});
        w.get_mut::<MarketPricing>(market).unwrap().supply=[(Commodity::Food,100.0),(Commodity::Water,100.0),(Commodity::Electronics,10.0),(Commodity::Tools,10.0)].into();
        let pop=w.spawn((PopIdentity{db_id:1,id:"people".into(),label:"People".into(),demographic:"workers".into(),facility:owner,facility_location:"port".into(),faction_id:"own".into()},
            PopDemographics{population_count:100,growth_rate:0.0,employed_fraction:0.0,migration_pressure:0.0},
            PopEconomy{total_wealth:1000,spending_rate:0.0,consumption:HashMap::new(),production_commodity:None,production_amount:0.0})).id();
        w.insert_resource(Director::default());observe(&mut w,&board,60,1);
        assert!(research_ready(&mut w,"own",60));
        let total=|w:&World|w.get::<FactionData>(faction).unwrap().treasury+w.get::<FacilityOperations>(owner).unwrap().credits+w.get::<PopEconomy>(pop).unwrap().total_wealth;
        let before=total(&w);let cost=research(&mut w,"own",60).unwrap();assert!(cost>10);assert_eq!(total(&w),before);
        assert_eq!(w.get::<MarketPricing>(market).unwrap().supply[&Commodity::Electronics],9.0);
        assert_eq!(research(&mut w,"own",60),Err("already_researched"));assert_eq!(total(&w),before);
        assert_eq!(workforce::occupied_workers(&mut w,60)["people"],10);
        let state=serde_json::to_string(w.resource::<Director>()).unwrap();w.insert_resource(serde_json::from_str::<Director>(&state).unwrap());
        assert_eq!(research(&mut w,"own",60),Err("already_researched"));
        w.get_mut::<MarketPricing>(market).unwrap().supply.insert(Commodity::Electronics,0.0);
        assert!(research(&mut w,"own",120).is_err());assert_eq!(total(&w),before);
    }
}
