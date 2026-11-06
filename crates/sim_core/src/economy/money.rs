//! Accounting view over native wallets, not a second ledger.
use bevy_ecs::prelude::World;
use crate::agents::{facility::FacilityOperations, faction::FactionData,
    population::PopEconomy, ship::{ShipEconomy, ShipCrew}};
use super::contracts::ContractBoard;

#[derive(Debug, Default, Clone, PartialEq, Eq, serde::Serialize)]
pub struct MoneySnapshot {
    pub ships: i128,
    pub facilities: i128,
    pub factions: i128,
    pub households: i128,
    /// Actual savings debited from ship cash, counted once, persisted in resume_json.
    pub crew_savings: i128,
    pub escrow: i128,
    pub total: i128,
    pub unverified_contracts: usize,
    pub negative_accounts: usize,
}

impl MoneySnapshot {
    pub fn capture(world: &mut World, board: &ContractBoard) -> Self {
        let mut result = Self::default();
        macro_rules! sum {
            ($ty:ty, $field:ident, $target:ident) => {
                for account in world.query::<&$ty>().iter(world) {
                    result.$target += account.$field as i128;
                    result.negative_accounts += usize::from(account.$field < 0);
                }
            }
        }
        sum!(ShipEconomy, credits, ships);
        sum!(FacilityOperations, credits, facilities);
        sum!(FactionData, treasury, factions);
        sum!(PopEconomy, total_wealth, households);
        sum!(ShipCrew, wages_credits, crew_savings);
        for contract in board.iter() {
            if let Some(funding) = &contract.funding {
                result.escrow += funding.reserved as i128;
                result.negative_accounts += usize::from(funding.reserved < 0);
            } else if !matches!(contract.status, super::contracts::ContractStatus::Paid | super::contracts::ContractStatus::Expired) {
                result.unverified_contracts += 1;
            }
        }
        result.total = result.ships + result.facilities + result.factions
            + result.households + result.crew_savings + result.escrow;
        result
    }
}
