# N55 — Tick admission / frame hitch safety

Source: frozen Rust `native/crates/sim_core/src/simulation/config.rs` (8 TPS, world_speed=0.25, tick_scale=world_speed/TPS), `native/crates/sim_server/src/engine.rs` (tokio interval + MissedTickBehavior::Delay). Existing P1 `TickRunner` remains authoritative; no new game-time unit is introduced.

Changes: P1 `SimClock.consume_frame` preserves fractional normal-frame accumulation, rejects invalid delta, and on a window/OS hitch >250 ms admits one tick then discards stale wall-clock debt. Manual stepping remains chunked at 16 ticks/frame and works while paused. Read-only `last_admission()` gives ticks/mode/dropped_seconds for diagnostics, never changes snapshot schema. Tick speed still changes native `tick_scale`, not TPS.

Alternative: replaying every missed wall-clock tick is rejected because it would execute many future financial/economic actions in one render frame; dropping *all* hitches would freeze even one due tick. No third-party scheduler or ECS needed; one `RefCounted` clock is shared by the simulation.

Acceptance: `godot --headless --path godot --script res://tests/n55_clock_admission_check.gd` (short isolated check). Runtime unavailable during implementation: CODE_UNVERIFIED. Existing Windows checkpoint unchanged. No P2/P3/AI functionality is implied.
