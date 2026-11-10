"""Build-only source overlay for Galaxy 0.3 AI, applied after extracting CI input.

The uploaded archive remains unchanged; all fixes are explicit and fail closed
if the source layout or exact expected code is different.
"""
from pathlib import Path

root = Path(__file__).resolve().parent.parent / "work" / "source" / "Living-Sector-Galaxy-0.2"
strategy = root / "crates" / "sim_core" / "src" / "strategy"

def replace_exact(path: Path, old: str, new: str) -> None:
    data = path.read_text(encoding="utf-8")
    count = data.count(old)
    if count != 1:
        raise RuntimeError(f"Expected exactly one match in {path}: found {count}")
    path.write_text(data.replace(old, new, 1), encoding="utf-8")
    print(f"Patched {path.relative_to(root)}")

replace_exact(
    strategy / "colony_development.rs",
    "        let required_workers = local.iter().filter(|(f, _, _)|",
    "        let required_workers: i64 = local.iter().filter(|(f, _, _)|",
)

replace_exact(
    strategy / "coordination.rs",
    """    let mut query = world.query::<(&MarketIdentity, &MarketPricing)>();
    let sources = sourcing::Sources::new(
        query.iter(world).map(|(id, market)| (id.facility_location.as_str(), market)),
        owners, relations,
    );""",
    """    // Own a stable snapshot rather than borrowing ECS World throughout
    // the director's evaluation. Native orders still revalidate live prices.
    let market_snapshot: Vec<(String, MarketPricing)> = {
        let mut query = world.query::<(&MarketIdentity, &MarketPricing)>();
        query.iter(world).map(|(id, market)|
            (id.facility_location.clone(), market.clone())).collect()
    };
    let sources = sourcing::Sources::new(
        market_snapshot.iter().map(|(location, market)| (location.as_str(), market)),
        owners, relations,
    );""",
)
print("Galaxy AI source overlay applied.")
