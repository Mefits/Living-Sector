# Living Sector — 14.11.2026 — N140 spatial ship LOD wired into one N158/N39 fleet

**Scope:** frozen `native/crates/sim_core/src/simulation/lod.rs`, `agents/ship/mod.rs::tick_ships` and native `ship/behavior.rs` N148. One Phase2 PR #249 branch `integration/godot-phase2-unified-20261113`. **SOURCE_WIRED / CODE_UNVERIFIED**.

## Connected source mechanics
- New N46 seeded `AgentLod::new()` cursor on every **actual** live Rust 24-ship record; old N38 P2 ships missing `lod` keep Rust fallback "fire every tick", no invented migration.
- New `unified_n140_ship_lod_phase.gd`: original P1 N140 `recompute` 50×tick_multiplier, native distance tiers {1,2,5,10,20,50}, cursor `try_fire`, nearest actual observer in **universe/world coordinates** and actual ship transit/current orbital position. No connected observer => **all ships divisor=1**, as original Rust headless / no-clients behavior. A real camera position is NOT inferred from UI pixels; current N158 passes no observers pending an actual native observer source.
- `unified_ship_phase.gd`: N14 physical ship advance and fuel burn only for the **same** fired ship IDs. `ship_transit.gd` accepts an explicitly N140-authorized nonsequential tick and scale `native_tick_scale * skipped_ticks`, keeps direct N14 commands strictly sequential. Never teleports physical cargo.
- `unified_n140_ship_ai_dispatch.gd`: original `unified_ship_ai_execution.gd::propose` is called against a detached world view containing **only fired ships**, its BT/N146 effects merged with untouched sleeping ships before sole N39 commit. Non-firing ships do not advance source N84 BT cursors, receive orders or issue N146 ship commands.
- `unified_n148_ship_retirement_phase.gd`: the same N140 fired map gates N148 idle/strike accumulation. Rust ships asleep under LOD do not accrue one idle per skipped global tick; native 500×mult threshold is unchanged. Existing N39 N148 stage checks no money/other world mutation.
- N158 ships phase passes source tick multiplier to N140, uses the returned fired map for N84 and N148 while still using the original N39 World/ledger and one N14 flight. The pass stores last-tick N140 fired/skipped/recomputed stats and preserves N104 passenger transaction dispatch added by the second chat.
- N38 save round-trip: N158 JSON integer normalization and N39 Schema verify source `lod.divisor` u8, `lod.next_tick` nonnegative int. Cursor and unfinished flight remain inside the existing canonical checkpoint, no second save or timer.

## Static review & remaining gaps
- GitHub re-read / lexical bracket, strings, file indentation checks of changed GDScripts. This includes fixing one mixed-indent N14 signature. **No Godot parser, execution, GitHub Actions, Windows builds or user tests**; runtime and complete Rust parity NOT VERIFIED.
- N140 original server `tick_lod_recompute` also aggregates facility/population cursors for diagnostics; their gameplay simulation is deliberately NOT LOD gated in Rust. This P2 bridge currently reports live ship tiers only and lacks a connected real observer source.
- Crew needs/wages and personal market observation in Rust also run under the fired map; the existing P2 ship pipeline does not yet own the full original crew and price-observation Apply. Those remain broader source parity gaps rather than inventing a duplicate crew subsystem.
- Skipped N140 transit uses the existing P2 N14 position/fuel implementation. Headless Rust-vs-Godot differential parity and full 1/5/50 tier saved-flight cases remain final integrated tests after ALL Rust source code is ported.
- No economy balance changes, free hulls, extra world, new UI or alternative AI. Other worker's N104 passenger lease RELEASED before N39/N158 central modifications; those N104 code paths were left intact.

## Final acceptance after source integration freeze
- d1 no observers: one N84/N148 fired tick per real tick.
- d5/d50 real observer, native 50×mult recompute, exact one firing with correct skipped-time motion/fuel, none on sleeping ticks; no double N148 strikes.
- N14 save/load midflight with LOD cursor and N38 bytes normalized; 24 physical source ships, disappearing actors retain N152 historical record, no N9 mint.
- N104 passenger flight remains physical and can continue over N140 skipped ticks; N148 cannot retire a ship with embarked passengers.
