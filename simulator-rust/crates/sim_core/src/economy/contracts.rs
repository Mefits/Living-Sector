//! Contract board — directed demand signals between agents.
//!
//! A contract is a request posted by one agent (population, facility) for
//! another to fulfill. Example: "Pop-earth-workers needs 200 food delivered
//! to earth-station from belt-outpost; pays 3600 credits on delivery."
//!
//! Contracts close two gaps that pure speculative trading leaves open:
//! 1. Shortage signalling — a price differential alone doesn't tell a ship
//!    "this is URGENT". A posted contract does.
//! 2. Multi-tick commitment — a ship can't "reserve" a trade run at current
//!    prices across a 20-minute voyage; a contract locks in the payoff.
//!
//! ## Lifecycle
//!
//! ```text
//!  Posted → Accepted → PickedUp → Delivered → Paid → Completed
//!                                                   → Expired
//! ```
//!
//! * Posted — on the board, any qualifying ship can accept
//! * Accepted — a ship claimed it; `fulfiller_id` set
//! * PickedUp — ship loaded the cargo at source_location
//! * Delivered — ship arrived at destination_location with cargo
//! * Paid / Completed — payment transferred to the ship; closed
//! * Expired — posted_at_tick + lifespan exceeded with no acceptor
//!
//! ## Storage
//!
//! A regular `HashMap<String, Contract>` plus two indexes (by_status,
//! by_destination). The tick loop has exclusive access during each tick
//! phase, so no locks are needed. Ships query the board during their
//! planner phase; populations/facilities post during theirs.

