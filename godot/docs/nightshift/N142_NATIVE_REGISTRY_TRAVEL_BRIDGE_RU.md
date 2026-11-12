# N142 — WorldRegistry, физические маршруты и legacy travel timing

**Статус Фазы 1: CODE_UNVERIFIED.** Исходник: frozen Rust Galaxy 0.6.7 `archive/rust-galaxy-067-reference`; `native/crates/sim_core/src/world/registry.rs` (127 строк), `native/crates/sim_core/src/world/travel.rs` (67 строк), `native/crates/sim_core/src/simulation/config.rs::TickConfig`. Также сверена семантика `world/pathfinder.rs` (281 строк), **не копируется повторно**, потому что уже есть N59/PR #147.

Вход в работу: atomically reserved `godot/docs/nightshift/claims/N142.json` @ `b80b322a`, macro #10. Ветка `feature/godot-n142-native-registry-physical-distance-20261112` от неизменного Phase-1 integration baseline. Реальный GitHub N58–N61 проверен до бронирования. N39/N100/N112/N140 и другие чужие исходники/PR не затронуты.

## Что именно перенесено

1. `godot/scripts/sim/phase1/n142_native_world_registry.gd`
   - Frozen Rust data model `SystemInfo` (`db_id,name,universe_offset,star_type?`), `LocationInfo` (`db_id,name,loc_type,celestial_body_id`), `Route` (`to,distance:u32`), `faction_ids`. Read-only copy of an **authoritative** DB/world snapshot; synthetic map coordinates NOT used for real route costs.
   - `travel_distance(from,to)`: returns the **first matching direct edge only** (Rust `iter().find()`); never invent reverse arcs, never assume shortest path, preserve duplicate arc order.
   - `reachable_from(location)`: outgoing native records in source insertion order, empty for missing origin; detached copy.
   - `shortest_distance(from,to)`: separate Dijkstra over **real directed physical routes only**, with saturating u32 addition, Rust `Reverse<(u32, String)>` heap, unknown intermediate nodes ignored, `from == to -> Some(0)` even when unknown. `u32::MAX` paths are not discovered because Rust uses strict comparison to default MAX. GATES EXCLUDED.
   - `physical_distance_matrix(requests)`: fail-closed `location -> location -> integer physical cost` facade for source N135 strategy/orders or N94 sourcing / faction-head budget estimates. Missing path => reject whole batch; do not replace with zero or distance inferred from galaxy map.
   - Canonical normalized snapshot/restore, original metadata retained, no new physical goods or money.

2. `godot/scripts/sim/phase1/n142_native_legacy_travel.gd`
   - Frozen `TickConfig::DEFAULT`: 8 TPS, world_speed=0.25; `tick_interval_ms=1000/tps` integer division, `tick_scale=speed/tps`, `tick_multiplier=round(tps/world_speed)`.
   - `world/travel.rs::travel_ticks(distance:u32,speed_modifier)`: integer truncation of `distance * tick_multiplier / max(speed_modifier, 0.1)`. At default 60/1.0 -> 1920 native ticks. `arrival_tick=departure + duration` and `transit_progress=(current-departure)/(arrival-departure)` with saturating elapsed and clamp. Input/tick signed-64 boundaries rejected rather than overflowed.
   - IMPORTANT: This is the **legacy route schedule and progress helper**, not real physical motion. Current frozen `agents/ship/mod.rs::advance_transits` makes ships pursue MOVING orbital targets at `SHIP_BASE_VELOCITY=0.05`. N112 has already transferred that separate system. Do not replace current moving-body transit with linear static ETA or `world/travel.rs` interpolation.

3. `godot/scripts/sim/phase1/n142_native_registry_travel_checks.gd` — source-derived scenarios for duplicate edges, zero-length matching, one-hop versus multihop, directed reverse edges, no gate teleport, disconnected locations, snapshot isolation, u32::MAX, built-in timing config; **authored but NOT run**.

## Почему N59/N61 не переписаны

- N4/N58: seed graph and provenance of `travel_routes`, opt-in Godot `route_graph.gd`, audit `route_graph_audit.gd`. Those are seed/audit layers, not exactly Rust `WorldRegistry::shortest_distance` or signed-safe legacy time helpers.
- N59/PR #147: fully implemented opt-in gate-aware `PathfinderCtx::find_route` with `LegKind::Travel` / `Gate`, paired gate weight **5** for ranking and nominal distance **1** on a gate leg. Gate pairs are external facility state, not part of WorldRegistry. Do not implement that Dijkstra twice.
- N60/PR #148 and N61/PR #150: route admission / one physical first-leg command in N57; intentionally no free gate transfer. N108/PR #200 owns the paid gate-jump **physical Apply**. N142 does not issue transfers, debt, docking or voyage mutations.
- Strategy N135 (and related N94) requires `registry.shortest_distance` that ignores gate teleportation. If somebody substitutes N59 shortest gate route cost, a delivery can be funded from false cheap distance. N142 restores the **distinct source-approved strategic cost layer** without competing with N59.

## Фаза 2 — точка стыковки

Read-only `Registry.load_native_snapshot` accepts normalized dictionary:
```text
{
  systems: Dictionary[system_name -> {
    db_id:int, name:string, universe_offset:[float,float], star_type:string|null
  }],
  locations: Dictionary[location_name -> {
    db_id:int, name:string, loc_type:string, celestial_body_id:int
  }],
  routes: Dictionary[from_location -> Array[{to:string,distance:int(u32)}]],
  faction_ids: Array[string]
}
```
The **exclusive Godot DB/seed adapter** constructs this snapshot from the real frozen world registry (seed or persisted runtime DB). Do not guess an external location's system from the string, a star's screen coordinate or the existence of a gate. This port deliberately rejects broken metadata, unknown route destinations and invalid u32 values at *ingest* rather than silently fabricating topology; Rust read access assumes prevalidated DB rows. Actual native `SystemInfo.star_type=None` is allowed.

`shortest_distance` returns `{found:bool,distance:int,reason:string}` so the `Option<u32>` branch can be checked without treating 0 as missing. `physical_distance_matrix` must be fed **actual available** requested pair endpoints. `Registry.snapshot/restore_snapshot` are pure canonical data; adapter save schema negotiation still needed. `_routes` order is preserved; Rust direct lookup chooses first matching edge while Dijkstra considers every matching edge.

`NativeTravel` returns `{ok:bool,reason:string,value}` with signed-64 guard; frozen Rust time uses u64, and Rust f32->integer cast at rounding borders can differ from Godot 64-bit float. Test exact boundaries in **Phase 2** (don't claim perfect runtime parity yet). Do not generate a system clock or convert world speed/ticks to a fixed gameplay calendar not in Rust.

**No cargo, stock, credits, contracts, ships or positions are modified by either script.** Runtime and parser are **not** tested: static GitHub readback/bracket balance only, so `CODE_UNVERIFIED`. Existing PRs N58–N61 remain independent drafts. Future combined application, full source mapping and headless/Windows verification belong to Phase 2. Remaining macro #10: native DB spawner/loader and persistent world/save/tracking, simulation/config beyond timing and server authoritative callbacks. Other macros still open.
