# Living Sector P2 — N91 same-system remote construction engineer (14.11.2026)

Working branch: `integration/godot-phase2-unified-20261113`; [Draft PR #249](https://github.com/Mefits/Living-Sector/pull/249). Starting HEAD `72a81ae`.

## Integrated in this work block
1. `unified_n91_construction_dispatch.gd`: the original N91/Executor.choose keeps its source same-system restriction and local-first preference. Full preflight uses native N4 directed shortest_path, each actual N4 edge, dynamic N43 orbital Vector2 positions, canonical ship stats/fuel, and source N14 per-leg consumption. Unreachable, cross-system, empty, or unaffordable paths are rejected; no fake dispatch.
2. A remote N91 task persists an N84 BT sequence `ConstructionUndock? → Travel (each physical leg) → ConstructionDock → Construct`. A local task retains `ConstructionDock → Construct`. No separate GOAP, ledger or world created; native N84/N146/N14 performs travel, and the original N21 dock registry applies real requests.
3. `n39_native_world_production.gd` now independently regenerates the full plan from actual source World, source N4 graph, native N43 coordinates and fuel before accepting a real qualified faction engineer. Route and BT mismatches are fatal. The pre-existing N15/N104/N9 source delivery receipt validation still gates the site.
4. `unified_ship_ai_execution.gd`: N84 authenticates remote construction Travel site/faction, dispatches site-specific N21 origin undock; it never grants money, fuel, labor, cargo or movement except through N146/N14 Apply.
5. `n158_production_runtime.gd`: factions supply the real graph, N43 positions and tick scale to N91 selector and N39 recheck; ships distinguish remote project undock from final paid site dock, with real origin N21 dock proof.
6. Extended the existing `p2_gate4_native_construction_check.gd`, NOT a new CI workflow. It uses the frozen directed Sol edge `earth-station → mine-near-earth` and a detached PLAN-ONLY synthetic site/market, checks route BT JSON survival, mandatory undock, a real isolated N14 departure, fuel denial and no invented reverse edge. It still checks N134 head permission, fake-material rejection, N9 conservation and N38 disk restore on canonical seed.

## Truth and limitations
- `CODE_WIRED_STATIC_PASS` on file brackets/strings and known preloads; NO available Godot executable, **GODOT RUN NOT EXECUTED**, **GitHub Actions: 0**. No claim of end-to-end paid construction completion or CI parity.
- The frozen eight-system seed has only three existing stations/markets and T1 production slots are occupied. Directional routes have `earth-station → mine` but not necessarily reverse edges. Hence this adapter does **not** fabricate a reachable funded remote construction site at startup.
- The end-to-end gate still needs actual N147 colony/free site, N154 paid material delivery, N91 autonomous flight, N21 dock, N141 paid labor and T1 creation in ONE Godot run, plus N38 save/load mid-flight; only after that call it VERIFIED.
- No changes to GUI, balance parameters, N100 Hybrid, Rust source, or original research. The UI manual fleet controls remain hidden.
- Next major work after this block: N147 native colonization/migration + new legitimate construction capacity and colony routes, then one coordinated full runtime verification (avoid repeat Actions).

Lease: `godot/docs/phase2/leases/20261114-interactive-n91-remote-engineer-route-1127.json`, to be released. No force-push and no source PR fan-out.
