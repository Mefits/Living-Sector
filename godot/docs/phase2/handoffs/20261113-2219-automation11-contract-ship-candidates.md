# P2 autonomous contract candidate boundary — automation11
- 2026-11-13 22:19 MSK. Commit `7ad41652c8419323fee831f674c7fbab5203fa45`.
- Added `unified_autonomous_contract_candidates.gd`, pure read-only N153 admission candidates from canonical N39 `contract_board`, `escrow_balances`, markets, facilities, ships.
- Requires posted delivery contract, existing funded escrow, physical source stock and owner, idle ship physically at source, empty transit/dock, enough free hold and positive fuel.
- Deterministic ordered candidate and blocked reason output. No fake voyages, new wallets, stock changes or parallel runner.
- **SOURCE_PRESENT / CODE_UNVERIFIED**: not connected to N158 TickRunner or authoritative N104 accept; no actual ship movement, route graph verification, docking or cargo. No local Godot binary; no GitHub Actions used.
- Next: inspect frozen Rust N153/N80 policy and actual N14 graph; connect chosen candidate to canonical N39 contract acceptance + ship command through one atomic Apply, then physical N21/N15 execution and save/load.
- No central files reserved or changed. Lease RELEASED.
