//! Engineering ships choose construction alongside other utility goals.
use bevy_ecs::prelude::{Entity, World};
use crate::{agents::{ship::{ShipIdentity,ShipPosition,ShipTransit,ShipAI,ShipAction},facility::{FacilityStorage,FacilityLifecycle}},ai::behavior_tree::BtNode};
use super::ConstructionSite;

/// Non-commercial faction duty: utility is not a promised monetary reward.
pub fn utility(loyalty: f32) -> f32 { 20.0 + 30.0 * loyalty.clamp(0.0,1.0) }

pub fn capable(class: &str) -> bool {
    crate::simulation::config::ship_class(class).is_some_and(|c| c.crew_roles.contains(&"engineer"))
}

/// Planned assignment. Runtime eligibility additionally requires the active leaf.
pub fn target(bt: &BtNode<ShipAction>) -> Option<&str> {
    match bt {
        BtNode::Action(ShipAction::Construct { site_id, .. }) => Some(site_id),
        BtNode::Sequence { children, .. } => children.iter().find_map(target),
        _ => None,
    }
}
fn active(bt: &BtNode<ShipAction>) -> Option<&str> {
    match bt {
        BtNode::Action(ShipAction::Construct { site_id, .. }) => Some(site_id),
        BtNode::Sequence { children, index } => children.get(*index).and_then(active),
        _ => None,
    }
}

pub fn present(world: &mut World, site: &ConstructionSite) -> Option<String> {
    world.query::<(Entity,&ShipIdentity,&ShipPosition,&ShipTransit,&ShipAI)>().iter(world)
        .filter(|(e,id,pos,transit,ai)| capable(&id.class) && id.faction_id==site.faction_id
            && site.labor.station_order.as_ref().is_none_or(|o|o.executor_id.as_deref()==Some(id.id.as_str()))
            && ai.current_goal=="construct" && ai.current_bt.as_ref().and_then(active)==Some(site.id.as_str())
            && transit.transit.is_none() && pos.location_name.as_deref()==Some(site.location_name.as_str())
            && pos.docked_at.is_some_and(|dock| world.get::<FacilityStorage>(dock).is_some_and(|s|s.docked_ships.contains(e))
                && !world.get::<FacilityLifecycle>(dock).is_some_and(|l|l.abandoned)))
        .map(|(_,id,_,_,_)|id.id.clone()).min()
}

#[derive(Clone)]
pub struct Offer { pub site_id:String, pub location:String, pub faction:String, pub claimed_by:Option<String> }
/// Compare a viable local-system assignment with the current best utility option.
#[allow(clippy::too_many_arguments)]
pub fn choose<'a>(offers: &'a [Offer], ship: &str, faction: &str, class: &str,
    location: Option<&str>, systems: &std::collections::HashMap<String,String>,
    loyalty: f32, competing_score: f32, committed: bool) -> Option<&'a Offer> {
    if committed || !capable(class) || utility(loyalty) <= competing_score { return None; }
    let system=systems.get(location?)?;
    offers.iter().find(|o| o.faction==faction && systems.get(&o.location)==Some(system)
        && o.claimed_by.as_deref().is_none_or(|owner|owner==ship))
}

