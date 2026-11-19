# PERF D · N150 read-only DTO ownership boundary · 2026-11-16 09:28 MSK

Branch: `integration/perf-astra-5-workers-20261116`, shared draft PR #262.

CODE COMMIT: `e0612de6e2953f82c980f07a3885c91da4ba0093`.
TEST COMMITS: `a30d606a2e2ee1f357fbc3afbee7c61ff7fa37a4`, `3c08d5ae756eec0954a7f69858e08e755454bd72`.

Files:
- `godot/scripts/sim/phase2/unified_market_phase.gd`: borrow seven read-only nested market fields in DTO projection, instead of deep copying before N150's mandatory owned `market.duplicate(true)`. N150 `tick_one_market` validates and deep-copies before mutations. Returned updates remain detached with explicit `duplicate(true)`. No new World/ledger/runtime.
- `godot/tests/p2_perf_d_market_dto_borrow_oracle.gd`: eager-copy legacy oracle vs new Phase.propose, multiple ticks, warning events, nested output mutation, malformed pending order rejection and no source mutation.

TEST EXECUTED: NOT RUN (no Godot 4.7.2 execution). CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. Source signatures and preload paths checked through GitHub connector. Performance improvement NOT MEASURED; do not claim FPS gain. No Actions triggered, no merge, no balance/cadence/search changes.

Risk: borrowed dictionaries are read-only only by convention until N150 deep ownership; recheck if N150 changes its ownership boundary. Full N38 restart and 420/900 identical-seed parity remain unverified. Next: run targeted oracle; fix any parser/runtime failures, then benchmark market DTO allocations and 420/900 phase cost against parent SHA with N38 checkpoint/restart and full market/ledger parity.