use crate::economy::commodities::Commodity;
use serde::Serialize;
use std::collections::HashMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ContractType {
    /// Deliver commodity from source to destination.
    Delivery,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ContractStatus {
    Posted,
    Accepted,
    PickedUp,
    Delivered,
    Paid,
    Expired,
}

#[derive(Debug, Clone, Serialize)]
pub struct Contract {
    pub id: String,
    pub contract_type: ContractType,
    pub status: ContractStatus,
    /// Who posted (e.g. "pop-earth-workers" or "facility-..."). Serialization only.
    pub requestor_id: String,
    /// Ship id once accepted; None while Posted.
    pub fulfiller_id: Option<String>,
    pub commodity: Commodity,
    pub quantity: u32,
    pub source_location: String,
    pub destination_location: String,
    pub payment: i64,
    pub posted_at_tick: u64,
    pub accepted_at_tick: Option<u64>,
    pub expires_at_tick: u64,
}

/// In-memory contract board. Lives in `AgentStore`.
#[derive(Debug, Default)]
pub struct ContractBoard {
    contracts: HashMap<String, Contract>,
    next_id: u64,
    /// status → list of contract ids
    by_status: HashMap<ContractStatus, Vec<String>>,
    /// destination_location → list of contract ids currently Posted
    posted_by_destination: HashMap<String, Vec<String>>,
}

impl ContractBoard {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn len(&self) -> usize {
        self.contracts.len()
    }

    pub fn is_empty(&self) -> bool {
        self.contracts.is_empty()
    }

    pub fn get(&self, id: &str) -> Option<&Contract> {
        self.contracts.get(id)
    }

    pub fn get_mut(&mut self, id: &str) -> Option<&mut Contract> {
        self.contracts.get_mut(id)
    }

    pub fn iter(&self) -> impl Iterator<Item = &Contract> {
        self.contracts.values()
    }

    /// Post a new delivery contract and return its id.
    #[allow(clippy::too_many_arguments)]
    pub fn post_delivery(
        &mut self,
        requestor_id: String,
        commodity: Commodity,
        quantity: u32,
        source_location: String,
        destination_location: String,
        payment: i64,
        posted_at_tick: u64,
        lifespan_ticks: u64,
    ) -> String {
        self.next_id += 1;
        let id = format!("contract-{}", self.next_id);
        let contract = Contract {
            id: id.clone(),
            contract_type: ContractType::Delivery,
            status: ContractStatus::Posted,
            requestor_id,
            fulfiller_id: None,
            commodity,
            quantity,
            source_location: source_location.clone(),
            destination_location: destination_location.clone(),
            payment,
            posted_at_tick,
            accepted_at_tick: None,
            expires_at_tick: posted_at_tick + lifespan_ticks,
        };
        self.contracts.insert(id.clone(), contract);
        self.by_status
            .entry(ContractStatus::Posted)
            .or_default()
            .push(id.clone());
        self.posted_by_destination
            .entry(destination_location)
            .or_default()
            .push(id.clone());
        id
    }

    /// Return all posted contracts whose destination matches `location`.
    pub fn posted_with_destination(&self, location: &str) -> Vec<&Contract> {
        self.posted_by_destination
            .get(location)
            .map(|ids| {
                ids.iter()
                    .filter_map(|i| self.contracts.get(i))
                    .filter(|c| c.status == ContractStatus::Posted)
                    .collect()
            })
            .unwrap_or_default()
    }

    /// Return all posted contracts. Used by ship planner to find any available.
    pub fn posted(&self) -> Vec<&Contract> {
        self.by_status
            .get(&ContractStatus::Posted)
            .map(|ids| ids.iter().filter_map(|i| self.contracts.get(i)).collect())
            .unwrap_or_default()
    }

    /// Mark a contract Accepted.
    pub fn accept(&mut self, contract_id: &str, fulfiller_id: String, tick: u64) -> bool {
        let c = match self.contracts.get_mut(contract_id) {
            Some(c) if c.status == ContractStatus::Posted => c,
            _ => return false,
        };
        c.status = ContractStatus::Accepted;
        c.fulfiller_id = Some(fulfiller_id);
        c.accepted_at_tick = Some(tick);
        self.reindex_status(contract_id, ContractStatus::Posted, ContractStatus::Accepted);
        true
    }

    pub fn mark_picked_up(&mut self, contract_id: &str) -> bool {
        let c = match self.contracts.get_mut(contract_id) {
            Some(c) if c.status == ContractStatus::Accepted => c,
            _ => return false,
        };
        c.status = ContractStatus::PickedUp;
        self.reindex_status(contract_id, ContractStatus::Accepted, ContractStatus::PickedUp);
        true
    }

    pub fn mark_delivered(&mut self, contract_id: &str) -> Option<Contract> {
        // In Phase 8b the BT goes straight from Accepted → Paid (no explicit
        // PickedUp step — Buy is the pickup). Accept either.
        let (old_status, cloned) = {
            let c = self.contracts.get_mut(contract_id)?;
            let old = c.status;
            if old != ContractStatus::Accepted && old != ContractStatus::PickedUp {
                return None;
            }
            c.status = ContractStatus::Paid;
            (old, c.clone())
        };
        self.reindex_status(contract_id, old_status, ContractStatus::Paid);
        Some(cloned)
    }

    /// Remove expired Posted contracts. Returns the count removed.
    pub fn expire(&mut self, tick: u64) -> u32 {
        let mut expired_ids: Vec<String> = Vec::new();
        if let Some(ids) = self.by_status.get(&ContractStatus::Posted) {
            for id in ids {
                if let Some(c) = self.contracts.get(id) {
                    if tick >= c.expires_at_tick {
                        expired_ids.push(id.clone());
                    }
                }
            }
        }
        let n = expired_ids.len() as u32;
        for id in expired_ids {
            if let Some(c) = self.contracts.get_mut(&id) {
                c.status = ContractStatus::Expired;
                let dest = c.destination_location.clone();
                self.reindex_status(&id, ContractStatus::Posted, ContractStatus::Expired);
                // Remove from destination index
                if let Some(list) = self.posted_by_destination.get_mut(&dest) {
                    list.retain(|i| i != &id);
                }
            }
        }
        n
    }

    fn reindex_status(&mut self, id: &str, from: ContractStatus, to: ContractStatus) {
        if let Some(list) = self.by_status.get_mut(&from) {
            list.retain(|i| i != id);
        }
        self.by_status.entry(to).or_default().push(id.to_string());
    }

    pub fn counts_by_status(&self) -> HashMap<ContractStatus, u32> {
        self.by_status
            .iter()
            .map(|(k, v)| (*k, v.len() as u32))
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn post_accept_pickup_deliver_flow() {
        let mut board = ContractBoard::new();
        let id = board.post_delivery(
            "pop-earth".into(),
            Commodity::Food,
            100,
            "belt-outpost".into(),
            "earth-station".into(),
            1500,
            0,
            1000,
        );
        assert_eq!(board.len(), 1);

        let posted_at_earth = board.posted_with_destination("earth-station");
        assert_eq!(posted_at_earth.len(), 1);

        assert!(board.accept(&id, "ship-artemis-7".into(), 50));
        assert_eq!(board.get(&id).unwrap().status, ContractStatus::Accepted);

        assert!(board.mark_picked_up(&id));
        let delivered = board.mark_delivered(&id).unwrap();
        assert_eq!(delivered.payment, 1500);
        assert_eq!(board.get(&id).unwrap().status, ContractStatus::Paid);
    }

    #[test]
    fn expire_removes_stale_posted_contracts() {
        let mut board = ContractBoard::new();
        let _ = board.post_delivery(
            "pop-a".into(),
            Commodity::Food,
            10,
            "a".into(),
            "b".into(),
            100,
            0,
            10,
        );
        assert_eq!(board.posted().len(), 1);
        let n = board.expire(20);
        assert_eq!(n, 1);
        assert_eq!(board.posted().len(), 0);
    }

    #[test]
    fn cannot_accept_already_accepted() {
        let mut board = ContractBoard::new();
        let id = board.post_delivery(
            "p".into(),
            Commodity::Ore,
            1,
            "a".into(),
            "b".into(),
            10,
            0,
            100,
        );
        assert!(board.accept(&id, "ship-1".into(), 1));
        assert!(!board.accept(&id, "ship-2".into(), 2));
    }
}
