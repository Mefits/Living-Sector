extends RefCounted
## Immutable native Galaxy 0.6.7 commodity catalog.
## Source: native/crates/sim_core/src/economy/commodities.rs @ Rust archive 6e40615.
## Keep the Rust Commodity::ALL order for deterministic serialization.
const ORDER: Array[String] = [
    "ore", "ice", "gas", "rare_ore", "crystal_ore",
    "metals", "fuel", "polymers", "water", "alloys",
    "components", "electronics", "quantum_cores", "tools",
    "food", "medical", "luxury"
]
const TIERS: Array[int] = [1,1,1,1,1, 2,2,2,2,2, 3,3,3,3, 4,4,4]
const BASE_PRICES: Array[float] = [
    15.0,10.0,20.0,75.0,140.0, 45.0,25.0,40.0,12.0,145.0,
    80.0,120.0,320.0,90.0, 18.0,100.0,150.0
]

static func contains(slug: String) -> bool:
    return ORDER.has(slug)

static func tier(slug: String) -> int:
    var index: int = ORDER.find(slug)
    return TIERS[index] if index >= 0 else -1

static func base_price(slug: String) -> float:
    var index: int = ORDER.find(slug)
    return BASE_PRICES[index] if index >= 0 else -1.0

static func catalog() -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for i in range(ORDER.size()):
        result.append({"slug": ORDER[i], "tier": TIERS[i], "base_price": BASE_PRICES[i]})
    return result

static func validate() -> String:
    if ORDER.size() != 17 or TIERS.size() != 17 or BASE_PRICES.size() != 17:
        return "Native catalog must have exactly 17 entries"
    var seen: Dictionary = {}
    for i in range(ORDER.size()):
        if seen.has(ORDER[i]) or TIERS[i] < 1 or TIERS[i] > 4 or BASE_PRICES[i] <= 0.0:
            return "Invalid commodity at index %d" % i
        seen[ORDER[i]] = true
    return ""
