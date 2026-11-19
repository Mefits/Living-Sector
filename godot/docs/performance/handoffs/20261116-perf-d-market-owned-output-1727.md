# PERF D — N150 owned output transfer (16.11.2026 17:27 MSK)

- Branch: `integration/perf-astra-5-workers-20261116`, draft PR #262. No merge.
- CODE SHA: `e0367bfc005066e838f3df2f3a9cf65c0db81c22`.
- TEST SHA: `6e526c32e15acef6f4f32e29672ee137f20890d7`.
- Files: `godot/scripts/sim/phase2/unified_market_phase.gd`; `godot/tests/p2_perf_d_market_owned_output_20261116.gd`.
- Hot path: each paid market tick N150 already deep-copies each market; P2 proposal then deep-copied prices, demand, seed_demand, consumption_window, orders, crisis history again. The latter history is itself deep-copied by `stage_market_history`. Removed six redundant deep copies from P2 output construction; output remains detached from input World. No price/stock/cadence/AI changes.
- Evidence: existing `p2_perf_d_market_dto_borrow_oracle.gd` compares P2 proposal with old eager-copy implementation across ticks 0/16/32/200/201 and invalid orders. New targeted negative checks output/source/cross-market isolation, repeated proposal and malformed second market.
- TEST EXECUTED: NOT RUN. CODE_UNVERIFIED / TEST_ADDED_NOT_RUN; no Godot runtime used, no CI started. No claimed performance gain or full parity. Existing Linux profiled baseline markets ~39.43s/300 ticks at tick601–900 (~131ms/tick), but this site contribution is not yet measured.
- NEXT: bounded same-seed early/late window with per-site `P2 output duplicate` timing/calls and market sizes, run both oracle tests and N38 restart/full N9/N39/BT/RNG parity before acceptance. If improvement is insignificant or parity fails, revert this specific transfer. Do not trigger standalone 2600 tick CI.
