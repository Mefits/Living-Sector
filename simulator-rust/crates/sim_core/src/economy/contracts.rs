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
use std::collections::{BTreeMap, HashMap};

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

/// Phase 19b: max times a delivery contract can auto-renew before
/// it's allowed to expire permanently. After 3 renewals the payment
/// is +75% over initial and rep gate has dropped by 45 — if no ship
/// wants it at that point, the demand is structurally unreachable
/// (no compatible hull, wrong system, etc.) and we stop re-posting.
pub const CONTRACT_MAX_RENEWALS: u8 = 3;

/// Payment premium per renewal cycle. 0.25 = +25% per cycle: a 2×
/// renewal has +50% payment, a 3× renewal has +75%. Bumps are applied
/// off the most recently posted `payment` so they compound with
/// `age_escalate_payment` if both fire on the same contract.
pub const CONTRACT_RENEWAL_PAYMENT_BUMP: f32 = 0.25;

/// Rep-gate drop per renewal cycle. Subtracted from the CURRENT
/// `min_reputation`, floored at 0. A delivery that starts public
/// (min_rep=0) is already at the floor; a subsidy at 70 drops to 55
/// → 40 → 25 across its renewals.
pub const CONTRACT_RENEWAL_REP_DROP: u8 = 15;

/// Fallback lifespan used by the single-arg `expire()` shim. Ticks
/// counted in mult=1 base ticks — real callers prefer
/// [`sweep_expiring`] with the per-world-speed lifespan.
pub const DEFAULT_EXPIRE_LIFESPAN: u64 = 300;

/// Phase 18j: every this many ticks a contract sits Posted unaccepted,
/// its payment climbs by `PAYMENT_AGE_ESCALATE_STEP_PCT` percent of
/// its original posted payment. Simulates a desperate requestor
/// sweetening the offer until a ship bites — feeds back into the
/// planner's contract scoring so stale-but-lucrative listings
/// eventually out-compete trade_run for ships that see them.
pub const PAYMENT_AGE_ESCALATE_INTERVAL_TICKS: u64 = 50;
/// Percent of `initial_payment` added per escalation step. 5% every
/// 50 ticks = roughly doubles the urgency over a full lifespan.
pub const PAYMENT_AGE_ESCALATE_STEP_PCT: i64 = 5;
/// Cap on total escalation (percent of initial). Prevents runaway
/// multipliers on bugs that leave a contract posted forever.
pub const PAYMENT_AGE_ESCALATE_CAP_PCT: i64 = 100;

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
    /// Phase 19c: construction delivery. Mechanically like a bigger
    /// Delivery — ship buys a commodity at source and delivers it to
    /// destination — but on payout the sim ALSO spawns a new facility
    /// at the destination sized to produce that commodity. Used by the
    /// demand analyzer to self-correct chronic shortages: "Kuiper
    /// Station has had no polymers for 500 ticks → build a polymer
    /// refinery there." Rep treatment + fill-ratio scoring match
    /// Delivery; the only post-delivery difference is the spawn.
    Construction,
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
            ContractType::Construction => "construction",
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
    /// Payment at post time. Captured once so
    /// [`ContractBoard::age_escalate_payment`] can bump `payment`
    /// by a percentage of the original rather than compounding off
    /// an already-escalated value. Defaults to `payment` on pre-18j
    /// saves.
    #[serde(default)]
    pub initial_payment: i64,
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
    /// Phase 19b: how many times `expire()` has auto-renewed this
    /// contract at escalating price + relaxed rep gate. Caps at
    /// [`CONTRACT_MAX_RENEWALS`] — after that, the contract actually
    /// expires. Not persisted (in-memory only) since it resets cleanly
    /// on restart and the renew math is idempotent from any starting
    /// payment.
    #[serde(default)]
    pub renewal_count: u8,
}

/// Per-contract detail for a renewal that just fired. Returned from
/// [`ContractBoard::sweep_expiring`] so the engine can emit a
/// `contract_renewed` event to the ticker without re-looking-up the
/// contract by id.
#[derive(Debug, Clone)]
pub struct RenewalSummary {
    pub id: String,
    pub commodity: Commodity,
    pub destination: String,
    pub new_payment: i64,
    pub new_min_rep: u8,
    pub renewal_count: u8,
}

