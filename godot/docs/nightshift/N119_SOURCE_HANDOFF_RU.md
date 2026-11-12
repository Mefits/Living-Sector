# N119 — Phase 1 Rust component port

Frozen source: `native/crates/sim_core/src/sim_server/engine/admin.rs admin_spawn_ship` (for N119 use `native/crates/sim_server/src/engine/admin.rs`).

Dependencies: native DB insert, ship class config, fitting defaults, N101 progression.

Hydration of already persisted admin ship; NOT a shipyard production queue. Requires db_insert_confirmed and caller-owned index/persistence. Fitting/personality/LOD exact constructors deferred.

Minimal static check: source inspected and standalone GDScript added. Godot parser/runtime NOT executed. Status CODE_UNVERIFIED. No P1, main or Rust archive writes.
