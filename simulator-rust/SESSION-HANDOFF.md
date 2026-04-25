# Session Handoff — Fresh Claude Start Here

A one-pager so a new Claude session can pick up this project without
reading the full history. Read this first, then `CLAUDE.md`, then
anything else as you need it.

## Where we are

**Bevy embedded client is the canonical client.** The Godot client
at `../client/` is code-frozen reference. The Rust sim runs through
the full economic loop *embedded inside the Bevy binary* — no WS,
no HTTP between sim and render. 39 client-side bundles shipped
(2a → 3aj). 1604 ships / 93 facilities / 27 pops / 8 factions
load, tick, render with HDR + bloom, and the user can pause /
speed / inspect / select / spawn / heal / delete from a 12-panel
egui inspector. `sim_server` still builds for headless CI use but
the development path is `cargo run --bin client_bevy`.

**Pre-Bevy phases (the long arc that came before the port):**
Phases 1–20c shipped, GOAP planner arc complete, Bundle 4 tranche
(S, H, G, Q, K, M, J), Bundle A (FactionRelations), Bundle B
(trade-pact effects), Bundle C (market posture). 190 tests passing.
Sim runs at p50 ≈ 10–20 ms, p99 ≈ 30–50 ms at 485 agents with
WORLD_SPEED=4. Three systems (Sol / Alpha Centauri / Tau Ceti)
plus extensions (Vega / Barnard / Lalande on the seed side).

## The Bevy port arc (Bundle 2a → 3aj)

| Bundle | What |
|---|---|
| 2a | Pivot from a planned WS client to embedded sim. Deleted `client_bevy/src/net/`. |
| 2b.1 | Extracted `sim_db` crate (pool, seeder, spawner, persistence) so client_bevy can load a world without sim_server's HTTP stack. |
| 2b.2 | client_bevy loads the real world from `sim.db` at Startup via a one-shot tokio runtime. |
| 2c | Spawn Bevy entities mirroring hecs ships / facilities / bodies. Per-faction materials. |
| 2b.3 | Minimum-viable tick — `ship::tick_ships` runs each FixedUpdate; ships move in transit. CommandBuffer dropped. |
| **2b.4** | **`sim_server` grew a `[lib]` target** so client_bevy could call `apply_ship_commands` + helpers. Full tick chain wired (bodies → ships → apply → dock-queue → facilities → pops → markets → apply2 → bodies_regen → crisis → factions → relations). Economy is **live** in embedded. |
| 3a–3w | Camera, perf overlay, ship list, faction-tint, contracts panel, factions panel, markets panel, populations panel, ship details (click-select), facility list+details, camera focus, retirements panel, construction sites panel, selection highlight, pause+speed, transit-line gizmos, starfield, click-on-mesh raycast, directional ship rotation, admin Grant XP, minimap, per-class silhouettes, body labels overlay. |
| 3x–3aj | Admin Delete Ship + render cleanup, events ticker, keyboard shortcuts (Space=pause, Esc=clear), admin Heal Ship, gate ring gizmos, construction site gizmos, Reset view, nebula backdrop, selection ring (pulsing), Save-As DB backup, admin Spawn Ship + reconciler, docked ship list with cross-nav, admin Refill Reserves on facility. |
| visual fix pass | Black ClearColor, shadows off (1604 shadow-casters dropped FPS to 1 on M1), WinitSettings Continuous (window kept ticking when Terminal took focus), camera far clip 20000, body/facility/ship sizes bumped, HDR + bloom on camera, F12 + env-var auto screenshot. |