pub fn offers(world: &mut World) -> Vec<Offer> {
    let mut claims=std::collections::HashMap::<String,String>::new();
    for (id,ai) in world.query::<(&ShipIdentity,&ShipAI)>().iter(world) {
        if ai.current_goal=="construct" && capable(&id.class) {
            if let Some(site)=ai.current_bt.as_ref().and_then(target) {
                let entry=claims.entry(site.to_string()).or_insert_with(||id.id.clone());
                if id.id < *entry { *entry=id.id.clone(); }
            }
        }
    }
    let executing=crate::strategy::executing(world);
    let mut offers:Vec<_>=world.query::<&ConstructionSite>().iter(world)
        .filter(|s| !s.completed && s.remaining()==0 && s.labor.completed<s.labor.required)
        .filter(|s| !executing || s.labor.station_order.as_ref().is_some_and(|o|o.executor_id.is_some()))
        .map(|s|Offer {site_id:s.id.clone(),location:s.location_name.clone(),faction:s.faction_id.clone(),claimed_by:s.labor.station_order.as_ref().and_then(|o|o.executor_id.clone()).or_else(||claims.get(&s.id).cloned())}).collect();
    offers.sort_by(|a,b|a.site_id.cmp(&b.site_id)); offers
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    pub fn builder(w:&mut World,dock:Entity)->Entity {
        w.spawn((ShipIdentity {db_id:1,id:"builder".into(),name:"Builder".into(),class:"freighter".into(),faction_id:"civ".into(),size:crate::simulation::config::ShipSize::Medium},
            ShipPosition {location_name:Some("port".into()),docked_at:Some(dock),system_id:"sol".into(),universe_offset:(0.0,0.0),position:(0.0,0.0)},
            ShipTransit {transit:None},
            ShipAI {personality:crate::ai::personality::Personality::balanced_trader(),current_goal:"construct".into(),
                current_bt:Some(BtNode::action(ShipAction::Construct {site_id:"site".into(),location:"port".into()})),current_goal_score:40.0,last_plan_tick:0})).id()
    }
    #[test]
    fn construction_executor_must_be_engineering_ship_on_active_work_leaf() {
        let mut w=World::new();let dock=w.spawn(FacilityStorage::default()).id();let ship=builder(&mut w,dock);
        w.get_mut::<FacilityStorage>(dock).unwrap().docked_ships.push(ship);
        let site=ConstructionSite {id:"site".into(),name:"Site".into(),facility_type:"farm".into(),faction_id:"civ".into(),body_id:"earth".into(),location_name:"port".into(),
            commodity:crate::economy::commodities::Commodity::Metals,progress_delivered:600,progress_required:600,position:(0.0,0.0),spawned_at_tick:0,completed:false,dirty:false,labor:Default::default()};
        assert_eq!(present(&mut w,&site),Some("builder".into()));
        w.get_mut::<ShipIdentity>(ship).unwrap().class="courier".into();
        assert_eq!(present(&mut w,&site),None);
        w.get_mut::<ShipIdentity>(ship).unwrap().class="freighter".into();
        w.get_mut::<ShipPosition>(ship).unwrap().location_name=Some("elsewhere".into());
        assert_eq!(present(&mut w,&site),None);
        w.get_mut::<ShipPosition>(ship).unwrap().location_name=Some("port".into());
        w.get_mut::<ShipAI>(ship).unwrap().current_bt=Some(BtNode::sequence(vec![BtNode::action(ShipAction::Dock),
            BtNode::action(ShipAction::Construct {site_id:"site".into(),location:"port".into()})]));
        assert_eq!(present(&mut w,&site),None,"planned work is not actual attendance");
    }
}

#[cfg(test)]
mod choice_tests {
    use super::*;
    #[test]
    fn construction_executor_competes_with_options_and_respects_commitment() {
        let mut offers=vec![Offer {site_id:"site".into(),location:"port".into(),faction:"civ".into(),claimed_by:None}];
        let systems=[("source".into(),"sol".into()),("port".into(),"sol".into())].into();
        assert!(choose(&offers,"ship","civ","freighter",Some("source"),&systems,0.8,10.0,false).is_some());
        assert!(choose(&offers,"ship","civ","freighter",Some("source"),&systems,0.8,90.0,false).is_none());
        assert!(choose(&offers,"ship","civ","freighter",Some("source"),&systems,0.8,10.0,true).is_none());
        assert!(choose(&offers,"ship","civ","courier",Some("source"),&systems,0.8,10.0,false).is_none());
        assert!(choose(&offers,"ship","other","freighter",Some("source"),&systems,0.8,10.0,false).is_none());
        assert!(choose(&offers,"ship","civ","freighter",None,&systems,0.8,10.0,false).is_none());
        offers[0].claimed_by=Some("another".into());
        assert!(choose(&offers,"ship","civ","freighter",Some("source"),&systems,0.8,10.0,false).is_none());
    }
}
