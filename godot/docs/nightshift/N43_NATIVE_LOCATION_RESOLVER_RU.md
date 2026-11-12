# N43 — native world-space position resolver and moving ship targets

Дата: 12.11.2026. Статус: **CODE_UNVERIFIED / STATIC_CHECKED**.
Claim: `feature/godot-nightshift-20261112:godot/docs/nightshift/claims/N43.json`.
**Stacked dependency:** PR #130 (N40) is the base, PR #128 is its parent.
**No changes** to occupied N39 production, verified P1 checkpoint, main, stable, or frozen Rust.

## Implemented

1. `scripts/sim/ships/native_location_resolver.gd`: reads original `worlds[].system.universe_offset`, celestial `orbit_radius` and *current* `WorldModel.orbital_snapshot()`; body center = `offset + radius × (cos(angle), sin(angle))`.
2. Facility locations with docking capacity follow the **frozen Rust station orbit** around the body center, radius `0.55`, period `8000` native units; initial phase uses the byte-accurate FNV-1a u32 hash of the location name. All modules with one location share the same anchor. Native navigation/mining sites follow their body's center without a fabricated station offset.
3. Fails closed for malformed orbit radius/system offset, missing referenced body, cross-system/ambiguous names, nonfinite elapsed native time, unknown old-save time origin, mismatched seed fingerprint, or unavailable orbital state. Route-only IDs without a body mapping are not assigned fictional positions; no route-distance-as-position or UI pixels.
4. `scripts/sim/ship_tick_runner.gd` from N40 receives **opt-in** `configure_fleet_from_native` that takes the real seed and dynamic resolver. It still **requires separately sourced real fuel/cargo**. At the `ships` phase, after advancing `bodies`, it refreshes coordinates using `calendar.native_time_units + native_delta` and N14 pursues the *current* destination position. Invalid geometry suspends the fleet rather than continuing with stale positions.
5. `tests/n43_native_location_resolver_check.gd`: FNV phase `earth-station=106°`, native Sol station radius, nav center at `near-earth` orbit, validation/reject behavior, moving locations after orbital step, optional N40 ship flight and fuel, fail-closed save. Numeric fuel `12` in the test is explicitly a **test fixture**, NOT native ship stock.

## Rust sources examined

- `native/crates/sim_core/src/agents/celestial_body.rs`: `BodyOrbit::position()`, `universe_position()`.
- `native/crates/sim_core/src/agents/facility/components.rs`: `FACILITY_ORBIT_RADIUS=0.55`, `FACILITY_ORBIT_PERIOD=8000`, `FacilityOrbit::advance`, FNV-1a `facility_orbit_initial_angle`, `facility_orbit_position`.
- `native/crates/sim_core/src/agents/ship/mod.rs`: live `location_to_pos` matches facilities with `docking_capacity>0` to moving station orbits and body-linked nav sites to body center; ship transit chases current target.

## Checks actually completed

- GitHub source verified N43 changes are separate from N39; native Sol/Nadir JSON parsed.
- Seed example: Sol's `earth-station` has 5 modules and directed `earth-station→mine-near-earth`, `mine-near-earth` belongs to `near-earth`; Nadir's `pirate-outpost` also has 5 co-located facilities.
- Independent integer FNV-1a check: `earth-station=106°`, `pirate-outpost=331°`.
- Static string/interface checks confirm dynamic refresh at ships phase, N40 save guard, and tests covering moving targets.
- **Godot 4.7 Runtime absent in agent environment, headless tests NOT run.** No gameplay VERIFIED/Rust full parity claim.

## Next integration boundary

N40 + N43 remain stacked experimental modules, not automatically part of the user's already-working P1 UI. N39 has a different owner and may create a production-specific TickRunner: next integrator must consolidate **one** authoritative `TickRunner` supporting `bodies/ships/facilities`, with actual state sources and atomic snapshot/restore, without double-advancing worlds or losing deterministic events.

Run short N40 and N43 headless tests internally before integration. **Do not ask the user to download any small patch**; next user-facing build only after a larger block batch.