/// Per-contract detail for a contract that actually expired this
/// sweep (either non-delivery kind, or delivery that hit its renewal
/// cap). Paired with [`RenewalSummary`] in [`SweepResult`].
#[derive(Debug, Clone)]
pub struct ExpiredSummary {
    pub id: String,
    pub commodity: Commodity,
    pub destination: String,
    pub contract_type: ContractType,
    /// Payment at time of expiry, which for renewed deliveries may be
    /// well above the initial post-time value.
    pub final_payment: i64,
}

/// Result of [`ContractBoard::sweep_expiring`]. Two parallel lists so
/// the caller can emit distinct `contract_renewed` /
/// `contract_expired` event streams.
#[derive(Debug, Default, Clone)]
pub struct SweepResult {
    pub renewed: Vec<RenewalSummary>,
    pub expired: Vec<ExpiredSummary>,
}

/// Result of [`ContractBoard::drop_ship_holdings`] — split so the
/// caller can emit different events for "handed back to the board"
/// vs "cargo was aboard, cancelled permanently."
#[derive(Debug, Default, Clone)]
pub struct DropShipResult {
    /// Accepted contracts flipped back to Posted.
    pub released: Vec<String>,
    /// PickedUp contracts marked Expired — cargo was on the ship.
    pub cancelled: Vec<String>,
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
    /// Bundle (P): faction_id → min_reputation → list of Posted
    /// contract ids. `None` outer key holds all public contracts.
    /// Inner BTreeMap keyed by min_reputation lets
    /// `posted_for_ship` skip whole rep-tier sub-buckets above
    /// the ship's rep instead of filtering per-contract. Maintained
    /// by the post/release/sweep/cancel pipelines alongside
    /// `posted_by_destination`. `age_open_reputation` re-buckets
    /// contracts whose min_reputation ratchets down.
    posted_by_faction: HashMap<Option<String>, BTreeMap<u8, Vec<String>>>,
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

    /// Insert a pre-built contract read from persistence. Fills the
    /// per-status and per-destination indices so the board looks
    /// identical to one populated via `post_*`. Only used by the DB
    /// loader at boot — live tick code still posts via `post_*`.
    ///
    /// `next_id` is bumped past any numeric suffix on the loaded id
    /// (e.g. `"contract-137"` → `next_id >= 138`) so post-boot
    /// posting doesn't collide with hydrated ids.
    pub fn insert_loaded(&mut self, c: Contract) {
        if let Some(suffix) = c.id.strip_prefix("contract-") {
            if let Ok(n) = suffix.parse::<u64>() {
                if n >= self.next_id {
                    self.next_id = n + 1;
                }
            }
        }
        let id = c.id.clone();
        let status = c.status;
        let dest = c.destination_location.clone();
        let faction = c.faction_id.clone();
        let min_rep = c.min_reputation;
        self.contracts.insert(id.clone(), c);
        self.by_status
            .entry(status)
            .or_default()
            .push(id.clone());
        if status == ContractStatus::Posted {
            self.posted_by_destination
                .entry(dest)
                .or_default()
                .push(id.clone());
            self.faction_bucket_add(&id, faction, min_rep);
        }
    }

