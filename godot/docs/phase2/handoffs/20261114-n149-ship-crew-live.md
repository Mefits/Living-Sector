# Living Sector — N149 native aggregate ship crew integrated into single P2 N158/N39

**Date:** 2026-11-14. **PR:** #249. **Branch:** `integration/godot-phase2-unified-20261113`.
**Status:** `SOURCE_WIRED / CODE_UNVERIFIED`. NO Godot runtime/parser, Actions, Windows build or user playtest. User requires ALL frozen Rust source integrated first, then gameplay testing/rebalance.

## Frozen source
- `native/crates/sim_core/src/agents/ship/mod.rs::tick_ships/tick_crew` orders N140-gated ship transit → crew decay → morale at 5×mult → meal from cargo and actual task → paid wages at 50×mult → ShipEconomy.efficiency → N84 decisions.
- `native/crates/sim_db/src/spawner.rs` N50 crew defaults reproduced by already authored `native_crew_roster.gd`, not a synthetic crew population.
- Original P1 `n149_native_crew_tick_single_owner.gd::core_step` implements exact stage order and native thresholds, no physical Apply. N72 and N138 isolated modules are NOT added as separate clocks.

## Code wired in PR #249
1. `godot/scripts/sim/ships/native_fleet_bootstrap.gd`: new clean-seed real N46 ships include ORIGINAL N50 aggregate `crew` health/hunger/morale/fatigue/task/wage savings, skills, `cargo_age={}`, initial efficiency. No seeded bonus credits/cargo/food or crew wages. Old checkpoints lacking these fields may reconstruct literal default on first active crew tick, without resetting pre-existing components.
2. NEW `godot/scripts/sim/phase2/unified_n149_ship_crew_phase.gd`: single pure staging operation reads exact N39 ship wallet, N15 hold, real dock/transit, N140 fired map and real cargo ages; invokes original N149 core_step only for fired hulls, applying skipped-ticks scale. Checks food physically consumed, ship wage credits debited and same amount accrued to crew, next stats & task. One staged N9 snapshot for all ships, fail on any invalid item.
3. `godot/scripts/sim/economy/credit_ledger.gd::pay_native_ship_crew`: source ShipEconomy.credits reduction is ONE auditable N9 debit receipt; opposite amount accrues to the original nonspendable `ShipCrew.wages_credits` component, NOT a second tradable N9 wallet. Monetary total of spendable N9 balances decreases exactly by wages, while crew savings increase by same amount. No phantom transfer, replay or invented payee.
4. `godot/scripts/sim/phase1/n39_native_world_production.gd::apply_native_n149_ship_crew`: at N158 native ships tick (_last_tick+1), stage both N39 world/N9 ledger, refuse edits to other domains or unfired hulls, check every wage receipt and its original amount, conservation of active N9 total minus wages, exact ship->wallet agreement and schema preflight. Single _world/_ledger swap only on success.
5. `godot/scripts/sim/phase2/n158_production_runtime.gd`: after N14 and before N84/N146/N148, source N149 crew stage fires once using THE SAME real N140 fired map. Exposes crew food/wage diagnostics. N38 JSON normalization covers crew headcount, accrued wages, cargo ages and native skill integers. Read-only last_native_ship_crew() resets on new seed/load.
6. `godot/scripts/sim/phase1/n39_native_world_schema.gd`: validates optional original ShipCrew fields, physical headcount from live N46 ship, task enum, stat bounds, nonspendable wage credits, cargo_age and efficiency. Legacy P2 saves without crew remain acceptable.

## Verification and remaining full-parity dependencies
- GitHub readback: balanced brackets and quotes, consistent indentation, no NUL, trailing newlines across six GDScripts; source method names/calls crosschecked; only static, NO actual Godot parse/runtime. No Actions.
- Rust `ShipCrew.wages_credits` is nonspendable inside native ECS. P2 N9 presents it as auditable paid outflow, not spendable account. Differential Rust/Godot playback and precision (Rust f32 versus GDScript float) is NOT proven.
- The existing source N84/N153 trade/strategy costs may not yet consume new live `crew_efficiency` everywhere; that is separate planner/economic full-parity integration, not proof of working autonomous trade.
- N140 price observation, individual crew skill XP, full native checkpoint replay and source ship retirement financial reconciliation remain broader full-parity work. N151 dock/colony code from second chat was preserved.
- User plans complete source integration before gameplay tests and balance/UX fixes; no test or balance request in this handoff.
