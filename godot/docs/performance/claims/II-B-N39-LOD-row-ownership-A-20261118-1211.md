# Astra II-B — N39 L196/N18 to LOD row ownership
STATUS: IN_PROGRESS
OWNER: A
START: 2026-11-18 12:11 Europe/Moscow
BASE HEAD: 3bc3f1cdc795ab0a172b94066f355bd075dc33e5
ASTRA: II-B bounded owned write sets / rollback / alias isolation. Fix mutable facility row alias at N18 staffing → LOD advance, avoid broad copies for LOD-only changes.
INTENDED FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n39_lod_owned_rows.gd
EXPECTED: old vs optimized LOD state, no-op and due ticks, negative alias regression, full Schema oracle; runtime NOT_RUN without Godot.
