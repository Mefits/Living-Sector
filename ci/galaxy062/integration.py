"""Galaxy 0.6.2 — connect charter to original Genesis native decision paths.

Conservative: charter gates only NEW player-directed research shifts and
contracts. It cannot starve food/water emergency AI, revoke prepaid work,
or create a separate imaginary economy. All actual CR debits remain native.
"""
from pathlib import Path
root=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2"
core=root/"crates/sim_core/src"

def one(path,old,new):
    s=path.read_text(encoding="utf8")
    n=s.count(old)
    if n!=1:
        raise RuntimeError(f"Galaxy062 integration anchor drift {path}: {n}: {old[:110]!r}")
    path.write_text(s.replace(old,new,1),encoding="utf8")

# Prevent reassigning research to a charter-disabled directive. Do not
# reset existing already-funded research progress when the policy changes.
p=core/"strategy/director.rs"
one(p,
    """        let mandate=d.research_mandates.get(&f.id).cloned();
        let c=d.commanders.entry(f.id.clone()).or_insert_with(||Commander{""",
    """        let mandate=d.research_mandates.get(&f.id).cloned();
        let charter_can_direct_research=d.faction_charters.get(&f.id)
            .is_none_or(|c|c.research_authority!=super::charter::Authority::Autonomous);
        let c=d.commanders.entry(f.id.clone()).or_insert_with(||Commander{""")
one(p,
    """            if m.mode==super::governance::MandateMode::Delegated &&
                !m.completed(&c.technologies) && c.progress==0 {""",
    """            if m.mode==super::governance::MandateMode::Delegated &&
                charter_can_direct_research &&
                !m.completed(&c.technologies) && c.progress==0 {""")

# Identify an attributed shift BEFORE it is paid. After the final shift
# completes a technology, active() no longer reports the mandate; this
# snapshot prevents both losing that receipt AND counting later free AI.
one(p,
    """        let cost=price.ceil() as i64+10;
        if treasury<cost+10_000 {return Err("research_reserve");}""",
    """        let charter_mandated_shift=super::governance::active(world,faction_id)
            .is_some_and(|m|m.mode==super::governance::MandateMode::Delegated);
        let cost=price.ceil() as i64+10;
        if treasury<cost+10_000 {return Err("research_reserve");}""")
one(p,
    """        super::governance::paid_research(world,faction_id,cost);
        return Ok(cost);""",
    """        super::governance::paid_research(world,faction_id,cost,charter_mandated_shift);
        return Ok(cost);""")

# The budget test runs before the native ECS paid research shift.
p=core/"strategy/governance.rs"
one(p,
    """        MandateMode::Delegated=>{
            mandate_spending_gate(m,cost,treasury)
        }""",
    """        MandateMode::Delegated=>{
            mandate_spending_gate(m,cost,treasury)?;
            super::charter::authorize(world,faction,
                super::charter::Department::Research,cost,treasury)
        }""")
one(p,
    """pub fn paid_research(world:&mut World,faction:&str,cost:i64){
    if let Some(mut d)=world.get_resource_mut::<Director>(){
        if let Some(m)=d.research_mandates.get_mut(faction){
            if m.mode==MandateMode::Delegated {
                m.spent_cr=m.spent_cr.saturating_add(cost);
                m.last_reason="native_research_shift_paid".into();
            }
        }
    }
}""",
    """pub fn paid_research(world:&mut World,faction:&str,cost:i64,mandated_shift:bool){
    if !mandated_shift||cost<=0 {return;}
    let mut recorded=false;
    if let Some(mut d)=world.get_resource_mut::<Director>(){
        if let Some(m)=d.research_mandates.get_mut(faction){
            if m.mode==MandateMode::Delegated {
                m.spent_cr=m.spent_cr.saturating_add(cost);
                m.last_reason="native_research_shift_paid".into();
                recorded=true;
            }
        }
    }
    if recorded {
        super::charter::record_paid(world,faction,super::charter::Department::Research,cost);
    }
}""")

