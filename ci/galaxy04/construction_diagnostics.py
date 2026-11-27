"""Galaxy 0.4 A5: preserve strategic 'existing_contract' semantics while
reporting the native carrier/order blocker as a separate UI diagnostic.

Never reuse order state for financial accounting or auto-complete a site.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[2] / "work/source/Living-Sector-Galaxy-0.2"
path = root / "crates/sim_core/src/strategy/construction.rs"
s = path.read_text(encoding="utf-8")
def replace_once(old, new):
    global s
    n=s.count(old)
    if n!=1: raise RuntimeError(f"Unexpected A5 source anchor count={n}: {old[:90]!r}")
    s=s.replace(old,new,1)

replace_once(
    """    pub contract_id: Option<String>,
    pub delivery_commodity: Option<Commodity>,""",
    """    pub contract_id: Option<String>,
    /// Native contract phase, separate from strategic head option semantics.
    pub delivery_status: Option<String>,
    /// Why the station dispatcher cannot currently appoint/execute a carrier.
    /// The StrategyView.reason stays "existing_contract" to avoid reposting.
    pub delivery_block_reason: Option<String>,
    pub delivery_commodity: Option<Commodity>,""",
)
replace_once(
    """labor_completed: 0, labor_required: 0, labor_blocked_reason: None, contract_id: None, delivery_commodity: None, offers: Vec::new()""",
    """labor_completed: 0, labor_required: 0, labor_blocked_reason: None,
            contract_id: None, delivery_status: None, delivery_block_reason: None,
            delivery_commodity: None, offers: Vec::new()""",
)
replace_once(
    """            view.status = "waiting".into(); view.reason = "existing_contract".into();
            view.contract_id = Some(c.id.clone());""",
    """            // Keep the existing-contract marker: the head's option
            // comparator relies on it to prevent duplicate commitments.
            view.status = "waiting".into(); view.reason = "existing_contract".into();
            view.contract_id = Some(c.id.clone());
            view.delivery_status = Some(c.status.as_str().into());
            view.delivery_block_reason = super::orders::contract_order(c)
                .and_then(|order| order.blocked_reason.clone());""",
)
# ContractStatus has no as_str method: use explicit mapping so the new
# field is stable even if debug presentation changes.
replace_once(
    """view.delivery_status = Some(c.status.as_str().into());""",
    """view.delivery_status = Some(match c.status {
                crate::economy::contracts::ContractStatus::Posted => "posted",
                crate::economy::contracts::ContractStatus::Accepted => "accepted",
                crate::economy::contracts::ContractStatus::PickedUp => "picked_up",
                crate::economy::contracts::ContractStatus::Delivered => "delivered",
                crate::economy::contracts::ContractStatus::Paid => "paid",
                crate::economy::contracts::ContractStatus::Expired => "expired",
            }.into());""",
)
path.write_text(s, encoding="utf-8")
print("Galaxy 0.4 A5 installed: native construction contract blockers")
