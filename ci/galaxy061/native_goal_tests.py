"""Galaxy061 fixture regression: player priority -> real funded logistics.

Uses the EXACT existing native strategy fixture, not a second mock
economy. Shadow must not debit. Execution issues a real prepaid
ContractBoard order and the economic mandate observes only its
actually committed payment.
"""
from pathlib import Path
p=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2/crates/sim_core/src/strategy.rs"
s=p.read_text(encoding="utf8")
before="""    #[test]
    fn strategy_block_portfolio_skips_unavailable_goal_and_shadow_matches_execute() {"""
addition=r'''    #[test]
    fn galaxy061_player_supply_mandate_only_funds_a_real_native_contract(){
        let (mut world,mut board,owner,port,source)=fixture(Mode::Shadow);
        let relations=FactionRelations::new();
        // Water is an ACTUAL existing source product, not a shadow yield.
        world.get_mut::<MarketPricing>(source).unwrap().supply
            .insert(Commodity::Water,500.0);
        world.get_mut::<MarketPricing>(source).unwrap().prices
            .insert(Commodity::Water,1.0);
        world.get_mut::<MarketPricing>(port).unwrap().demand
            .insert(Commodity::Water,80.0);
        world.insert_resource(director::Director::default());
        director::observe(&mut world,&board,0,1);
        world.resource_mut::<director::Director>().economic_mandates.insert(
            "own".into(),economic_mandate::EconomicMandate{
                kind:economic_mandate::EconomicKind::Supply,
                location:"port".into(),
                commodity:Commodity::Water,
                min_stock:200,
                mode:governance::MandateMode::Delegated,
                budget_ceiling_cr:4000,treasury_floor_cr:10000,
                spent_cr:0,created_tick:0,last_commitment_tick:None,
                last_reason:String::new(),
            }
        );
        // An ordinary observer view never produces a real contract.
        run_cycle(&mut world,&mut board,&relations,60,1);
        assert!(world.resource::<StrategyState>().factions["own"]
            .goals.iter().any(|g|g.goal_id=="player_supply" &&
                g.commodity==Commodity::Water));
        assert_eq!(board.iter().count(),0);
        assert_eq!(world.get::<FactionData>(owner).unwrap().treasury,20_000);

        world.resource_mut::<StrategyState>().mode=Mode::Execute;
        let mut events=Vec::new();
        coordination::run_cycle(&mut world,&mut board,&relations,&mut events,120,1);
        let funded:Vec<_>=board.iter().filter(|contract|
            contract.requestor_id=="own" &&
            contract.destination_location=="port" &&
            contract.commodity==Commodity::Water &&
            contract.funding.as_ref().is_some_and(|x|x.reserved>0)).collect();
        assert_eq!(funded.len(),1,"Mandate must issue ONE actual funded water contract");
        let actual=funded[0].funding.as_ref().unwrap().reserved;
        assert!(actual>0);
        assert_eq!(world.resource::<director::Director>()
            .economic_mandates["own"].spent_cr,actual);
        assert_eq!(world.get::<FactionData>(owner).unwrap().treasury,
            20_000-actual);
        // An acceptance/posted offer is not yet a delivered water unit.
        assert_eq!(world.get::<MarketPricing>(port).unwrap()
            .supply.get(&Commodity::Water).copied().unwrap_or(0.0),0.0);
    }

    #[test]
    fn galaxy061_player_supply_budget_refuses_new_native_contract(){
        let (mut world,mut board,owner,port,source)=fixture(Mode::Execute);
        world.get_mut::<MarketPricing>(source).unwrap().supply
            .insert(Commodity::Water,500.0);
        world.get_mut::<MarketPricing>(source).unwrap().prices
            .insert(Commodity::Water,1.0);
        world.get_mut::<MarketPricing>(port).unwrap().demand
            .insert(Commodity::Water,80.0);
        world.insert_resource(director::Director::default());
        director::observe(&mut world,&board,0,1);
        world.resource_mut::<director::Director>().economic_mandates.insert(
            "own".into(),economic_mandate::EconomicMandate {
                kind:economic_mandate::EconomicKind::Supply,
                location:"port".into(),commodity:Commodity::Water,
                min_stock:200,mode:governance::MandateMode::Delegated,
                budget_ceiling_cr:1000,treasury_floor_cr:10000,
                spent_cr:0,created_tick:0,last_commitment_tick:None,
                last_reason:String::new(),
            }
        );
        let mut events=Vec::new();
        coordination::run_cycle(&mut world,&mut board,&FactionRelations::new(),
            &mut events,120,1);
        assert!(!board.iter().any(|c|c.requestor_id=="own"&&
            c.commodity==Commodity::Water));
        assert_eq!(world.resource::<director::Director>()
            .economic_mandates["own"].spent_cr,0);
        // Any autonomous unrelated income and purchases remain owned by
        // the baseline Director; the mandate never prints new money.
        assert!(world.get::<FactionData>(owner).unwrap().treasury<=20_000);
    }

'''
if s.count(before)!=1:raise RuntimeError("Galaxy061 native fixture tests insertion drift")
p.write_text(s.replace(before,addition+before,1),encoding="utf8")
print("Galaxy061: 2 integration regressions installed for native funded water contract and rejected budget")
