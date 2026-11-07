//! One outstanding economic request per ship, acknowledged by the apply phase.
//!
//! This mailbox is transient, like the BT it belongs to. Sequence numbers prevent
//! duplicate commands within a running world; they are NOT a durable replay log.
//! Replanning cancels the mailbox, without resetting its sequence counter.

use crate::economy::commodities::Commodity;

#[derive(Debug, Clone, PartialEq)]
pub enum ShipTransaction {
    Accept {
        contract_id: String,
    },
    Buy {
        location: String,
        commodity: Commodity,
        quantity: u32,
        max_unit_price: f32,
    },
    Sell {
        location: String,
        commodity: Commodity,
        quantity: u32,
        min_unit_price: f32,
    },
    Refuel {
        location: String,
    },
    /// Native physical extraction at a body-linked mining waypoint.
    /// This is not a market purchase or an implicit stock generator.
    Mine {
        location: String,
        body_id: String,
        commodity: Commodity,
        quantity: u32,
    },
    Deliver {
        contract_id: String,
    },
}

impl ShipTransaction {
    pub fn kind(&self) -> &'static str {
        match self {
            Self::Accept { .. } => "accept",
            Self::Buy { .. } => "buy",
            Self::Sell { .. } => "sell",
            Self::Refuel { .. } => "refuel",
            Self::Mine { .. } => "mine",
            Self::Deliver { .. } => "deliver",
        }
    }
}

#[derive(Debug, Clone)]
pub struct PendingTransaction {
    pub id: u64,
    pub request: ShipTransaction,
    /// None until the exclusive apply phase validates and commits/rejects it.
    pub result: Option<Result<(), &'static str>>,
}

#[derive(Debug, Clone, Default)]
pub struct TransactionSlot {
    pub sequence: u64,
    pub pending: Option<PendingTransaction>,
}

impl TransactionSlot {
    pub fn begin(&mut self, request: ShipTransaction) -> Option<u64> {
        if self.pending.is_some() {
            return None;
        }
        self.sequence = self.sequence.checked_add(1)?;
        self.pending = Some(PendingTransaction {
            id: self.sequence,
            request,
            result: None,
        });
        Some(self.sequence)
    }
}
