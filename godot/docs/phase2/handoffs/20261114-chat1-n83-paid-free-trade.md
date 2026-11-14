# Living Sector P2 — Chat 1, N83 autonomous free trade / N97 real physical Apply

**Date:** 2026-11-14. **Branch:** `integration/godot-phase2-unified-20261113`. **PR:** #249.
**Status:** `SOURCE_WIRED / CODE_UNVERIFIED`. No Godot parser, F5, headless, Windows build, Actions or Rust/Godot diff was run (user requires final integrated test after port).

## Exact source chain now connected

`native/crates/sim_core/src/agents/ship/behavior.rs::best_trade_route_with_ownership` → original N83 freshness/history/own-market ranking and real N9 buyer liquidity → N80 `native_ship_goal_policy.gd` scoring, source N150 contested territory → N81 `native_goap_planner.gd` with directed N4 route legs → persistent N84 BT → original N21 real Dock/Undock → N90 `TransactionSlot` request + N146 `RequestShipTransaction` → existing P1 N97 `n97_ship_transaction_apply.gd` and `n97_ship_physical_settlement.gd` → **one canonical N39 World/N9 Ledger** and immutable N15 cargo / N9 monetary receipts. Free trading never posts a fake N104 contract.

### Main files

- NEW `unified_n83_trade_route_planner.gd`: examines only N140-fired, idle, unassigned physical ships and their real N150 ShipMemory price observations, canonical market/station cash and faction relations. Requires original actual N4 source and destination routes, accepted N80 goal and viable N81 GOAP plan; refuses unimplemented free Refuel/Refit leaves, no synthetic route/ship/funds. Preserves source contested market status and two-step ownership preference. One real N84 BT assigned to existing N39 ship.
- NEW `unified_n83_trade_action.gd`: Rust `Buy/Sell/SellAll` leaf semantics, observed physical prices and diplomatic price posture, capped affordable whole units, deterministic SellAll alphabetical commodity selection, exactly one N90 pending per ship; N146 command is ONLY a request. On the next fired N140 tick, real N97 acknowledgement is polled; rejection cancels only that speculative trade goal.
- NEW `unified_n83_free_trade_apply.gd`: projects a TEMPORARY N97 source fixture from the actual current N39 ship+station+market+N150 relations/physical N21 dock occupancy. Original P1 N97 Apply rechecks true dock, current quoted prices, owned supply, ship hold, actual cash, embargo, partial-sale buyer liquidity; **does not** become a second runtime or second money authority. Translation back permits one source market stock/trade history, one buyer station, one ship cargo + provenance/crew skills/route profitability and N90 acknowledgement. Staged transfer debits one genuine N9 wallet and credits the actual counterparty; one matching durable `n83:ship:<id>:<sequence>` N9 and N15 receipt. Error writes N90 negative ack without publishing physical changes.
- `n39_native_world_production.gd::apply_native_n83_free_trade`: independently verifies one real ship/market/operator, exact conservation of physical quantity, signed money delta, historical receipt immutability, full canonical Schema accounts and unchanged ledger total, then publishes **one** World+Ledger snapshot atomically.
- `unified_ship_ai_execution.gd`: N83 trade-run BT, actual N21 station dock/undock even without contract, N90 polls, N146 free trade request. N84 no longer stops the whole World when speculative trade is rejected; other cargo/funds remain untouched.
- `n158_production_runtime.gd`: after original N14→N140 observation→N149 crew, calls native N83 planning before N84 and executes free N21/N90/N97 via N39 while contract and passenger operations retain existing dispatch. N38 restoration normalizes N90 sequence/pending ID, real paid free-trade receipt quantity/payment/request ID and N83 route-performance attempts. Exposes `n83_trade_plans_this_tick` and `n83_paid_exchanges_this_tick`.
- `native_fleet_bootstrap.gd` now initializes Rust-original empty N90 transaction, cargo_origin and faction_reputation on the REAL N46 ships, with no credits or cargo added.
- `n39_native_world_schema.gd` validates N90 pending slot, original cargo cost basis and acquired route-performance statistics; old saves lacking optional N90 stay legal until first action.

## Unfinished, intentionally not claimed as verified

1. **Runtime proof is still absent.** No confirmed clean-seed profitable route, physical N14 arrival, actual N9 payment, one N97 buyer receipt or midflight N38 resume has been played through in Godot. These are final integrated tests after Rust port; use source fixture to isolate a genuine price differential without modifying seed/balance.
2. Rust original f32 pricing, exact market liquidity rounding, source gate jumps/recent_systems, dock queues and multi-agent source BT scheduling need full differential/runtime reconciliation; source bridge enforces original equations, not byte-for-byte proof.
3. N97 `Refuel` and `Mine`, free `Sell` outside a trade_run, exploratory N84 idle goals and full original strategic refit interactions are separate remaining ship-source port gaps; do not replace them with free-world transfers.
4. N145/N152 N104 expiration/refund lifecycle is separately source-wired (see `20261114-n152-canonical-close-refund.md`); **DO NOT** create a parallel refund runner. End-to-end N104 paid freight remains a separate final acceptance gate.
5. N38 results are `CODE_UNVERIFIED`; static GitHub readback checked source method wiring, bracket/string balance, UTF-8 newlines and uniform indentation. Zero CI/Actions spent. No user balance or UI changes.

**Suggested next Chat1 block** after lease recheck: complete original N97 paid Refuel/Mine through the same source transaction-slot and one N39/N9 apply, plus physical native GateJump/recent_systems if still missing; then final freight/free trade save-reload acceptance once all source is present.

**Ownership:** this work only on ship trade/N97 request parts. Chat 2 owns colony N144/N151/N154; Chat 3 owns faction AI and final integration. Shared `N39/N158/Schema` edits were made against fresh SHA, never force-pushed.