The last visual-fix pass came out of user feedback ("background is
grey, FPS is 1, are you taking screenshots?"). Self-verification
loop now uses `CLIENT_BEVY_AUTO_SCREENSHOT=1 cargo run --bin
client_bevy` which captures `/tmp/bevy_screenshot.png` at frame 3
(macOS throttles backgrounded Bevy windows so frame counts stay low
under `cargo run &`; F12 in foreground works for live capture).

## How to run it, today

```bash
# Bevy client (canonical, embedded sim, no separate process)
cd /Users/dclausen/code/spaceproject/simulator-rust
cargo run --bin client_bevy
# F12 saves /tmp/bevy_screenshot.png. Spacebar pauses; Esc clears
# selection. Top bar exposes 12 panel toggles + pause + speed +
# Reset view + Save as… + +Freighter (admin spawn). Click ships
# in the list or in the 3D scene to inspect.

# Auto-screenshot for headless verification (background-throttled
# but enough frames render to capture):
CLIENT_BEVY_AUTO_SCREENSHOT=1 cargo run --bin client_bevy &
sleep 12 && kill %1
ls /tmp/bevy_screenshot.png

# Headless sim_server (still builds, useful for CI)
WORLD_SPEED=4.0 cargo run --bin simulator

# Verify everything (cargo check + test + clippy at -D warnings)
scripts/verify.sh --strict          # passes; ~190 tests across 4 crates
```

## Crate layout (current)

| Crate | Depends on | Purpose |
|---|---|---|
| `sim_core` | hecs, serde, rand, rayon | Pure sim logic, no async |
| `sim_protocol` | serde + sim_core | WS wire types (sim_server only) |
| `sim_db` | sim_core + sqlx + tokio | Pool, migrations, seeder, spawner, persistence |
| `sim_server` | sim_core + sim_db + sim_protocol + tokio + axum | Headless HTTP/WS + library surface for engine helpers |
| `client_bevy` | sim_core + sim_db + sim_server (lib) + bevy + bevy_egui | Embedded Bevy client |

`client_bevy` pulls axum / tower / flume transitively via sim_server's
lib target. They compile but aren't exercised — the trade-off
documented in Bundle 2b.4's commit. A clean move of `apply_ship_commands`
+ helpers into `sim_core::engine` remains possible later.

## Open candidates (heavy items, want focused sessions)

1. **Async drains in client_bevy** — `PendingMaterialization`,
   `PendingDecommission`, `PendingRespawn` queues never drain in
   embedded mode, so construction sites complete logically but
   never materialise into facilities; strikes accumulate but ships
   don't auto-retire; respawn queue fills with no consumer. The
   sim_server drain helpers are async (`drain_pending_*`) — would
   need either a long-lived tokio runtime + `rt.block_on(...)` per
   tick (blocks the FixedUpdate system) or sync no-DB versions.
2. **Embedded persistence worker** — sessions currently die at
   restart. Mirror sim_server's `PersistenceWorker`: long-lived
   tokio rt on a Resource, mpsc::Sender<DbWrite>, end-of-tick
   `emit_persist_writes`. Pairs with #1 — both want the long-lived
   runtime.
3. **Procedural ship meshes** — port `procedural_ship.gd` geometry
   into Rust. Per-class+size mesh cache; faction-coloured material;
   instanced render. Currently using elongated cuboids — works
   visually with HDR bloom but doesn't read as "ships". This is
   the biggest visual upgrade left.
4. **Admin Refit + Spawn Facility panels** — Spawn Ship is wired
   (3ah), Refit + Spawn Facility need similar treatment. Refit
   needs slot+slug dropdowns and via_shipyard bool; Spawn Facility
   needs facility_type + body_id pickers.
5. **Rayon on ship `decide_and_act`** — dep is in, never called.
   Snapshot-then-plan-then-apply refactor. ~5× speedup at 10k
   ships. Skip until needed.
6. **Backlog (N) from old roadmap** — same as #5 above.
7. **Click-on-mesh selection at zoom-in** — works at galactic
   overview (Bundle 3r) but pick radius is screen-space, so when
   zoomed in the radius shrinks proportionally. Could clamp to a
   minimum to keep clicks forgiving.
8. **Sol / Alpha Centauri / Tau Ceti vs Vega / Barnard / Lalande** —
   the world JSON has six systems but the gate network may not
   connect them all. Worth auditing if a player can actually
   traverse the whole map.

## Watch-outs / gotchas

- **macOS throttles backgrounded Bevy windows** to ~1 Hz unless
  `WinitSettings::focused_mode = unfocused_mode = Continuous` (set
  in `client_bevy/src/main.rs`). Without it, `cargo run &` runs
  the sim at 1 FPS. The user originally reported "FPS is 1" which
  was actually this, not real perf.
- **Shadows on a DirectionalLight kill perf at fleet scale.** 1604
  shadow-caster meshes on M1 integrated GPU drops the frame budget
  catastrophically. We set `shadows_enabled: false`; space scenes
  read fine on key + ambient alone.
- **Default Bevy camera far clip is 1000 wu.** With stars at 4000 and
  nebulae at 9000, both clipped. Set explicitly to 20000 in
  `camera/mod.rs`.
- **HDR + Bloom is load-bearing** for ship visibility. SHIP_SIZE is
  0.4 wu; at 500-wu camera distance that's a sub-pixel silhouette.
  Faction-tinted emissive materials + `BloomSettings::NATURAL` make
  ships read as bright sparks.
- **Bevy systems cap at 16 params per tuple.** `top_bar` blew through
  this when Save-As + Reset-view + Spawn-Ship were added; split
  into `top_bar_controls` + `top_bar` (panel toggles). Future
  large-param systems can use the same pattern or aggregate ResMuts
  into a single struct Resource.
- **Admin actions in client_bevy mutate hecs directly** (Grant XP,
  Heal, Delete, Refill Reserves). They don't round-trip through
  `SimCommand::*` — they're treated as direct admin overrides
  (matching sim_server's `admin_*` functions). Spawn Ship goes
  through `sim_server::engine::admin_spawn_ship` which is the same
  function the HTTP path uses.
- **The render side has two reconciliation systems**:
  `cleanup_stale_ships` despawns Bevy entities for vanished sim
  ships; `reconcile_new_ships` spawns Bevy entities for new sim
  ships. Without them, admin Spawn / Delete leak ghost or missing
  meshes. Same pattern would extend to facility add/delete when
  those land.
- **`Dock` is multi-tick** (Phase 18L). Returning `Running` is
  expected. Don't assume a single tick resolves a dock request.
- **Cross-system contract gate (Phase 18f)**: ships with
  `sensor_range_au < 2.0` never see cross-system contracts. Size≥5
  spawns tier-2 sensors. If "why won't this ship take this contract"
  comes up, check the fitting first.
- **Tick loop owns `hecs::World` exclusively.** HTTP / WS handlers
  read from `SnapshotCache` (DashMap), never touch the live world.
  Cross-entity state changes go through `SimCommand`. Same-entity
  mutation is in-place.
- **Ships don't replan every tick** — `plan_goal` only fires when a
  ship's BT completes. Trade_run BTs are 10+ actions. Economic
  rebalancing takes ~10+ game-minutes to settle, not seconds.
- **Recipe inputs come from `market.supply`, not facility reserves.**
  Refilling reserves doesn't feed recipes — that's why the Refill
  Reserves admin button only addresses the food/fuel/tools crisis,
  not raw input shortages.

## Critical files to read first

1. **`crates/client_bevy/src/main.rs`** — Bevy app bootstrap. Plugins,
   ClearColor, WinitSettings, screenshot system, scene lighting.
2. **`crates/client_bevy/src/sim/mod.rs`** — embedded `Sim` resource,
   tick chain (mirror of `sim_server::run_tick_loop`), admin
   request resources (SaveAsRequest, SpawnShipRequest), event log.
3. **`crates/client_bevy/src/render/mod.rs`** — placeholder mesh
   pool, faction materials with emissive, sync_positions,
   highlight_selected, gizmo systems (transit lines, gate rings,
   construction sites, selection ring), reconcile_new_ships +
   cleanup_stale_ships, raycast_select, starfield + nebulae.
4. **`crates/client_bevy/src/ui/mod.rs`** — every egui panel.
   `top_bar_controls` (pause/speed/save/reset/admin) + `top_bar`
   (panel toggles) + 12 inspector panels + minimap + body labels +
   keyboard shortcuts.
5. **`crates/client_bevy/src/camera/mod.rs`** — orbit camera with
   pan / zoom / orbit, CameraFocusRequest, CameraResetRequest,
   HDR + BloomSettings.
6. **`crates/sim_server/src/lib.rs`** — re-exports the engine /
   control / http / ws / snapshot / app_state modules so
   client_bevy can call into them.
7. **`crates/sim_server/src/engine.rs`** — tick loop driver, full
   command-apply phase, admin helpers. Many helpers were promoted
   to `pub` in Bundle 2b.4 + 3ah for client_bevy access.
8. **`crates/sim_core/src/agents/ship/mod.rs`** — biggest single
   file. Components + tick phases + BT actions + planner.
9. **`crates/sim_core/src/economy/contracts.rs`** — contract
   board + lifecycle.
10. **`crates/sim_db/src/persistence.rs`** — `DbWrite` enum,
    persistence worker, `load_retirements`, `save_as` (added in
    Bundle 3ag).

## Next session's first move

Decide based on user direction:
- "keep going" → pick the smallest unblocked item from open
  candidates (most likely #4 Admin Refit panel — follows the
  Spawn-Ship pattern from 3ah).
- "polish the visuals" → #3 procedural ship meshes.
- "fix retirements / persistence" → start #1 (async drains) since
  #2 (persistence worker) shares the long-lived runtime work.

`/ultrareview` for a multi-agent review of the current branch is
also viable — the port is feature-dense and ripe for a fresh look.
