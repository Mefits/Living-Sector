use crate::economy::{commodities::Commodity, order_book::Order};
use hecs::Entity;

/// Unified command buffer for all cross-phase effects.
///
/// Each tick phase reads world state, writes commands here, and NEVER mutates
/// the world mid-phase. The next phase drains and applies commands. This gives
/// us deterministic replay (record + replay the command log), no write
/// conflicts during parallel queries, and a clean audit trail for debugging.
#[derive(Debug, Clone)]
pub enum SimCommand {
    // --- Market interactions ---
    /// Ship places a buy order on a market.
    PlaceBuyOrder { ship: Entity, market: Entity, order: Order },
    /// Ship places a sell order on a market.
    PlaceSellOrder { ship: Entity, market: Entity, order: Order },
    /// Apply a trade execution: transfer cargo and credits.
    ExecuteTrade {
        buyer: Entity,
        seller: Entity,
        commodity: Commodity,
        quantity: u32,
        total_cost: i64,
    },

    // --- Docking / transit ---
    DockShip { ship: Entity, facility: Entity },
    UndockShip { ship: Entity },
    BeginTransit {
        ship: Entity,
        from: String,
        to: String,
        departure_tick: u64,
        arrival_tick: u64,
    },
    ArriveAtLocation { ship: Entity, location: String },

    // --- Dock-dwell interactions (Phase 11a) ---
    /// Ship requests to dock at its current location's primary facility.
    /// Apply phase finds the facility, checks capacity, deducts the docking
    /// fee (base × occupancy × condition), appends the ship entity to the
    /// facility's `docked_ships`, and sets `position.docked_at` on the ship.
    /// If the facility is full or charges more than the ship can pay, the
    /// request is silently dropped — the ship's BT continues (subsequent
    /// refuel/unload will fail softly if the facility can't service them).
    RequestDock {
        ship: Entity,
        facility_location: String,
        /// Optional facility-type hint. When set (e.g. `"shipyard"` for
        /// agent-driven retrofit), the apply phase picks the largest
        /// facility of that type at `facility_location`. Falls back to
        /// the usual primary facility when `None` (every existing
        /// call site) or when no facility of that type is present.
        preferred_facility_type: Option<&'static str>,
    },
    /// Ship leaves dock. Apply phase removes the ship from the facility's
    /// `docked_ships` list. Used in apply phase only; the ship clears its
    /// own `docked_at` in-place before emitting this.
    ReleaseDock {
        ship: Entity,
        facility_location: String,
    },
    /// Ship is pulling fuel from a facility's reserves. Apply phase
    /// decrements `reserves[Fuel]` (min 0) and credits the facility's
    /// `credits` by `payment`. The ship already adjusted its own fuel and
    /// credits when emitting — this command is the cross-entity half.
    FacilityRefuel {
        ship: Entity,
        facility_location: String,
        amount: f32,
        payment: i64,
    },
    /// Grant crew XP to a specific skill after a successful trade, delivery,
    /// or completed crew mission. Apply phase bumps `ShipCrewSkills.<skill>`
    /// by `amount`, capped at 100. Unknown skills are a no-op.
    GrantCrewXp {
        ship: Entity,
        skill: &'static str,
        amount: u8,
    },
    /// Ship is jumping through a gate. Apply phase looks up the source
    /// gate at the ship's current location, charges the fee
    /// (`flat + per_cargo × cargo_used`) to the ship + credits the gate
    /// facility, and teleports the ship to `dest_gate_location`. Fails
    /// silently if the ship lacks credits or if no gate is found — the
    /// ship's `GateJump` BT action catches it and returns Failure.
    RequestGateJump {
        ship: Entity,
        src_gate_location: String,
        dest_gate_location: String,
    },

    // --- Contracts ---
    PostContract { contract_id: String },
    /// Ship wants to accept a posted contract. Apply phase sets board status +
    /// fulfiller_id; fails silently if the contract was already taken.
    AcceptContract {
        ship: Entity,
        ship_id: String,
        contract_id: String,
    },
    /// Ship delivered contract cargo at destination. Apply phase:
    /// - marks contract Paid
    /// - credits ship the payment
    /// - decrements ship cargo by contract quantity
    /// - increases destination market supply by contract quantity
    DeliverContract {
        ship: Entity,
        contract_id: String,
    },
    ExpireContract { contract_id: String },
    /// Ship's BT failed before delivery while it still held this
    /// contract. Apply phase moves the contract Accepted → Posted so
    /// another ship can pick it up. Guarded by `ship_id` to prevent
    /// a losing speculative-accept from yanking the winning ship's
    /// contract.
    ReleaseContract {
        ship_id: String,
        contract_id: String,
    },

    // --- Economy transfers ---
    TransferCredits {
        from: Entity,
        to: Entity,
        amount: i64,
    },

    // --- Supply adjustments (facility recipes, population production) ---
    /// Add supply at the market whose location matches the ship's current location.
    /// `market` field is a placeholder — the apply phase resolves the real market
    /// by looking up the ship's location at apply time. Emitted from ship sells.
    AddSupplyAtShipLocation {
        ship: Entity,
        commodity: Commodity,
        quantity: f32,
    },
    /// Symmetric to AddSupplyAtShipLocation — ship buys remove supply locally.
    RemoveSupplyAtShipLocation {
        ship: Entity,
        commodity: Commodity,
        quantity: f32,
    },
    /// Direct supply adjustment at a specific market entity (facility recipes).
    AddSupply {
        market: Entity,
        commodity: Commodity,
        quantity: f32,
    },
    RemoveSupply {
        market: Entity,
        commodity: Commodity,
        quantity: f32,
    },

    // --- Ship lifecycle ---
    DecommissionShip { ship: Entity, reason: &'static str },

    // --- Subsystem refit (Phase 18d, agent-driven) ---
    /// Ship requests a subsystem swap at its currently-docked shipyard.
    /// Apply phase re-verifies docked+stock+credits+retrofit-point,
    /// then performs the same mutations as an admin via_shipyard
    /// refit PLUS decrements the ship's retrofit_points by one.
    /// Silently no-ops on any validation failure — the BT is expected
    /// to replan on the next tick after a failed refit.
    RequestRefit {
        ship: Entity,
        slot: crate::modules::Slot,
        slug: &'static str,
    },
}

/// Per-tick command buffer. Cleared at the end of each tick after all commands
/// have been applied. Rayon-parallel phases can each push to a thread-local
/// buffer then merge at the phase boundary.
#[derive(Debug, Default)]
pub struct CommandBuffer {
    pub commands: Vec<SimCommand>,
}

impl CommandBuffer {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn push(&mut self, cmd: SimCommand) {
        self.commands.push(cmd);
    }

    pub fn append(&mut self, other: &mut CommandBuffer) {
        self.commands.append(&mut other.commands);
    }

    pub fn drain(&mut self) -> std::vec::Drain<'_, SimCommand> {
        self.commands.drain(..)
    }

    pub fn len(&self) -> usize {
        self.commands.len()
    }

    pub fn is_empty(&self) -> bool {
        self.commands.is_empty()
    }

    pub fn clear(&mut self) {
        self.commands.clear();
    }
}
