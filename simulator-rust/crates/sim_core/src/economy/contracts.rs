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

/// Reputation threshold used when a faction wants to restrict a contract
/// to members only. Any ship needs rep ≥ this with the posting faction.
pub const REP_GATE_FACTION_ONLY: u8 = 70;
/// Threshold for "allied" — crew missions default here.
pub const REP_GATE_ALLIED: u8 = 50;
/// Every this many ticks unaccepted, the contract's `min_reputation`
/// drops by `REP_AGE_OPEN_STEP` (floored at 0). So a fresh subsidy pays
/// faction-members only, and after ~1000 ticks it's public.
pub const REP_AGE_OPEN_INTERVAL_TICKS: u64 = 100;
pub const REP_AGE_OPEN_STEP: u8 = 10;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ContractType {
    /// Deliver commodity from source to destination (requires purchase).
    Delivery,
    /// Zero-deposit delivery — ship doesn't need to buy the cargo first,
    /// the posting facility/pop supplies it. Used for courier runs to
    /// help broke ships climb back out.
    Courier,
    /// Transport passengers from source to destination. `quantity` = head
    /// count; `commodity` is unused (serialized as Food as a placeholder
    /// so existing clients don't choke). On delivery, population at the
    /// destination increases by `quantity` instead of market supply.
    Passenger,
    /// Faction-posted subsidy delivery — high pay, sourced from chronic
    /// shortages in member markets. Board-side identical to Delivery but
    /// Godot UI tags them so the player sees faction intervention.
    Subsidy,
    /// Buy contract — posted by a facility that will pay a ship to source
    /// and deliver a specific commodity. Used by facility restock when
    /// the local market is dry. (Phase 11g admin hook uses this too.)
    Supply,
    /// Crew-mission contract — facility-posted short-duration job for a
    /// ship's crew. `quantity` is duration-ticks; `commodity` unused;
    /// completion grants skill XP. Not yet wired end-to-end.
    CrewMission,
}