    /// Post a new delivery contract and return its id.
    #[allow(clippy::too_many_arguments)]
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
        self.post_delivery_for(
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

    /// Post a delivery contract tagged with the requestor's faction.
    /// Phase 19e: without this, facility-owned deliveries had
    /// `faction_id=None` so ships never accrued reputation for
    /// completing them — subsidies and crew missions (which gate on
    /// rep) stayed perpetually unreachable. Pass `Some("terran-
    /// authority")` etc. to grant +1 rep on delivery.
    #[allow(clippy::too_many_arguments)]
    pub fn post_delivery_for(
        &mut self,
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
        self.post_kind_with_faction(
            ContractType::Delivery,
            requestor_id,
            faction_id,
            commodity,
            quantity,
            source_location,
            destination_location,
            payment,
            posted_at_tick,
            lifespan_ticks,
        )
    }

    /// Phase 19c: post a construction delivery. Behaves like a
    /// Delivery on the board but is tagged so the DeliverContract
    /// apply phase knows to spawn a new facility at `destination`
    /// sized to produce `commodity`.
    #[allow(clippy::too_many_arguments)]
    pub fn post_construction(
        &mut self,
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
        self.post_kind_with_faction(
            ContractType::Construction,
            requestor_id,
            faction_id,
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
        let faction_for_index = faction_id.clone();
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
            initial_payment: payment,
            posted_at_tick,
            accepted_at_tick: None,
            expires_at_tick: posted_at_tick + lifespan_ticks,
            mission_category: None,
            min_reputation,
            initial_min_reputation: min_reputation,
            renewal_count: 0,
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
        self.faction_bucket_add(&id, faction_for_index, min_reputation);
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
    ///
    /// Bundle (P) + rep-tier: iterate `posted_by_faction`
    /// (faction → BTreeMap<min_rep, ids>) and for each faction
    /// walk only the rep-tier sub-buckets the ship qualifies
    /// for (`BTreeMap::range(..=ship_rep)`). A ship with rep=0
    /// in a faction touches only that faction's min_rep=0 tier;
    /// a ship with rep=65 touches tiers {0, 50} but skips the
    /// 70-tier entirely. At 150 contracts across 3 tiers per
    /// faction, low-rep ships typically see 30-50 contracts
    /// instead of 150.
    pub fn posted_for_ship(
        &self,
        ship_reputation: &HashMap<String, u8>,
    ) -> Vec<&Contract> {
        let mut out: Vec<&Contract> = Vec::new();
        for (fac_opt, tiers) in self.posted_by_faction.iter() {
            let ship_rep: u8 = match fac_opt {
                None => 0,
                Some(fac) => ship_reputation.get(fac).copied().unwrap_or(0),
            };
            // BTreeMap::range(..=ship_rep) yields only tiers the
            // ship qualifies for — higher tiers are skipped
            // entirely without touching their contract ids.
            for (_min_rep, ids) in tiers.range(..=ship_rep) {
                for id in ids {
                    if let Some(c) = self.contracts.get(id) {
                        if c.status == ContractStatus::Posted {
                            out.push(c);
                        }
                    }
                }
            }
        }
        out
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
        // Collect re-bucket work first so we can release the
        // `contracts.get_mut` borrow before touching the index.
        let mut rebucket: Vec<(String, Option<String>, u8, u8)> = Vec::new();
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
                    let old_tier = c.min_reputation;
                    c.min_reputation = expected;
                    // Rep-tier sub-bucketing (Bundle P extension):
                    // when the tier changes we have to move the
                    // contract id from its old rep-tier sub-bucket
                    // to its new one. Defer the index update until
                    // after the mutable borrow drops.
                    rebucket.push((id.clone(), c.faction_id.clone(), old_tier, expected));
                }
            }
        }
        // Apply deferred re-bucket moves now that `contracts.get_mut`
        // borrows are released.
        for (id, fac, old_tier, new_tier) in rebucket {
            if let Some(tiers) = self.posted_by_faction.get_mut(&fac) {
                if let Some(old_list) = tiers.get_mut(&old_tier) {
                    old_list.retain(|i| i != &id);
                }
                tiers.retain(|_, ids| !ids.is_empty());
            }
            self.faction_bucket_add(&id, fac, new_tier);
        }
    }

