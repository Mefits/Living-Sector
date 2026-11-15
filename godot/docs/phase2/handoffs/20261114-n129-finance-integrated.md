# 14.11.2026 — N129 Rust faction tax / bailout / relief transferred into canonical Godot World

**Branch:** `integration/godot-phase2-unified-20261113`, PR #249.
**Authority:** frozen Rust `agents/faction.rs::run_tax_cycle/run_bailout_cycle` and `agents/faction/relief.rs::tick_relief` with existing GDScript ports `faction_tax_n129.gd` and `native_faction_relief.gd`.

### Work done
- `unified_native_faction_finance_phase.gd`: pure stage of original tax (200×mult; 2.5% of facility credits above 1000), immediate post-tax bailout (facility below 500, target 2000, faction reserve at least 10000), then bounded source relief (25×mult; households, actual market facility payers, essential producers). Existing funds only; no synthetic receipt.
- `n39_native_world_production.gd::apply_native_faction_finance`: runs in the sole authoritative N39 World, reprojects all actual population/facility/treasury accounts, posts one exact N9 household/facility/faction transfer per real source-stage leg, validates every balance, total and single ledger, publishes results atomically. An invalid stage fails closed; there is no side-effect unless the entire batch succeeds.
- `n158_production_runtime.gd`: invokes the original tax/bailout/relief ordering in factions phase *after* territory recomputation, *before* N153 AI, construction/research strategic spending. Summary exposes actual per-tick receipts, source due flags and finance cursor.
- `n158_galaxy_production_seed.gd` and N39 Schema/N38: add canonical source finance phase cursor, preserve in same checkpoint, disallow future-tick cursor/replay. Old checkpoints absent the new cursor are not backfilled with fictitious subsidies.

**Verification status by user's explicit order:** source integration code is written, syntax brackets/imports/indent static checks PASS. **No headless Godot, no GitHub Actions, no gameplay tests before final integration completion.** This is not a runtime PASS.

### Remaining source work
Source N154 shipyard/refits, N100 Hybrid director+administrators as live executable decisions, N151 real colonies / passenger contracts, other source ECS behaviors and dynamic market/faction events. Do not rebalance Food/Energy/industry or manually make ships fly.
