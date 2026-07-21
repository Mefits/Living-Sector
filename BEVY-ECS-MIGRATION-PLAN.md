# Migrate `sim_core` from `hecs` → `bevy_ecs`

## Why

Three wins, decided after extended discussion (see CLAUDE.md "Don't do" + the rayon deferred note):

1. **Drop the mirror layer.** [crates/client_bevy/src/render/mod.rs](simulator-rust/crates/client_bevy/src/render/mod.rs) currently translates each hecs ship → a sibling Bevy entity with `Transform` + materials and syncs them every frame. With one ECS, the sim entity *is* the Bevy entity — `Transform` lives on the ship row directly. ~500 LOC of glue disappears.
2. **Free parallel queries.** `bevy_ecs` has `par_iter_mut` out of the box. The CLAUDE.md "Rayon on ship phase" deferred note estimates ~1.5× at 485 agents, ~5× at 10k. The snapshot-then-plan-then-apply structure we already have makes this almost mechanical.
3. **One ECS to maintain.** Two ECS APIs in the same workspace is a small but real papercut.

`bevy_ecs` runs headless fine (it's a separate crate from `bevy`, no winit / wgpu deps), so the headless concern is a non-issue.

## Non-goals

- Don't redesign the tick phase order. It stays exactly as `engine::run_tick_loop` defines it today.
- Don't change the `SimCommand` pattern. Cross-entity effects still buffer + apply.
- Don't introduce per-entity behaviour at this layer. ECS is a data store; AI / planning logic stays where it is.
- Don't break `sim_server`'s HTTP/WS surface (CI scripts depend on it). Either keep the binary or replace it with a `--headless` flag on `client_bevy` — but the curl endpoints stay byte-identical either way.

## Phases (ship one at a time, keep tests green between)

### Phase A — in-place ECS swap

Replace `hecs::World` with `bevy_ecs::World` inside `sim_core`. Same phase order, same components, same semantics. **No parallel queries yet** (would muddy the diff). **No mirror-layer changes yet** (Phase B).

Mechanical work:
- Add `#[derive(Component)]` to every component struct in `crates/sim_core/src/agents/*` and `simulation/*` (~30+ types).
- Translate query patterns:
  - `world.query::<(&A, &B)>().iter()` → `world.query::<(&A, &B)>().iter(&world)`
  - `world.get::<&mut T>(e)` → `world.get_mut::<T>(e)` (now `Option<Mut<T>>`)
  - `world.query_one::<(&mut A, &mut B)>(e)` → `let mut entity_mut = world.entity_mut(e); let (a, b) = (entity_mut.get_mut::<A>(), entity_mut.get_mut::<B>());`
  - `world.spawn((A, B))` returns `EntityWorldMut`; grab the id with `.id()`.
- Update `AgentStore` ([crates/sim_core/src/simulation/spawner.rs](simulator-rust/crates/sim_core/src/simulation/spawner.rs)) so its `World` field is `bevy_ecs::World`.
- Tests: most `#[test]` fns build a `World` directly today; just swap the type. The few that hand a `World` to a tick fn keep working.

Tick scheduling note: do NOT introduce a `bevy_ecs::Schedule` yet. Keep calling phase functions directly from `engine::run_tick_loop`. The Schedule machinery is Phase C; mixing it in here makes the diff hard to review.

**Done when:** `cargo test -p sim_core` is green, `client_bevy` and `sim_server` both compile and behave identically.

### Phase B — kill the mirror layer

Now that sim entities are Bevy entities, render systems can attach `Transform` + `Mesh3d` + materials directly to the ship/facility/body row instead of spawning a parallel mirror entity.

- Delete `spawn_mirror_entities`, `cleanup_stale_ships`, `reconcile_new_*` in [crates/client_bevy/src/render/mod.rs](simulator-rust/crates/client_bevy/src/render/mod.rs).
- `sync_positions` becomes a system that updates `Transform` from `ShipPosition` + `InterpPos` directly on the same entity. (Keep `InterpPos` for sub-tick smoothing — that part is unchanged.)
- `SelectedShip(Entity)` and friends already store entity ids; verify the id is now the same Bevy + sim entity. Click-pick raycasts already work entity-wise — should just work.
- Engine-trail particle entities (`EngineTrailFor(sim_id)`) become children of the ship entity instead of looking it up.

Watch for: render-side gizmos that read from sim components — they all keep working since the components are still queryable. The simplification is they no longer need a join through `sim_id_to_bevy_entity` maps.

**Done when:** the mirror layer is deleted, frame rendering looks identical to before, no warnings about orphan entities on ship spawn / decommission.

### Phase C — parallel ship phase

Now the payoff. The ship phase is structured as `advance_transits` (read-only) → `observe_prices` (read-only) → `decide_and_act` (writes own components + emits commands).

- Convert `decide_and_act` to a `Query<...>` + `par_iter_mut` invocation. Each ship gets its own `&mut Vec<SimCommand>` via a thread-local accumulator (`Local<Vec<SimCommand>>` per worker, drained after the parallel pass).
- Verify determinism is preserved: command ordering matters for apply. Sort or stably-merge the per-thread buffers by `(actor_entity_id, sequence)` before the apply phase. Exact strategy depends on what reproducibility we need — for now, deterministic-by-default: sort by entity id post-merge.
- Keep facility / market / population phases sequential. Ship phase is where the cost is.

**Done when:** `tick_compute_p99_us` drops noticeably at 485 agents (debug build); a 5k-agent stress test shows ~3× speedup on a 4-core machine.

### Phase D — retire `sim_server` (optional, separable)

`client_bevy --headless` boots an `App` with `MinimalPlugins` instead of `DefaultPlugins`, registers the same systems, exposes the same axum routes, skips winit + render. One binary, one source of truth.

- Move `crates/sim_server/src/{http,ws,snapshot}` into `client_bevy` (or a new shared lib). The apply helpers we already re-export from `sim_server::engine::*` move to `sim_core` since they no longer depend on anything sim_server-specific.
- `cargo run -p client_bevy -- --headless` replaces `cargo run --bin simulator`.
- Update CI scripts to invoke the new entry point.
- Delete `crates/sim_server`.

This phase is independent of A–C and can land any time after A. Worth doing — kills a whole binary's worth of code duplication — but not strictly required to harvest the parallel-queries + mirror-layer wins.

## Critical files

- [crates/sim_core/src/agents/](simulator-rust/crates/sim_core/src/agents/) — every module gets `#[derive(Component)]` adds
- [crates/sim_core/src/simulation/spawner.rs](simulator-rust/crates/sim_core/src/simulation/spawner.rs) — `AgentStore` wraps `World`
- [crates/sim_core/src/simulation/commands.rs](simulator-rust/crates/sim_core/src/simulation/commands.rs) — `SimCommand` apply paths use `world.get_mut`
- [crates/sim_core/src/agents/ship/](simulator-rust/crates/sim_core/src/agents/ship/) — biggest single consumer of query patterns; the planner hot path lives here
- [crates/client_bevy/src/sim/mod.rs](simulator-rust/crates/client_bevy/src/sim/mod.rs) — `Sim` resource definition
- [crates/client_bevy/src/render/mod.rs](simulator-rust/crates/client_bevy/src/render/mod.rs) — entire mirror layer to delete in Phase B
- [crates/sim_server/src/engine/mod.rs](simulator-rust/crates/sim_server/src/engine/mod.rs) — `pub fn` apply helpers shared with client_bevy; may move to sim_core in Phase D
- [crates/sim_db/src/spawner.rs](simulator-rust/crates/sim_db/src/spawner.rs) — DB-load path that builds entities; ECS-call sites need translation

## Risks

- **API translation density.** hecs and bevy_ecs are similar but not 1:1. The biggest gotcha is `query_one` (hecs lets you mutably borrow N components on one entity) — bevy_ecs spells it as `world.entity_mut(e).get_mut::<T>()` calls in sequence, which can fight the borrow checker if you grab mutable refs to two components and then try to call a method that takes `&mut World`. Plan: use small scopes + drop guards.
- **Bigger compile times for `sim_core`.** `bevy_ecs` is heavier than hecs. Verify `cargo build -p sim_core` doesn't blow up.
- **Determinism.** bevy_ecs schedules can run systems in parallel by default. We're not using a Schedule in Phase A, so this is a Phase C concern — but worth flagging early. Pin ordering aggressively in the parallel ship phase.
- **Persistence loader.** `sim_db::spawner` builds entities via hecs APIs. Translates 1:1 but every call site changes.
- **Test harness.** Tests currently build a `hecs::World`, call a tick fn, assert. The same shape works with `bevy_ecs::World`, just different type. No `App` needed for sim_core tests.

## How to start

1. Branch off `main`: `feat/bevy-ecs-migration`.
2. Phase A in one go on a single PR — it's all-or-nothing for compile success. Aim for ~1–2 days of focused work.
3. Smoke-test against `scripts/smoke.sh 30` to verify nothing changed behaviourally.
4. Land A. Phase B follows on its own PR. Phase C on its own. Phase D whenever.

Don't try to land A+B+C as one PR. The diff is too big to review and bisecting regressions becomes a nightmare.
