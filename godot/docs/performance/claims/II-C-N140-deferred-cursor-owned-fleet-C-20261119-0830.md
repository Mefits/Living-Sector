# II-C N140 cursor staging and deferred fleet ownership
STATUS: IN_PROGRESS
OWNER: C
START: 2026-11-19 08:30 Europe/Moscow
BASE_SHA: d17865d88e759249d15851ed0d3bd4755cf94b77
ASTRA: II-C ship/contract/dock/route caches; remove repeated N140 ship/agent fleet copies with read-only/owned boundary; preserve source cadence.
SCOPE: godot/scripts/sim/phase2/unified_n140_ship_lod_phase.gd; godot/tests/p2_perf_c_n140_deferred_fleet_ownership.gd
PLAN: Stage validated N140 cursor results without deep-copying cargo/BT before full gate validation; detach full fleet exactly once after successful cursor stage; avoid location projection on non-recompute ticks; retain fired order and changed semantics.
ORACLE: old direct SourceLod set_divisor/try_fire, mixed no-LOD/LOD, sleeping, bad cursor, missing position, source immutability and changed/fired metadata. TEST_NOT_RUN until manual Godot.
NEXT: paid 24/100/500 BT/cargo/route parity.
