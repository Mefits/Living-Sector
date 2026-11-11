"""Galaxy 0.6.3 — only native ready build/transport quotes can request approval.

Produce pending offers from the real Genesis comparator, then validate
the exact action/price/goal again before native dispatch. Only the native
paid receipt consumes approval. No browser-initiated economic actions.
"""
from pathlib import Path
root=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2"
core=root/"crates/sim_core/src"
def one(path,old,new):
    s=path.read_text(encoding="utf8")
    count=s.count(old)
    if count!=1:
        raise RuntimeError(f"Galaxy063 native integration source drift {path}: {count} {old[:110]!r}")
    path.write_text(s.replace(old,new,1),encoding="utf8")

p=core/"strategy/coordination.rs"
one(p,
    """    let economic_intents=world.get_resource::<director::Director>()
        .map(|d|d.economic_mandates.clone()).unwrap_or_default();
    for (id,head) in &mut decisions {""",
    """    let economic_intents=world.get_resource::<director::Director>()
        .map(|d|d.economic_mandates.clone()).unwrap_or_default();
    // Captured only from genuine READY native alternatives, before native
    // administrators charge money. Never auto-approve a proposal.
    let mut specific_offers=Vec::<(
        String,super::economic_mandate::EconomicMandate,String,i64,i64
    )>::new();
    for (id,head) in &mut decisions {""")

one(p,
    """                        let charge=comparison.alternatives.iter()
                            .find(|a|a.action==comparison.selected)
                            .map_or(0,|a|a.total_commitment.max(a.first_payment));
                        if super::economic_mandate::may_commission(
                            m,view.treasury,charge).is_ok() &&
                            super::charter::authorize(world,id,
                                super::charter::Department::Economy,
                                charge,view.treasury).is_ok() {""",
    """                        let charge=comparison.alternatives.iter()
                            .find(|a|a.action==comparison.selected)
                            .map_or(0,|a|a.total_commitment.max(a.first_payment));
                        let ready=comparison.alternatives.iter().any(|a|
                            a.action==comparison.selected && a.status=="ready");
                        let quoted_action=comparison.selected.to_string();
                        if ready && super::economic_proposal::can_offer(
                            world,id,m,charge,view.treasury) {
                            specific_offers.push((id.clone(),m.clone(),
                                quoted_action.clone(),charge,view.treasury));
                        }
                        if super::economic_mandate::may_commission(
                            m,view.treasury,charge).is_ok() &&
                            super::economic_proposal::authorize_action(
                                world,id,m,&quoted_action,charge,view.treasury,tick).is_ok() {""")

one(p,
    """                if super::economic_mandate::may_commission(m,treasury,charge).is_err() ||
                    super::charter::authorize(world,id,
                        super::charter::Department::Economy,charge,treasury).is_err() {""",
    """                if super::economic_mandate::may_commission(m,treasury,charge).is_err() ||
                    super::economic_proposal::authorize_action(
                        world,id,m,&head.selected_option,charge,treasury,tick).is_err() {""")

one(p,
    """                    head.reason=super::charter::authorize(world,id,
                        super::charter::Department::Economy,charge,treasury)
                        .err().unwrap_or("player_mandate_budget_or_reserve_blocked").into();""",
    """                    head.reason=super::economic_proposal::authorize_action(
                        world,id,m,&head.selected_option,charge,treasury,tick)
                        .err().unwrap_or("player_mandate_budget_or_reserve_blocked").into();""")

# Existing status.py inserted this marker after all native decisions.
# Publish after dispatch so approval visibility is never mistaken for
# physical completion; paid receipts are recorded by native administrators.
one(p,
    """    let actual_economic_mandates=world.get_resource::<director::Director>()
        .map(|d|d.economic_mandates.clone()).unwrap_or_default();""",
    """    super::economic_proposal::expire(world,tick);
    for (id,mandate,action,quote,treasury) in specific_offers {
        super::economic_proposal::publish(
            world,&id,&mandate,&action,quote,treasury,tick);
    }
    let actual_economic_mandates=world.get_resource::<director::Director>()
        .map(|d|d.economic_mandates.clone()).unwrap_or_default();""")

p=core/"strategy/economic_mandate.rs"
one(p,
    """    d.economic_mandates.insert(faction.to_owned(),incoming);
    Ok(())""",
    """    // A newly chosen objective never inherits an old approval token.
    if d.economic_mandates.get(faction).is_some_and(|old|old.key()!=incoming.key()){
        d.economic_proposals.remove(faction);
    }
    d.economic_mandates.insert(faction.to_owned(),incoming);
    Ok(())""")
one(p,
    """pub fn clear_mandate(world:&mut World,faction:&str)->bool{
    world.get_resource_mut::<Director>()
        .and_then(|mut d|d.economic_mandates.remove(faction))
        .is_some()
}""",
    """pub fn clear_mandate(world:&mut World,faction:&str)->bool{
    world.get_resource_mut::<Director>()
        .and_then(|mut d|{
            d.economic_proposals.remove(faction);
            d.economic_mandates.remove(faction)
        })
        .is_some()
}""")
one(p,
    """    if recorded {
        super::charter::record_paid(world,faction,super::charter::Department::Economy,amount);
    }
}""",
    """    if recorded {
        super::charter::record_paid(world,faction,super::charter::Department::Economy,amount);
        super::economic_proposal::native_paid(world,faction,amount,tick);
    }
}""")

print("Galaxy063: real comparator quotes, exact pre-dispatch approval and paid-receipt consumption")