p=core/"strategy/coordination.rs"
one(p,
    """        let delegated_science=super::governance::active(world,id).is_some_and(|m|
            m.mode==super::governance::MandateMode::Delegated);""",
    """        let delegated_science=super::governance::active(world,id).is_some_and(|m|
            m.mode==super::governance::MandateMode::Delegated) &&
            super::charter::may_direct(world,id,super::charter::Department::Research);""")
one(p,
    """                +if delegated_science{160.0}else{0.0}""",
    """                +if delegated_science{super::charter::priority_score(
                    world,id,super::charter::Department::Research,160.0)}else{0.0}""")

# Player economic goal must not be queued by a charter in autonomous mode.
p=core/"strategy.rs"
one(p,
    """            if members.contains(&m.location) && !crisis_factions.contains(&faction.id)
                && economic_mandate::may_commission(""",
    """            if members.contains(&m.location) && !crisis_factions.contains(&faction.id)
                && charter::may_direct(world,&faction.id,charter::Department::Economy)
                && economic_mandate::may_commission(""")
p=core/"strategy/construction.rs"
one(p,
    """                members.contains(&m.location) &&
                !world.get_resource::<super::director::Director>()""",
    """                members.contains(&m.location) &&
                super::charter::may_direct(world,&account.id,
                    super::charter::Department::Economy) &&
                !world.get_resource::<super::director::Director>()""")
# Preliminary goals and final dispatch BOTH check the actual charter.
p=core/"strategy/coordination.rs"
one(p,
    """                        if super::economic_mandate::may_commission(
                            m,view.treasury,charge).is_ok() {""",
    """                        if super::economic_mandate::may_commission(
                            m,view.treasury,charge).is_ok() &&
                            super::charter::authorize(world,id,
                                super::charter::Department::Economy,
                                charge,view.treasury).is_ok() {""")
one(p,
    """            native_score.max(160.0)""",
    """            native_score.max(super::charter::priority_score(
                world,id,super::charter::Department::Economy,160.0))""")
one(p,
    """                if super::economic_mandate::may_commission(m,treasury,charge).is_err() {""",
    """                if super::economic_mandate::may_commission(m,treasury,charge).is_err() ||
                    super::charter::authorize(world,id,
                        super::charter::Department::Economy,charge,treasury).is_err() {""")

# Record each *paid* contract only once, after the original real native
# coordinator has committed it. The charter observes, never pays itself.
p=core/"strategy/economic_mandate.rs"
one(p,
    """pub fn actual_commit(world:&mut World,faction:&str,amount:i64,tick:u64){
    if amount<=0{return;}
    if let Some(mut d)=world.get_resource_mut::<Director>(){
        if let Some(m)=d.economic_mandates.get_mut(faction){
            if m.last_commitment_tick==Some(tick){return;}
            m.spent_cr=m.spent_cr.saturating_add(amount);
            m.last_commitment_tick=Some(tick);
            m.last_reason="native_contract_funded_not_yet_delivered".into();
        }
    }
}""",
    """pub fn actual_commit(world:&mut World,faction:&str,amount:i64,tick:u64){
    if amount<=0{return;}
    let mut recorded=false;
    if let Some(mut d)=world.get_resource_mut::<Director>(){
        if let Some(m)=d.economic_mandates.get_mut(faction){
            if m.last_commitment_tick!=Some(tick) {
                m.spent_cr=m.spent_cr.saturating_add(amount);
                m.last_commitment_tick=Some(tick);
                m.last_reason="native_contract_funded_not_yet_delivered".into();
                recorded=true;
            }
        }
    }
    if recorded {
        super::charter::record_paid(world,faction,super::charter::Department::Economy,amount);
    }
}""")

# Report a specific reason when player review rather than lack of CR is
# the blocker. This changes no AI decisions.
p=core/"strategy/coordination.rs"
one(p,
    """                    head.reason="player_mandate_budget_or_reserve_blocked".into();""",
    """                    head.reason=super::charter::authorize(world,id,
                        super::charter::Department::Economy,charge,treasury)
                        .err().unwrap_or("player_mandate_budget_or_reserve_blocked").into();""")
print("Galaxy062: priorities, decision authority and shared real-paid budget wired to native systems")
