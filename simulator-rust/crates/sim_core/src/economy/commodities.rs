use serde::{Deserialize, Serialize};
use std::fmt;

/// All tradeable commodities in the simulation, organized into 4 supply-chain tiers.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Commodity {
    // Tier 1 — Raw (mined from celestial bodies)
    Ore,
    Ice,
    Gas,
    // Tier 2 — Refined (processed from raw)
    Metals,
    Fuel,
    Polymers,
    Water,
    // Tier 3 — Manufactured (assembled from refined)
    Components,
    Electronics,
    Tools,
    // Tier 4 — Consumer (end products)
    Food,
    Medical,
    Luxury,
}

impl Commodity {
    pub const ALL: &'static [Commodity] = &[
        Commodity::Ore,
        Commodity::Ice,
        Commodity::Gas,
        Commodity::Metals,
        Commodity::Fuel,
        Commodity::Polymers,
        Commodity::Water,
        Commodity::Components,
        Commodity::Electronics,
        Commodity::Tools,
        Commodity::Food,
        Commodity::Medical,
        Commodity::Luxury,
    ];

    pub fn tier(self) -> u8 {
        match self {
            Commodity::Ore | Commodity::Ice | Commodity::Gas => 1,
            Commodity::Metals | Commodity::Fuel | Commodity::Polymers | Commodity::Water => 2,
            Commodity::Components | Commodity::Electronics | Commodity::Tools => 3,
            Commodity::Food | Commodity::Medical | Commodity::Luxury => 4,
        }
    }

    /// Base price in credits. Market prices drift from these via supply/demand.
    pub fn base_price(self) -> f32 {
        match self {
            Commodity::Ore => 15.0,
            Commodity::Ice => 10.0,
            Commodity::Gas => 20.0,
            Commodity::Metals => 45.0,
            Commodity::Fuel => 25.0,
            Commodity::Polymers => 40.0,
            Commodity::Water => 12.0,
            Commodity::Components => 80.0,
            Commodity::Electronics => 120.0,
            Commodity::Tools => 90.0,
            Commodity::Food => 18.0,
            Commodity::Medical => 100.0,
            Commodity::Luxury => 150.0,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Commodity::Ore => "ore",
            Commodity::Ice => "ice",
            Commodity::Gas => "gas",
            Commodity::Metals => "metals",
            Commodity::Fuel => "fuel",
            Commodity::Polymers => "polymers",
            Commodity::Water => "water",
            Commodity::Components => "components",
            Commodity::Electronics => "electronics",
            Commodity::Tools => "tools",
            Commodity::Food => "food",
            Commodity::Medical => "medical",
            Commodity::Luxury => "luxury",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "ore" => Some(Commodity::Ore),
            "ice" => Some(Commodity::Ice),
            "gas" => Some(Commodity::Gas),
            "metals" => Some(Commodity::Metals),
            "fuel" => Some(Commodity::Fuel),
            "polymers" => Some(Commodity::Polymers),
            "water" => Some(Commodity::Water),
            "components" => Some(Commodity::Components),
            "electronics" => Some(Commodity::Electronics),
            "tools" => Some(Commodity::Tools),
            "food" => Some(Commodity::Food),
            "medical" => Some(Commodity::Medical),
            "luxury" => Some(Commodity::Luxury),
            _ => None,
        }
    }
}

impl fmt::Display for Commodity {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

/// A cargo hold: commodity → quantity.
pub type Cargo = std::collections::HashMap<Commodity, u32>;

/// A price memory entry stamped with the tick it was observed.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PriceMemory {
    pub price: f32,
    pub tick: u64,
}

/// Price knowledge indexed by location_id → commodity → PriceMemory.
pub type PriceKnowledge =
    std::collections::HashMap<String, std::collections::HashMap<Commodity, PriceMemory>>;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn all_commodities_have_base_price() {
        for c in Commodity::ALL {
            assert!(c.base_price() > 0.0, "{} base price should be positive", c);
        }
    }

    #[test]
    fn tier_ordering() {
        assert_eq!(Commodity::Ore.tier(), 1);
        assert_eq!(Commodity::Fuel.tier(), 2);
        assert_eq!(Commodity::Components.tier(), 3);
        assert_eq!(Commodity::Food.tier(), 4);
    }

    #[test]
    fn round_trip_str() {
        for c in Commodity::ALL {
            let s = c.as_str();
            assert_eq!(Commodity::from_str(s), Some(*c), "round-trip failed for {}", s);
        }
    }

    #[test]
    fn serde_round_trip() {
        let c = Commodity::Electronics;
        let json = serde_json::to_string(&c).unwrap();
        let back: Commodity = serde_json::from_str(&json).unwrap();
        assert_eq!(c, back);
    }
}
