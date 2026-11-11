"""Galaxy061: truthful economic-mandate states from REAL markets and contracts.

An old candidate plan is never shown as "completed". A stock minimum
reached is only an observation at the current tick; signed contracts
are not delivery. Inactive modes do not inhibit baseline faction AI.
"""
from pathlib import Path
root=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2"
p=root/"crates/sim_core/src/strategy/coordination.rs"
s=p.read_text(encoding="utf8")
a="""    world.resource_mut::<StrategyState>().last_coordinated_tick = Some(tick);"""
b="""    // Expose physical blockers or verified local stock, not a simulated
    // success event. This runs AFTER the native administrator/driver cycle.
    let actual_economic_mandates=world.get_resource::<director::Director>()
        .map(|d|d.economic_mandates.clone()).unwrap_or_default();
    let actual_economic_stocks:std::collections::HashMap<String,MarketPricing>=
        world.query::<(&MarketIdentity,&MarketPricing)>().iter(world)
            .map(|(id,market)|(id.facility_location.clone(),market.clone())).collect();
    let head_reasons:std::collections::HashMap<String,(String,String)>=
        world.resource::<StrategyState>().factions.iter().filter_map(|(id,view)|
            view.head.as_ref().map(|head|(id.clone(),(
                head.selected_option.to_string(),head.reason.clone())))).collect();
    let life_support_blockers:std::collections::HashSet<String>=
        world.get_resource::<director::Director>()
            .map(|d|d.commanders.iter().filter(|(_,c)|c.crisis)
                .map(|(id,_)|id.clone()).collect()).unwrap_or_default();
    for (id,m) in actual_economic_mandates {
        if m.last_commitment_tick==Some(tick) {continue;}
        let market=actual_economic_stocks.get(&m.location);
        let supply=market.map(|p|p.supply.get(&m.commodity).copied().unwrap_or(0.0));
        let active=board.iter().any(|contract|
            contract.requestor_id==id && contract.destination_location==m.location &&
            contract.commodity==m.commodity &&
            !matches!(contract.status,ContractStatus::Paid|ContractStatus::Expired));
        let reason=if m.mode==super::governance::MandateMode::Hold {
            "mandate_on_hold".to_owned()
        }else if m.mode==super::governance::MandateMode::Advise {
            "advisory_only".to_owned()
        }else if market.is_none(){
            "market_unavailable".to_owned()
        }else if m.kind==super::economic_mandate::EconomicKind::Industry &&
            super::economic_mandate::native_producer_exists(
                world,&id,&m.location,m.commodity) {
            // Built capacity is an ECS fact; actual production shifts and
            // their input/wage payment are independent receipts.
            "native_producer_present_actual_output_unverified".to_owned()
        }else if m.kind==super::economic_mandate::EconomicKind::Supply &&
            supply.is_some_and(|n|n.is_finite()&&n>=m.min_stock as f32) {
            "observed_stock_target_reached".to_owned()
        }else if life_support_blockers.contains(&id){
            "life_support_overrides_player_policy".to_owned()
        }else if active {
            "native_delivery_in_progress_not_completed".to_owned()
        }else {
            let payment=if m.kind==super::economic_mandate::EconomicKind::Supply{
                faction::SUBSIDY_BASE_PAYMENT*2
            }else{faction::CONSTRUCTION_BASE_PAYMENT};
            let treasury=world.query::<&FactionData>().iter(world)
                .find(|f|f.id==id).map_or(0,|f|f.treasury);
            match super::economic_mandate::may_commission(&m,treasury,payment){
                Err(r)=>r.to_owned(),
                Ok(())=>{
                    let (choice,why)=head_reasons.get(&id).cloned().unwrap_or_default();
                    if choice=="wait"||choice.is_empty() {
                        format!("waiting_native_administrator:{why}")
                    }else{
                        format!("native_administrator_chose:{choice}")
                    }
                }
            }
        };
        super::economic_mandate::status(world,&id,&reason);
    }
    world.resource_mut::<StrategyState>().last_coordinated_tick = Some(tick);"""
if s.count(a)!=1:raise RuntimeError("Galaxy061 native status anchor mismatch")
p.write_text(s.replace(a,b,1),encoding="utf8")
print("Galaxy061: player policy status now reflects actual market supply, real active contracts and blockers")
