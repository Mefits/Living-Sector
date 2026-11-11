"""Galaxy 0.6.3 — native end-to-end economic proposal regression.

This fixture is the existing Genesis strategy ECS fixture, not a second
mock economy. Must prove that clicking approve does NOT fund a contract:
only the next real native execution after the quoted recheck can do so.
"""
from pathlib import Path
p=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2/crates/sim_core/src/strategy.rs"
s=p.read_text(encoding="utf8")
anchor="""    #[test]
    fn strategy_block_portfolio_skips_unavailable_goal_and_shadow_matches_execute() {"""
addition=r'''    #[test]
    fn galaxy063_review_proposes_without_funding_then_uses_native_paid_receipt(){
        let (mut world,mut board,owner,port,source)=fixture(Mode::Execute);
        let relations=FactionRelations::new();
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
                location:"port".into(),commodity:Commodity::Water,min_stock:200,
                mode:governance::MandateMode::Delegated,
                budget_ceiling_cr:9000,treasury_floor_cr:10000,
                spent_cr:0,created_tick:0,last_commitment_tick:None,
                last_reason:String::new(),
            }
        );
        world.resource_mut::<director::Director>().faction_charters.insert(
            "own".into(),charter::FactionCharter{
                research_authority:charter::Authority::Delegated,
                economy_authority:charter::Authority::Review,
                research_priority:50,economy_priority:70,
                shared_ceiling_cr:9000,protected_treasury_cr:10000,
                approved_research_cr:0,approved_economy_cr:0,
                spent_cr:0,spent_research_cr:0,spent_economy_cr:0,
                updated_tick:0,last_reason:String::new(),
            }
        );
        let mut events=Vec::new();
        coordination::run_cycle(&mut world,&mut board,&relations,&mut events,120,1);
        let proposal=world.resource::<director::Director>()
            .economic_proposals.get("own").cloned()
            .expect("A native ready water quote should produce a review proposal");
        assert_eq!(proposal.status,economic_proposal::ProposalStatus::Pending);
        assert!(proposal.quoted_commitment_cr>0);
        assert_eq!(world.resource::<director::Director>()
            .faction_charters["own"].spent_economy_cr,0);
        assert_eq!(world.get::<FactionData>(owner).unwrap().treasury,20_000);
        assert!(!board.iter().any(|contract|
            contract.requestor_id=="own" &&
            contract.destination_location=="port" &&
            contract.commodity==Commodity::Water));

        assert_eq!(economic_proposal::decide(
            &mut world,"own","forged-or-stale-id",true,121),
            Err("stale_proposal_id"));
        assert!(economic_proposal::decide(
            &mut world,"own",&proposal.proposal_id,true,121).is_ok());
        assert_eq!(world.get::<FactionData>(owner).unwrap().treasury,20_000);
        assert_eq!(world.resource::<director::Director>()
            .economic_proposals["own"].status,
            economic_proposal::ProposalStatus::Approved);
        let charter=world.resource::<director::Director>()
            .faction_charters.get("own").unwrap().clone();
        assert_eq!(charter.spent_economy_cr,0);
        assert!(charter.approved_economy_cr>=proposal.quoted_commitment_cr);

        coordination::run_cycle(&mut world,&mut board,&relations,&mut events,180,1);
        let paid:Vec<_>=board.iter().filter(|c|
            c.requestor_id=="own"&&c.destination_location=="port"&&
            c.commodity==Commodity::Water&&
            c.funding.as_ref().is_some_and(|f|f.reserved>0)).collect();
        assert_eq!(paid.len(),1,"Only native Genesis can fund the approved quote");
        let amount=paid[0].funding.as_ref().unwrap().reserved;
        let director=world.resource::<director::Director>();
        assert_eq!(director.economic_proposals["own"].status,
            economic_proposal::ProposalStatus::Consumed);
        assert_eq!(director.economic_mandates["own"].spent_cr,amount);
        assert_eq!(director.faction_charters["own"].spent_economy_cr,amount);
        assert_eq!(world.get::<FactionData>(owner).unwrap().treasury,
            20_000-amount);
        assert_eq!(world.get::<MarketPricing>(port).unwrap().supply
            .get(&Commodity::Water).copied().unwrap_or(0.0),0.0,
            "Paid delivery is NOT physical delivery yet");
    }

'''
if s.count(anchor)!=1:raise RuntimeError("Galaxy063 native fixture anchor drift")
p.write_text(s.replace(anchor,addition+anchor,1),encoding="utf8")
print("Galaxy063: native paid-contract approval fixture added")
