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

    // --- Contracts ---
    PostContract { contract_id: String },
    AcceptContract { ship: Entity, contract_id: String },
    DeliverContract { ship: Entity, contract_id: String },
    ExpireContract { contract_id: String },

    // --- Economy transfers ---
    TransferCredits {
        from: Entity,
        to: Entity,
        amount: i64,
    },

    // --- Supply adjustments (facility recipes, population production) ---
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
