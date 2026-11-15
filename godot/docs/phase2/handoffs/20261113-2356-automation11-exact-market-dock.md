# P2 autonomy — exact N104 market docking (automation11)
- Date: 2026-11-13 23:56 MSK. Branch: `integration/godot-phase2-unified-20261113`, PR #249.
- Scope: `docking_registry.gd`, `unified_fleet_logistics.gd`; no N39/N9/ContractBoard changes.
- Code: `c5d512e` adds optional exact facility target to N21; `4242245` routes unified dock requests to actual canonical market warehouse owner rather than largest unrelated station at same location.
- Regression `caa30e2`: `godot/tests/p2_n21_exact_market_dock_check.gd` covers correct owner, no double dock, capacity failure without fallback, snapshot/restore.
- Real effect when executed: autonomous contract ship cannot accidentally occupy another station at the same location, which would make N97 paid cargo fail `not_docked_at_contract_warehouse`. N21 returns `no_available_dock` if contracted warehouse has no slots; no invented cargo, no bypass.
- Status: WIRED_CODE_UNVERIFIED. GitHub file writes confirmed. Godot 4.7.2 unavailable locally, no parser/headless/F5 execution. No GitHub Actions, no Windows ZIP.
- Remaining: run the new regression + existing `p2_native_paid_autonomous_delivery_check.gd`, then full unattended N14 multi-tick flight with N21 source/dest and N104 payout; check N39 SaveState mid-flight.
- Caveat: market owner is selected only when the ship's current location has a canonical market; non-market docking retains original deterministic N21 selection. The source `station` type constraint remains unchanged.
- Lease `20261113-2356-automation11-contract-dock-target.json` RELEASED after code handoff.