impl ContractType {
    /// Short "slug" used for Godot filter chips.
    pub fn as_str(self) -> &'static str {
        match self {
            ContractType::Delivery => "delivery",
            ContractType::Courier => "courier",
            ContractType::Passenger => "passenger",
            ContractType::Subsidy => "subsidy",
            ContractType::Supply => "supply",
            ContractType::CrewMission => "crew_mission",
        }
    }
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
    /// Faction the requestor belongs to. When a ship delivers this
    /// contract, its rep with this faction goes up. Set by the posting
    /// agent from its own `faction_id`; left empty for unowned posts.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub faction_id: Option<String>,
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
    /// For `ContractType::CrewMission` — the mission template category
    /// slug (e.g. "security_detail"). `missions::get(category)` resolves
    /// this back to the required skill + XP on completion. None for
    /// other kinds.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mission_category: Option<String>,
    /// Minimum reputation (0..=100) a ship must have with `faction_id` to
    /// accept this contract. Starts at the post time's value and decays
    /// toward 0 as the contract ages, so subsidised runs age open from
    /// faction-only → allied → public over `REPUTATION_AGE_OPEN_TICKS`.
    /// Contracts with no faction tag always default to 0.
    #[serde(default)]
    pub min_reputation: u8,
    /// The post-time `min_reputation` captured once so `age_open_reputation`
    /// can decay relative to it (rather than from `REP_GATE_FACTION_ONLY`
    /// unconditionally, which would skip the first 2 decay intervals for
    /// `CrewMission` contracts that start at `REP_GATE_ALLIED`).
    #[serde(default)]
    pub initial_min_reputation: u8,
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
        self.post_kind(
            ContractType::Delivery,
            requestor_id,
            commodity,
            quantity,
            source_location,
            destination_location,
            payment,
            posted_at_tick,
            lifespan_ticks,
        )
    }

    /// Post a subsidy contract (a faction-funded delivery). Kept as a
    /// distinct kind so Godot can tag them separately in the ledger.
    /// `faction_id` is stored both as the requestor and as the rep-gate
    /// faction the contract unlocks against.
    #[allow(clippy::too_many_arguments)]
    pub fn post_subsidy(
        &mut self,
        faction_id: String,
        commodity: Commodity,
        quantity: u32,
        source_location: String,
        destination_location: String,
        payment: i64,
        posted_at_tick: u64,
        lifespan_ticks: u64,
    ) -> String {
        let faction_clone = faction_id.clone();
        self.post_kind_with_faction(
            ContractType::Subsidy,
            faction_id,
            Some(faction_clone),
            commodity,
            quantity,
            source_location,
            destination_location,
            payment,
            posted_at_tick,
            lifespan_ticks,
        )
    }

    /// Post a passenger-transport contract. `quantity` is head count;
    /// `commodity` is a placeholder (Food) that no handler actually
    /// consumes.
    #[allow(clippy::too_many_arguments)]
    pub fn post_passenger(
        &mut self,
        requestor_id: String,
        head_count: u32,
        source_location: String,
        destination_location: String,
        payment: i64,
        posted_at_tick: u64,
        lifespan_ticks: u64,
    ) -> String {
        self.post_kind(
            ContractType::Passenger,
            requestor_id,
            Commodity::Food, // placeholder; apply phase branches on kind
            head_count,
            source_location,
            destination_location,
            payment,
            posted_at_tick,
            lifespan_ticks,
        )
    }

    /// Post a crew-mission contract. `quantity` is repurposed as the
    /// mission category index hash — actual category/skill lookup uses
    /// `missions::get(&c.requestor_id)` where `requestor_id` carries the
    /// category slug (we overload the field because there's no room for
    /// an extra column without breaking the snapshot schema).
    ///
    /// Apply phase on `DeliverContract` with `ContractType::CrewMission`
    /// reads `quantity` as duration-ticks, pays `payment`, and grants
    /// skill XP to the ship's crew based on the mission's `required_skill`.
    #[allow(clippy::too_many_arguments)]
    pub fn post_crew_mission(
        &mut self,
        requestor_id: String,
        mission_category: String,
        duration_ticks: u32,
        source_and_destination: String,
        payment: i64,
        faction_id: Option<String>,
        posted_at_tick: u64,
        lifespan_ticks: u64,
    ) -> String {
        // For crew missions the contract destination == source (the station
        // posting it). We stash the mission category in the `commodity`
        // placeholder slot by not serializing it separately; instead we
        // write the category into a dedicated field via post_kind_with_faction.
        let id = self.post_kind_with_faction(
            ContractType::CrewMission,
            requestor_id,
            faction_id,
            Commodity::Tools, // placeholder; apply phase doesn't touch supply
            duration_ticks,
            source_and_destination.clone(),
            source_and_destination,
            payment,
            posted_at_tick,
            lifespan_ticks,
        );
        if let Some(c) = self.contracts.get_mut(&id) {
            c.mission_category = Some(mission_category);
        }
        id
    }

    /// Post a courier contract — zero-deposit variant for broke ships.
    #[allow(clippy::too_many_arguments)]
    pub fn post_courier(
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
        self.post_kind(
            ContractType::Courier,
            requestor_id,
            commodity,
            quantity,
            source_location,
            destination_location,
            payment,
            posted_at_tick,
            lifespan_ticks,
        )
    }

    #[allow(clippy::too_many_arguments)]
    fn post_kind(
        &mut self,
        contract_type: ContractType,
        requestor_id: String,
        commodity: Commodity,
        quantity: u32,
        source_location: String,
        destination_location: String,
        payment: i64,
        posted_at_tick: u64,
        lifespan_ticks: u64,
    ) -> String {
        self.post_kind_with_faction(
            contract_type,
            requestor_id,
            None,
            commodity,
            quantity,
            source_location,
            destination_location,
            payment,
            posted_at_tick,
            lifespan_ticks,
        )
    }

    /// Variant that tags the contract with the posting agent's faction.
    /// The apply phase uses this to route reputation bumps on delivery.
    #[allow(clippy::too_many_arguments)]
    pub fn post_kind_with_faction(
        &mut self,
        contract_type: ContractType,
        requestor_id: String,
        faction_id: Option<String>,
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
        // Initial min_reputation depends on kind:
        //   - Subsidy / CrewMission: faction-only at post (high bar)
        //   - Delivery / Courier / Passenger / Supply: public from the jump
        // Subsidies "age open" — see `age_open_reputation` below.
        let min_reputation: u8 = match contract_type {
            ContractType::Subsidy => REP_GATE_FACTION_ONLY,
            ContractType::CrewMission => REP_GATE_ALLIED,
            _ => 0,
        };
        let contract = Contract {
            id: id.clone(),
            contract_type,
            status: ContractStatus::Posted,
            requestor_id,
            faction_id,
            fulfiller_id: None,
            commodity,
            quantity,
            source_location: source_location.clone(),
            destination_location: destination_location.clone(),
            payment,
            posted_at_tick,
            accepted_at_tick: None,
            expires_at_tick: posted_at_tick + lifespan_ticks,
            mission_category: None,
            min_reputation,
            initial_min_reputation: min_reputation,
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

    /// Return posted contracts the given ship can accept given its
    /// per-faction reputation. Ships without a matching rep entry are
    /// treated as rep-0 with that faction (strangers). Contracts with no
    /// faction tag are always eligible.
    pub fn posted_for_ship(
        &self,
        ship_reputation: &HashMap<String, u8>,
    ) -> Vec<&Contract> {
        self.posted()
            .into_iter()
            .filter(|c| {
                match c.faction_id.as_deref() {
                    None => true,
                    Some(fac) => {
                        let rep = ship_reputation.get(fac).copied().unwrap_or(0);
                        rep >= c.min_reputation
                    }
                }
            })
            .collect()
    }

    /// Age-open pass — decay `min_reputation` on long-posted contracts so
    /// subsidised runs and crew missions that no high-rep ship picked up
    /// eventually become public. Call this on the same cadence as
    /// `expire` (once per tick in the pop tick). Cheap: scans Posted
    /// list only.
    ///
    /// Decay is measured from the contract's ORIGINAL `min_reputation`
    /// (captured once in `initial_min_reputation`), not the faction-only
    /// constant — without this, CrewMissions (which start at REP_GATE_ALLIED
    /// = 50) wouldn't decay at all for the first 2 intervals because
    /// `70 - 2*10 = 50` isn't strictly less than 50.
    pub fn age_open_reputation(&mut self, tick: u64) {
        let ids: Vec<String> = self
            .by_status
            .get(&ContractStatus::Posted)
            .cloned()
            .unwrap_or_default();
        for id in ids {
            if let Some(c) = self.contracts.get_mut(&id) {
                if c.min_reputation == 0 {
                    continue;
                }
                let age = tick.saturating_sub(c.posted_at_tick);
                if age == 0 {
                    continue;
                }
                let steps = age / REP_AGE_OPEN_INTERVAL_TICKS;
                let expected = c
                    .initial_min_reputation
                    .saturating_sub((steps as u8).saturating_mul(REP_AGE_OPEN_STEP));
                // We only ratchet down — never raise back above post-time value.
                if expected < c.min_reputation {
                    c.min_reputation = expected;
                }
            }
        }
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

    #[test]
    fn subsidy_starts_faction_only_and_ages_open() {
        let mut board = ContractBoard::new();
        let _ = board.post_subsidy(
            "terran-authority".into(),
            Commodity::Food,
            200,
            "belt".into(),
            "earth".into(),
            5000,
            0,
            10_000,
        );
        let fresh = board.posted().into_iter().next().unwrap();
        assert_eq!(fresh.min_reputation, REP_GATE_FACTION_ONLY);

        // Ship with 0 rep gets filtered out.
        let no_rep: HashMap<String, u8> = HashMap::new();
        assert!(board.posted_for_ship(&no_rep).is_empty());

        // Ship with 70+ rep can accept right away.
        let mut member_rep: HashMap<String, u8> = HashMap::new();
        member_rep.insert("terran-authority".into(), 75);
        assert_eq!(board.posted_for_ship(&member_rep).len(), 1);

        // Wait 1000 ticks — rep gate drops to 70 - 10×10 = 0; public.
        board.age_open_reputation(1000);
        let aged = board.posted().into_iter().next().unwrap();
        assert_eq!(aged.min_reputation, 0);
        assert_eq!(board.posted_for_ship(&no_rep).len(), 1);
    }

    #[test]
    fn crew_mission_defaults_to_allied_gate() {
        let mut board = ContractBoard::new();
        let _ = board.post_crew_mission(
            "facility-earth-station".into(),
            "security_detail".into(),
            30,
            "earth-station".into(),
            1500,
            Some("terran-authority".into()),
            0,
            5_000,
        );
        let c = board.posted().into_iter().next().unwrap();
        assert_eq!(c.min_reputation, REP_GATE_ALLIED);
        assert_eq!(c.mission_category.as_deref(), Some("security_detail"));
    }

    #[test]
    fn posted_for_ship_passes_unfactioned_contracts() {
        let mut board = ContractBoard::new();
        let _ = board.post_delivery(
            "pop-x".into(),
            Commodity::Fuel,
            50,
            "a".into(),
            "b".into(),
            500,
            0,
            1000,
        );
        let empty_rep: HashMap<String, u8> = HashMap::new();
        assert_eq!(board.posted_for_ship(&empty_rep).len(), 1);
    }
}
