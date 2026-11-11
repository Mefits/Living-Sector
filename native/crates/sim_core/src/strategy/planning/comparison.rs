//! A read-only, apples-to-apples comparison. No alternative can issue orders.
//! Baseline Genesis is recorded separately, because the immediate native
//! director uses a different decision horizon than this 10-unit stock probe.

use serde::Serialize;

use super::{validate_plan, ActionSpec, ControlBeamAdapter, GoalSpec, HtnAdapter,
    Planner, PlanningSnapshot, PlanResult, PlanStatus, SearchBudget, TelicGoapAdapter};

#[derive(Clone, Debug, Serialize)]
pub struct ComparedPlanner {
    pub planner_id: String,
    pub result: PlanResult,
    pub validation: String,
    pub path_action_ids: Vec<String>,
}

#[derive(Clone, Debug, Serialize)]
pub struct PlannerComparison {
    pub mode: &'static str,
    pub faction_id: String,
    pub snapshot_tick: u64,
    pub goal_id: String,
    pub catalogue_size: usize,
    pub source_note: &'static str,
    pub results: Vec<ComparedPlanner>,
}

pub fn compare_planners(snapshot:&PlanningSnapshot, goal:&GoalSpec,
    actions:&[ActionSpec], budget:SearchBudget)->PlannerComparison {
    let planners:Vec<Box<dyn Planner>>=vec![
        Box::new(HtnAdapter),Box::new(TelicGoapAdapter),Box::new(ControlBeamAdapter)
    ];
    let results=planners.iter().map(|planner| {
        let mut result=planner.plan(snapshot,goal,actions,budget);
        let validation=if result.status==PlanStatus::Ready {
            match validate_plan(snapshot,goal,actions,&result,budget) {
                Ok(())=>"valid_projected_plan".to_string(),
                Err(err)=>{
                    // Invalid proposed plans are not eligible for execution.
                    result.explanation.push_str(&format!("; rejected: {err:?}"));
                    format!("rejected:{err:?}")
                }
            }
        } else {"not_applicable_no_ready_plan".into()};
        ComparedPlanner {planner_id:planner.id().into(),
            path_action_ids:result.steps.iter().map(|s|s.action_id.clone()).collect(),
            result,validation}
    }).collect();
    PlannerComparison {mode:"read_only_same_native_snapshot",faction_id:snapshot.faction_id.clone(),
        snapshot_tick:snapshot.tick,goal_id:goal.goal_id.clone(),catalogue_size:actions.len(),
        source_note:"Predictions only. Legacy Genesis director uses a different decision horizon and cannot be ranked by this short stock probe.",
        results}
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::strategy::planning::{ActionKind,FacilityEntry,MarketEntry,RecipeEntry,ShipEntry,SCHEMA_VERSION};
    use crate::economy::commodities::Commodity;
    use std::collections::BTreeMap;

    fn market(id:&str,loc:&str,stock:&[(Commodity,f64)]) -> MarketEntry {
        MarketEntry {market_id:id.into(),facility_id:format!("facility-{id}"),location_id:loc.into(),
            stock:stock.iter().map(|(c,n)|(c.as_str().into(),*n)).collect(),
            demand:BTreeMap::new(),prices:BTreeMap::new()}
    }
    fn fixture()->(PlanningSnapshot,GoalSpec,Vec<ActionSpec>){
        let s=PlanningSnapshot{schema_version:SCHEMA_VERSION,tick:11,faction_id:"genesis".into(),
            treasury_credits:30_000,treasury_floor_credits:10_000,
            owned_markets:vec![market("belt","asteroid",&[(Commodity::Ice,8.0)]),
                market("colony","colony",&[(Commodity::Water,0.0)])],
            facilities:vec![FacilityEntry{facility_id:"facility-colony".into(),
                location_id:"colony".into(),facility_type:"refinery".into()}],
            ships:vec![ShipEntry{ship_id:"ship".into(),class:"courier".into(),
                location_id:Some("asteroid".into()),in_transit:false,free_cargo:20,fuel:100.0}],
            active_commitments:vec![],technologies:vec![],
            recipes:vec![RecipeEntry{recipe_id:"process_ice".into(),facility_type:"refinery".into(),
                inputs:vec![(Commodity::Ice,8)],outputs:vec![(Commodity::Water,10)]}],
        };
        let g=GoalSpec{goal_id:"colony-water".into(),destination_id:"colony".into(),
            commodity:Commodity::Water,target_units:10,priority:100};
        let a=vec![
            ActionSpec{action_id:"ship-ice".into(),kind:ActionKind::Deliver,
                source_id:Some("asteroid".into()),destination_id:"colony".into(),
                commodity:Some(Commodity::Ice),units:8,cost_credits:200,expected_ticks:80,
                inputs:vec![],outputs:vec![],required_facility_type:None},
            ActionSpec{action_id:"refine".into(),kind:ActionKind::Produce,
                source_id:None,destination_id:"colony".into(),commodity:Some(Commodity::Water),
                units:10,cost_credits:100,expected_ticks:40,
                inputs:vec![(Commodity::Ice,8)],outputs:vec![(Commodity::Water,10)],
                required_facility_type:Some("refinery".into())},
        ];
        (s,g,a)
    }

    #[test]
    fn all_three_search_real_ice_delivery_then_refinery_without_free_stock(){
        let (snapshot,goal,actions)=fixture();
        let original=serde_json::to_string(&snapshot).unwrap();
        let report=compare_planners(&snapshot,&goal,&actions,SearchBudget::default());
        assert_eq!(report.results.len(),3);
        for item in &report.results {
            assert_eq!(item.result.status,PlanStatus::Ready,"{}: {}",item.planner_id,item.result.explanation);
            assert_eq!(item.validation,"valid_projected_plan");
            assert_eq!(item.path_action_ids,vec!["ship-ice","refine"]);
            assert_eq!(item.result.forecast_credits,300);
        }
        assert_eq!(serde_json::to_string(&snapshot).unwrap(),original);
    }

    #[test]
    fn no_ice_means_no_fake_resources_for_any_planner(){
        let (mut snapshot,goal,actions)=fixture();
        snapshot.owned_markets[0].stock.insert("ice".into(),0.0);
        let report=compare_planners(&snapshot,&goal,&actions,SearchBudget::default());
        for item in report.results {
            assert_ne!(item.result.status,PlanStatus::Ready,"{}",item.planner_id);
            assert!(item.path_action_ids.is_empty());
        }
    }

    #[test]
    fn low_budget_does_not_allow_out_of_budget_plan(){
        let (snapshot,goal,actions)=fixture();
        let report=compare_planners(&snapshot,&goal,&actions,SearchBudget{max_nodes:1,max_depth:12});
        for item in report.results {
            assert_ne!(item.result.status,PlanStatus::Ready,"{}",item.planner_id);
            assert!(item.result.nodes_expanded<=1);
        }
    }

    #[test]
    fn alternative_route_shows_difference_between_global_cost_search_and_beam(){
        let (mut snapshot,goal,mut actions)=fixture();
        snapshot.owned_markets.push(market("spring","spring",&[(Commodity::Water,10.0)]));
        snapshot.ships.push(ShipEntry{ship_id:"second-ship".into(),class:"courier".into(),
            location_id:Some("spring".into()),in_transit:false,free_cargo:20,fuel:100.0});
        actions.push(ActionSpec{action_id:"expensive-direct-water".into(),kind:ActionKind::Deliver,
            source_id:Some("spring".into()),destination_id:"colony".into(),
            commodity:Some(Commodity::Water),units:10,cost_credits:8_000,expected_ticks:50,
            inputs:vec![],outputs:vec![],required_facility_type:None});
        let report=compare_planners(&snapshot,&goal,&actions,SearchBudget::default());
        assert!(report.results.iter().all(|r|r.validation=="valid_projected_plan"));
        let goap=&report.results[1];
        let beam=&report.results[2];
        assert_eq!(goap.path_action_ids,vec!["ship-ice","refine"]);
        assert_eq!(goap.result.forecast_credits,300);
        assert_eq!(beam.path_action_ids,vec!["expensive-direct-water"]);
        assert_eq!(beam.result.forecast_credits,8_000);
        // This single input is NOT a reliable all-game superiority claim.
    }

    #[test]
    fn budget_floor_blocks_all_three_even_when_real_ingredients_exist(){
        let (mut snapshot,goal,actions)=fixture();
        snapshot.treasury_credits=10_100;
        let report=compare_planners(&snapshot,&goal,&actions,SearchBudget::default());
        assert!(report.results.iter().all(|r|r.result.status!=PlanStatus::Ready));
    }

    #[test]
    fn conflicting_market_identity_invalidates_all_variants(){
        let (mut snapshot,goal,actions)=fixture();
        snapshot.owned_markets.push(market("second","colony",&[(Commodity::Water,900.0)]));
        let report=compare_planners(&snapshot,&goal,&actions,SearchBudget::default());
        assert!(report.results.iter().all(|r|r.result.status==PlanStatus::InvalidSnapshot));
    }

    #[test]
    fn repeated_comparison_is_deterministic_for_identical_snapshot(){
        let (snapshot,goal,actions)=fixture();
        let a=serde_json::to_string(&compare_planners(&snapshot,&goal,&actions,SearchBudget::default())).unwrap();
        let b=serde_json::to_string(&compare_planners(&snapshot,&goal,&actions,SearchBudget::default())).unwrap();
        assert_eq!(a,b);
    }
}