    /// Phase 18j — escalate payment on long-posted unaccepted contracts.
    /// For every `PAYMENT_AGE_ESCALATE_INTERVAL_TICKS` a contract has
    /// sat in `Posted` state, its `payment` rises by
    /// `PAYMENT_AGE_ESCALATE_STEP_PCT`% of its `initial_payment`,
    /// capped at `PAYMENT_AGE_ESCALATE_CAP_PCT`%. Idempotent — we
    /// always recompute `payment` from the initial + current age,
    /// never compound the current value. Call on the same cadence
    /// as `age_open_reputation` + `expire`.
    pub fn age_escalate_payment(&mut self, tick: u64) {
        let ids: Vec<String> = self
            .by_status
            .get(&ContractStatus::Posted)
            .cloned()
            .unwrap_or_default();
        for id in ids {
            if let Some(c) = self.contracts.get_mut(&id) {
                if c.initial_payment <= 0 {
                    continue;
                }
                let age = tick.saturating_sub(c.posted_at_tick);
                let steps = age / PAYMENT_AGE_ESCALATE_INTERVAL_TICKS;
                let pct = (steps as i64 * PAYMENT_AGE_ESCALATE_STEP_PCT)
                    .min(PAYMENT_AGE_ESCALATE_CAP_PCT);
                // payment = initial × (1 + pct/100). Monotonic non-decreasing.
                let bumped = c.initial_payment + (c.initial_payment * pct / 100);
                if bumped > c.payment {
                    c.payment = bumped;
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

    /// Move an Accepted contract back to Posted so another ship can
    /// pick it up. Called when a ship's BT fails before delivery
    /// while it still holds the contract — without this the contract
    /// sits Accepted forever (no-one else can claim it) and the ship
    /// itself is stuck too.
    ///
    /// Guarded on `fulfiller_id == expected_fulfiller` so a losing
    /// speculative-accept can't yank a contract out from under the
    /// ship that actually won the race. Pass `None` to skip the
    /// guard (admin / bulk cleanup).
    ///
    /// Returns true if the release happened. False means the contract
    /// doesn't exist, isn't Accepted, or the fulfiller guard didn't
    /// match.
    pub fn release(&mut self, contract_id: &str, expected_fulfiller: Option<&str>) -> bool {
        // Mutate + collect what we need for the indexes in a single
        // scoped borrow, then drop `c` so `self` is free for the
        // reindex + posted-by-destination calls below.
        let (dest, fac, min_rep) = {
            let c = match self.contracts.get_mut(contract_id) {
                Some(c) if c.status == ContractStatus::Accepted => c,
                _ => return false,
            };
            if let Some(expected) = expected_fulfiller {
                let matches = c.fulfiller_id.as_deref() == Some(expected);
                if !matches {
                    return false;
                }
            }
            c.status = ContractStatus::Posted;
            c.fulfiller_id = None;
            c.accepted_at_tick = None;
            (
                c.destination_location.clone(),
                c.faction_id.clone(),
                c.min_reputation,
            )
        };
        self.reindex_status(contract_id, ContractStatus::Accepted, ContractStatus::Posted);
        // Re-add to the posted indexes so the contract is visible
        // to planners again.
        let id = contract_id.to_string();
        let entry = self.posted_by_destination.entry(dest).or_default();
        if !entry.contains(&id) {
            entry.push(id.clone());
        }
        self.faction_bucket_add(&id, fac, min_rep);
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

    /// Sweep Posted contracts past their `expires_at_tick`. Phase 19b:
    /// delivery contracts get up to [`CONTRACT_MAX_RENEWALS`] auto-
    /// renewals before permanently expiring. Courier / Subsidy /
    /// CrewMission / Passenger / Supply expire directly — they carry
    /// their own aging mechanics (e.g. passengers depend on live
    /// population sentiment, which re-posts organically).
    ///
    /// Returns a [`SweepResult`] with per-contract details so callers
    /// can emit events / telemetry. The counts version is still
    /// available via [`sweep_expiring_counts`] if you only need those.
    pub fn sweep_expiring(&mut self, tick: u64, lifespan_ticks: u64) -> SweepResult {
        let mut due: Vec<String> = Vec::new();
        if let Some(ids) = self.by_status.get(&ContractStatus::Posted) {
            for id in ids {
                if let Some(c) = self.contracts.get(id) {
                    if tick >= c.expires_at_tick {
                        due.push(id.clone());
                    }
                }
            }
        }

        let mut result = SweepResult::default();
        for id in due {
            // Per-kind renewal policy:
            //   Delivery / Construction: up to CONTRACT_MAX_RENEWALS
            //     renewals, each bumping payment + dropping rep by a
            //     fixed step.
            //   Subsidy: one renewal, and it slams rep to 0 — the
            //     faction tried to keep it in-house first; if no
            //     loyal ship picked up, they open it to anyone who's
            //     willing to cross a gate (Phase 19-tail "desperate
            //     bounty" behaviour).
            //   Everything else (Courier / Passenger / CrewMission /
            //     Supply): not renewed.
            let (should_renew, is_subsidy_retry) = match self.contracts.get(&id) {
                Some(c) => match c.contract_type {
                    ContractType::Delivery | ContractType::Construction => {
                        (c.renewal_count < CONTRACT_MAX_RENEWALS, false)
                    }
                    ContractType::Subsidy => (c.renewal_count < 1, true),
                    _ => (false, false),
                },
                None => (false, false),
            };
            if should_renew {
                let (commodity, destination, new_payment, new_min_rep, new_count) =
                    if let Some(c) = self.contracts.get_mut(&id) {
                        let bump = CONTRACT_RENEWAL_PAYMENT_BUMP;
                        c.payment = ((c.payment as f32) * (1.0 + bump)).round() as i64;
                        // Subsidies: one renewal drops rep straight to 0
                        // so anyone can accept. Others: fixed step.
                        if is_subsidy_retry {
                            c.min_reputation = 0;
                        } else {
                            c.min_reputation = c
                                .min_reputation
                                .saturating_sub(CONTRACT_RENEWAL_REP_DROP);
                        }
                        c.expires_at_tick = tick + lifespan_ticks;
                        c.renewal_count = c.renewal_count.saturating_add(1);
                        (
                            c.commodity,
                            c.destination_location.clone(),
                            c.payment,
                            c.min_reputation,
                            c.renewal_count,
                        )
                    } else {
                        continue;
                    };
                result.renewed.push(RenewalSummary {
                    id: id.clone(),
                    commodity,
                    destination,
                    new_payment,
                    new_min_rep,
                    renewal_count: new_count,
                });
                // Stays in Posted — no reindex needed.
            } else if let Some(c) = self.contracts.get_mut(&id) {
                let summary = ExpiredSummary {
                    id: id.clone(),
                    commodity: c.commodity,
                    destination: c.destination_location.clone(),
                    contract_type: c.contract_type,
                    final_payment: c.payment,
                };
                c.status = ContractStatus::Expired;
                let dest = c.destination_location.clone();
                let fac = c.faction_id.clone();
                self.reindex_status(&id, ContractStatus::Posted, ContractStatus::Expired);
                if let Some(list) = self.posted_by_destination.get_mut(&dest) {
                    list.retain(|i| i != &id);
                }
                self.faction_bucket_remove(&id, &fac);
                result.expired.push(summary);
            }
        }
        result
    }

    /// Count-only variant for tests / callers that don't need the
    /// per-contract details. Wraps [`sweep_expiring`] and discards
    /// everything except the lengths.
    pub fn sweep_expiring_counts(&mut self, tick: u64, lifespan_ticks: u64) -> (u32, u32) {
        let r = self.sweep_expiring(tick, lifespan_ticks);
        (r.renewed.len() as u32, r.expired.len() as u32)
    }

    /// Legacy shim for callers that still want a single "N contracts
    /// expired" count and don't need the renewal split. Uses
    /// [`DEFAULT_EXPIRE_LIFESPAN`] for the re-posted lifespan.
    pub fn expire(&mut self, tick: u64) -> u32 {
        self.sweep_expiring_counts(tick, DEFAULT_EXPIRE_LIFESPAN).1
    }

    /// Admin cleanup: release every Accepted contract held by a specific
    /// fulfiller back to Posted, and mark any PickedUp ones Expired
    /// (cargo was aboard the ship — if the ship is gone, the cargo is
    /// too, so the contract can't be salvaged). Returns the cancelled
    /// + released contract ids so the caller can emit events.
    ///
    /// Designed for the admin-destroy-ship path: without this, a
    /// deleted ship leaves its Accepted contract permanently
    /// unfulfillable — the contract's fulfiller_id points at a
    /// despawned entity and `release()`'s fulfiller guard rejects
    /// every other ship.
    pub fn drop_ship_holdings(&mut self, ship_id: &str) -> DropShipResult {
        let mut out = DropShipResult::default();
        let ids: Vec<String> = self
            .contracts
            .iter()
            .filter_map(|(id, c)| {
                if c.fulfiller_id.as_deref() == Some(ship_id) {
                    Some(id.clone())
                } else {
                    None
                }
            })
            .collect();
        for id in ids {
            let (status, dest, fac, min_rep) = match self.contracts.get(&id) {
                Some(c) => (
                    c.status,
                    c.destination_location.clone(),
                    c.faction_id.clone(),
                    c.min_reputation,
                ),
                None => continue,
            };
            match status {
                ContractStatus::Accepted => {
                    // Hand back to the board — another ship can pick up.
                    if let Some(c) = self.contracts.get_mut(&id) {
                        c.status = ContractStatus::Posted;
                        c.fulfiller_id = None;
                        c.accepted_at_tick = None;
                    }
                    self.reindex_status(&id, ContractStatus::Accepted, ContractStatus::Posted);
                    let entry = self.posted_by_destination.entry(dest).or_default();
                    if !entry.contains(&id) {
                        entry.push(id.clone());
                    }
                    self.faction_bucket_add(&id, fac, min_rep);
                    out.released.push(id);
                }
                ContractStatus::PickedUp => {
                    // Cargo is gone with the ship — can't re-post.
                    if let Some(c) = self.contracts.get_mut(&id) {
                        c.status = ContractStatus::Expired;
                    }
                    self.reindex_status(&id, ContractStatus::PickedUp, ContractStatus::Expired);
                    out.cancelled.push(id);
                }
                _ => {
                    // Paid / Expired / Posted-with-stale-fulfiller: no action.
                    // (Posted shouldn't happen — Posted has no fulfiller — but defensive.)
                }
            }
        }
        out
    }

    /// Admin cleanup: mark every non-finalised contract connected to a
    /// facility as Expired. A "connection" means the facility is the
    /// requestor, the source_location, or the destination_location.
    /// The caller is responsible for deciding whether any of those
    /// apply — for source/destination, usually only call if the
    /// deleted facility was the last one at its location (otherwise
    /// remaining facilities can still service the contract).
    ///
    /// Paid + Expired contracts are skipped — their lifecycle is done,
    /// purging history would hide it from the audit trail.
    pub fn cancel_for_facility(
        &mut self,
        requestor_id: Option<&str>,
        source_location: Option<&str>,
        destination_location: Option<&str>,
    ) -> Vec<String> {
        let mut cancelled: Vec<String> = Vec::new();
        let ids: Vec<String> = self
            .contracts
            .iter()
            .filter_map(|(id, c)| {
                if matches!(c.status, ContractStatus::Paid | ContractStatus::Expired) {
                    return None;
                }
                let hit_requestor = requestor_id
                    .map(|r| c.requestor_id == r)
                    .unwrap_or(false);
                let hit_source = source_location
                    .map(|s| c.source_location == s)
                    .unwrap_or(false);
                let hit_dest = destination_location
                    .map(|d| c.destination_location == d)
                    .unwrap_or(false);
                if hit_requestor || hit_source || hit_dest {
                    Some(id.clone())
                } else {
                    None
                }
            })
            .collect();
        for id in ids {
            let (old_status, dest, fac) = match self.contracts.get(&id) {
                Some(c) => (
                    c.status,
                    c.destination_location.clone(),
                    c.faction_id.clone(),
                ),
                None => continue,
            };
            if let Some(c) = self.contracts.get_mut(&id) {
                c.status = ContractStatus::Expired;
            }
            self.reindex_status(&id, old_status, ContractStatus::Expired);
            if old_status == ContractStatus::Posted {
                if let Some(list) = self.posted_by_destination.get_mut(&dest) {
                    list.retain(|i| i != &id);
                }
                self.faction_bucket_remove(&id, &fac);
            }
            cancelled.push(id);
        }
        cancelled
    }

    /// Add a contract id to the faction bucket indexed by its
    /// current `min_reputation`. Safe to call when the id is
    /// already present — becomes a no-op via the `contains`
    /// check, same pattern as `posted_by_destination` elsewhere.
    fn faction_bucket_add(&mut self, id: &str, faction: Option<String>, min_rep: u8) {
        let tier = self
            .posted_by_faction
            .entry(faction)
            .or_default()
            .entry(min_rep)
            .or_default();
        let id_string = id.to_string();
        if !tier.contains(&id_string) {
            tier.push(id_string);
        }
    }

    /// Remove a contract id from whatever faction + rep-tier bucket
    /// currently holds it. Walks the tier map for the faction
    /// (typically 1-3 tiers) and retains all other ids. Cleans
    /// up empty tier entries but keeps the outer faction entry
    /// (insertion cost is negligible vs re-creation churn).
    fn faction_bucket_remove(&mut self, id: &str, faction: &Option<String>) {
        if let Some(tiers) = self.posted_by_faction.get_mut(faction) {
            tiers.retain(|_tier, ids| {
                ids.retain(|i| i != id);
                !ids.is_empty()
            });
        }
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
    fn expire_renews_delivery_contracts_before_expiring() {
        // Phase 19b: delivery contracts get up to CONTRACT_MAX_RENEWALS
        // auto-renewals (escalating payment + relaxed rep gate) before
        // actually expiring. First 3 calls re-post; 4th moves to
        // Expired.
        let mut board = ContractBoard::new();
        let id = board.post_delivery(
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

        // 1st expire → renewed. Payment +25%, still Posted.
        let r = board.sweep_expiring(20, 10);
        assert_eq!((r.renewed.len(), r.expired.len()), (1, 0));
        let c = board.get(&id).unwrap();
        assert_eq!(c.status, ContractStatus::Posted);
        assert_eq!(c.payment, 125); // 100 * 1.25
        assert_eq!(c.renewal_count, 1);

        // 2nd and 3rd expire → renewed. Payment compounds.
        let r = board.sweep_expiring(40, 10);
        assert_eq!(r.renewed.len(), 1);
        let r = board.sweep_expiring(60, 10);
        assert_eq!(r.renewed.len(), 1);
        let c = board.get(&id).unwrap();
        assert_eq!(c.renewal_count, CONTRACT_MAX_RENEWALS);
        // 100 -> 125 -> 156 -> 195 (round() each step)
        assert!(c.payment > 150 && c.payment < 200);

        // 4th expire → actually expires (renewal_count hit cap).
        let r = board.sweep_expiring(80, 10);
        assert_eq!((r.renewed.len(), r.expired.len()), (0, 1));
        assert_eq!(board.get(&id).unwrap().status, ContractStatus::Expired);
        assert_eq!(board.posted().len(), 0);
    }

    #[test]
    fn expire_shim_still_returns_expired_count() {
        // Non-delivery contracts expire immediately — the legacy
        // `expire()` shim still returns just the expired count and
        // matches pre-19b behavior for Subsidy / Passenger / etc.
        let mut board = ContractBoard::new();
        let _ = board.post_passenger(
            "pop-a".into(),
            5,
            "a".into(),
            "b".into(),
            200,
            0,
            10,
        );
        assert_eq!(board.posted().len(), 1);
        let n = board.expire(20);
        assert_eq!(n, 1);
        assert_eq!(board.posted().len(), 0);
    }

    #[test]
    fn posted_for_ship_skips_tiers_above_rep() {
        // Bundle (P) rep-tier: a ship with rep=40 in a faction
        // should see the faction's min_rep=0 contracts but NOT
        // its min_rep=50 (allied) or min_rep=70 (faction-only).
        let mut board = ContractBoard::new();
        // Public-tier contract for the faction (post normal delivery).
        board.post_kind_with_faction(
            ContractType::Delivery,
            "fac-a".into(),
            Some("terran-authority".into()),
            Commodity::Food,
            50,
            "a".into(),
            "b".into(),
            1000,
            0,
            100,
        );
        // Allied-tier (crew mission, min_rep=50 by post rules).
        board.post_kind_with_faction(
            ContractType::CrewMission,
            "fac-a".into(),
            Some("terran-authority".into()),
            Commodity::Food,
            0,
            "a".into(),
            "a".into(),
            2000,
            0,
            100,
        );
        // Faction-only (subsidy, min_rep=70).
        board.post_kind_with_faction(
            ContractType::Subsidy,
            "fac-a".into(),
            Some("terran-authority".into()),
            Commodity::Food,
            50,
            "a".into(),
            "b".into(),
            3000,
            0,
            100,
        );

        // Ship with rep=40 sees only the delivery.
        let mut low_rep = HashMap::new();
        low_rep.insert("terran-authority".into(), 40u8);
        let visible = board.posted_for_ship(&low_rep);
        assert_eq!(
            visible.len(),
            1,
            "rep=40 ship should see only min_rep=0 delivery: {:?}",
            visible.iter().map(|c| (c.contract_type, c.min_reputation)).collect::<Vec<_>>(),
        );

        // Ship with rep=65 sees delivery + crew_mission.
        let mut mid_rep = HashMap::new();
        mid_rep.insert("terran-authority".into(), 65u8);
        assert_eq!(board.posted_for_ship(&mid_rep).len(), 2);

        // Ship with rep=80 sees all three.
        let mut high_rep = HashMap::new();
        high_rep.insert("terran-authority".into(), 80u8);
        assert_eq!(board.posted_for_ship(&high_rep).len(), 3);
    }

    #[test]
    fn age_open_rebuckets_contract_on_tier_decrease() {
        // Post a subsidy (starts at min_rep=70). Age enough ticks
        // that it decays to min_rep=40. A ship with rep=45 in the
        // faction should now see it via the 40-tier sub-bucket.
        let mut board = ContractBoard::new();
        let id = board.post_kind_with_faction(
            ContractType::Subsidy,
            "fac-a".into(),
            Some("terran-authority".into()),
            Commodity::Food,
            10,
            "a".into(),
            "b".into(),
            5000,
            0,       // posted_at_tick
            10000,   // long lifespan
        );
        assert_eq!(board.get(&id).unwrap().min_reputation, 70);

        // Advance age so the ratchet drops several steps.
        // REP_AGE_OPEN_INTERVAL_TICKS=100, REP_AGE_OPEN_STEP=10 →
        // after 300 ticks, expected min_rep = 70 - 3*10 = 40.
        board.age_open_reputation(300);
        assert_eq!(board.get(&id).unwrap().min_reputation, 40);

        // Ship with rep=45 should now see this via the 40-tier.
        let mut rep = HashMap::new();
        rep.insert("terran-authority".into(), 45u8);
        let visible = board.posted_for_ship(&rep);
        assert_eq!(visible.len(), 1, "aged-down subsidy must be visible after re-bucket");
        assert_eq!(visible[0].id, id);
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

    #[test]
    fn age_escalate_payment_bumps_stale_contracts() {
        let mut board = ContractBoard::new();
        let _ = board.post_delivery(
            "pop-x".into(),
            Commodity::Food,
            50,
            "source".into(),
            "dest".into(),
            1000, // initial payment
            0,    // posted at tick 0
            10_000,
        );
        let fresh = board.posted().into_iter().next().unwrap();
        assert_eq!(fresh.payment, 1000);
        assert_eq!(fresh.initial_payment, 1000);

        // After 50 ticks (1 escalation step): +5% → 1050.
        board.age_escalate_payment(50);
        let t50 = board.posted().into_iter().next().unwrap();
        assert_eq!(t50.payment, 1050);

        // After 500 ticks (10 steps): +50% → 1500.
        board.age_escalate_payment(500);
        let t500 = board.posted().into_iter().next().unwrap();
        assert_eq!(t500.payment, 1500);

        // After 5000 ticks: capped at PAYMENT_AGE_ESCALATE_CAP_PCT = 100%,
        // so payment = initial × 2 = 2000, not runaway.
        board.age_escalate_payment(5000);
        let tcap = board.posted().into_iter().next().unwrap();
        assert_eq!(tcap.payment, 2000);
    }

    #[test]
    fn age_escalate_payment_is_idempotent() {
        let mut board = ContractBoard::new();
        let _ = board.post_delivery(
            "pop-x".into(),
            Commodity::Food,
            50,
            "source".into(),
            "dest".into(),
            1000,
            0,
            10_000,
        );
        // Running the escalator multiple times at the same tick
        // must not compound. Re-derives payment from initial × pct.
        board.age_escalate_payment(500);
        board.age_escalate_payment(500);
        board.age_escalate_payment(500);
        let c = board.posted().into_iter().next().unwrap();
        assert_eq!(c.payment, 1500);
    }

    #[test]
    fn age_escalate_payment_skips_non_posted_contracts() {
        let mut board = ContractBoard::new();
        let id = board.post_delivery(
            "pop-x".into(),
            Commodity::Food,
            50,
            "source".into(),
            "dest".into(),
            1000,
            0,
            10_000,
        );
        board.accept(&id, "ship-test".into(), 10);
        // Once accepted, escalation shouldn't touch payment —
        // the ship already committed at the accepted rate.
        board.age_escalate_payment(500);
        let c = board.get(&id).unwrap();
        assert_eq!(c.payment, 1000);
    }
}
