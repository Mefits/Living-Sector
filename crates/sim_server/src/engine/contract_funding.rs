//! Funding for explicitly prepaid contracts. Legacy rows remain distinguishable.
use bevy_ecs::prelude::{Entity, World};
use sim_core::agents::{
    facility::FacilityOperations,
    faction::FactionData,
    ship::{ShipEconomy, ShipFitting, ShipIdentity, ShipLifecycle},
};
use sim_core::economy::contracts::{Contract, ContractStatus, FundingSource};
use sim_core::simulation::spawner::AgentStore;

pub(super) fn quote(
    world: &World,
    store: &AgentStore,
    ship: Entity,
    c: &Contract,
) -> Result<i64, &'static str> {
    let identity = world.get::<ShipIdentity>(ship).ok_or("missing_ship")?;
    let bonus = world
        .get::<ShipFitting>(ship)
        .map(|f| f.derived.comms_bonus)
        .unwrap_or(0.0);
    let treaty = c
        .faction_id
        .as_deref()
        .map(|f| {
            sim_core::agents::faction_relations::trade_pact_payment_multiplier(
                &store.relations,
                &identity.faction_id,
                f,
            )
        })
        .unwrap_or(1.0);
    let payment = (c.payment as f64 * (1.0 + bonus as f64) * treaty as f64).round();
    if !payment.is_finite() || payment < 0.0 || payment >= i64::MAX as f64 {
        return Err("invalid_payment");
    }
    Ok(payment as i64)
}

fn account(
    world: &World,
    store: &AgentStore,
    id: &str,
    source: FundingSource,
) -> Result<(Entity, i64), &'static str> {
    match source {
        FundingSource::Facility => {
            let e = *store
                .facility_by_id
                .get(id)
                .ok_or("missing_contract_payer")?;
            Ok((
                e,
                world
                    .get::<FacilityOperations>(e)
                    .ok_or("missing_contract_payer")?
                    .credits,
            ))
        }
        FundingSource::Faction => {
            let e = *store
                .faction_by_id
                .get(id)
                .ok_or("missing_contract_payer")?;
            Ok((
                e,
                world
                    .get::<FactionData>(e)
                    .ok_or("missing_contract_payer")?
                    .treasury,
            ))
        }
    }
}

fn set_balance(world: &mut World, entity: Entity, source: FundingSource, credits: i64) {
    match source {
        FundingSource::Facility => {
            let mut ops = world.get_mut::<FacilityOperations>(entity).unwrap();
            ops.credits = credits;
            ops.dirty = true;
        }
        FundingSource::Faction => {
            let mut data = world.get_mut::<FactionData>(entity).unwrap();
            data.treasury = credits;
            data.dirty = true;
        }
    }
}

/// The BT waits for this commit before spending money or travelling on the job.
pub(super) fn accept(
    world: &mut World,
    store: &mut AgentStore,
    ship: Entity,
    id: &str,
    events: &mut Vec<serde_json::Value>,
    tick: u64,
) -> Result<(f32, i64), &'static str> {
    let c = store.contracts.get(id).ok_or("missing_contract")?.clone();
    if c.status != ContractStatus::Posted {
        return Err("contract_unavailable");
    }
    let identity = world.get::<ShipIdentity>(ship).ok_or("missing_ship")?;
    let ship_id = identity.id.clone();
    if c.faction_id.as_deref().is_some_and(|f| {
        !sim_core::agents::faction_relations::commerce_allowed(
            &store.relations,
            &identity.faction_id,
            f,
        )
    }) {
        return Err("embargo");
    }
    let economy = world.get::<ShipEconomy>(ship).ok_or("missing_economy")?;
    if economy
        .active_contract_id
        .as_deref()
        .is_some_and(|active| active != id)
    {
        return Err("already_has_contract");
    }
    let payment = quote(world, store, ship, &c)?;
    let mut debit = None;
    let mut added = 0;
    if let Some(funding) = &c.funding {
        if funding.reserved < 0 {
            return Err("invalid_contract_escrow");
        }
        added = payment.saturating_sub(funding.reserved).max(0);
        if added > 0 {
            let (payer, credits) = account(world, store, &c.requestor_id, funding.source)?;
            if credits < added {
                return Err("insufficient_contract_funding");
            }
            debit = Some((payer, funding.source, credits - added));
        }
    }
    // Exclusive World/board access: all fallible checks are above this point.
    if !store.contracts.accept(id, ship_id.clone(), tick) {
        return Err("contract_unavailable");
    }
    if let Some((payer, source, balance)) = debit {
        set_balance(world, payer, source, balance);
    }
    if let Some(funding) = store.contracts.get_mut(id).unwrap().funding.as_mut() {
        funding.reserved += added;
        funding.agreed_payment = Some(payment);
    }
    world
        .get_mut::<ShipEconomy>(ship)
        .unwrap()
        .active_contract_id = Some(id.into());
    if let Some(mut life) = world.get_mut::<ShipLifecycle>(ship) {
        life.dirty = true;
    }
    events.push(serde_json::json!({
        "kind": "contract_accepted", "contract_id": id, "contract_type": c.contract_type.as_str(),
        "ship_id": ship_id, "commodity": c.commodity.as_str(), "source": c.source_location,
        "destination": c.destination_location, "payment": c.payment,
        "agreed_payment": c.funding.as_ref().map(|_| payment), "reserved_top_up": added, "tick": tick,
    }));
    Ok((0.0, payment))
}

/// Return unused escrow after expiry/cancellation or a lower final payout.
/// Missing/overflowing beneficiary accounts leave the reserve intact for recovery.
pub(super) fn refund_closed(
    world: &mut World,
    store: &mut AgentStore,
    events: &mut Vec<serde_json::Value>,
    tick: u64,
) {
    let mut pending: Vec<_> = store
        .contracts
        .iter()
        .filter(|c| matches!(c.status, ContractStatus::Paid | ContractStatus::Expired))
        .filter_map(|c| {
            c.funding
                .as_ref()
                .filter(|f| f.reserved > 0)
                .map(|f| (c.id.clone(), c.requestor_id.clone(), f.source, f.reserved))
        })
        .collect();
    pending.sort_by(|a, b| a.0.cmp(&b.0));
    for (id, requestor, source, amount) in pending {
        let Ok((payer, balance)) = account(world, store, &requestor, source) else {
            continue;
        };
        let Some(balance) = balance.checked_add(amount) else {
            continue;
        };
        set_balance(world, payer, source, balance);
        store
            .contracts
            .get_mut(&id)
            .unwrap()
            .funding
            .as_mut()
            .unwrap()
            .reserved = 0;
        events.push(
            serde_json::json!({ "kind": "contract_escrow_refunded", "contract_id": id,
            "requestor_id": requestor, "amount": amount, "tick": tick }),
        );
    }
}
