"""Galaxy 0.6.2: explicit review blockers and true baseline autonomy."""
from pathlib import Path
root=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2"
core=root/"crates/sim_core/src"
def one(path,a,b):
    s=path.read_text(encoding="utf8")
    n=s.count(a)
    if n!=1:raise RuntimeError(f"Galaxy062 status drift {path}: {n} {a[:90]!r}")
    path.write_text(s.replace(a,b,1),encoding="utf8")

# The optional charter may decline to steer a delegated research target;
# that must NOT freeze unrelated ordinary science or charge its ledger.
p=core/"strategy/governance.rs"
one(p,
    """    let Some(m)=active(world,faction) else{return Ok(());};
    match m.mode {""",
    """    if !super::charter::may_direct(world,faction,super::charter::Department::Research){
        return Ok(()); // ordinary Genesis AI science remains independent
    }
    let Some(m)=active(world,faction) else{return Ok(());};
    match m.mode {""")
p=core/"strategy/director.rs"
one(p,
    """        let charter_mandated_shift=super::governance::active(world,faction_id)
            .is_some_and(|m|m.mode==super::governance::MandateMode::Delegated);""",
    """        let charter_mandated_shift=super::governance::active(world,faction_id)
            .is_some_and(|m|m.mode==super::governance::MandateMode::Delegated) &&
            super::charter::may_direct(world,faction_id,
                super::charter::Department::Research);""")
p=core/"strategy/coordination.rs"
one(p,
    """            match super::economic_mandate::may_commission(&m,treasury,payment){
                Err(r)=>r.to_owned(),""",
    """            match super::economic_mandate::may_commission(&m,treasury,payment)
                .and_then(|_|super::charter::authorize(world,&id,
                    super::charter::Department::Economy,payment,treasury)) {
                Err(r)=>r.to_owned(),""")
print("Galaxy062: approval-required reason visible; autonomous fallback preserved")
