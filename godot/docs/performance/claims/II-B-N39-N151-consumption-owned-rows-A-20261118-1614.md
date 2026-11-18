# Astra II-B — N39 N151 paid consumption owned rows

STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: A
START: 2026-11-18 16:14 MSK
BASE HEAD: e616f557bfc7ae05fb364accd98d22dd09bd13f3
SOURCE: ASTRA_FIVE_SHIFTS_RU.md — A World snapshots / bounded owned writes / full Schema oracle
SCOPE: `godot/scripts/sim/phase1/n39_native_world_production.gd`, `godot/tests/p2_perf_a_n151_consumption_owned_rows.gd`
TASK: Replace deep clones of all populations/facilities/markets on paid N151 consumption with detached registry and touched-row copies, covering successive tickets, market history and sentiment, rejected tickets and source full Schema/N9 oracle.
TEST: positive multi-ticket same seller/market, negative failed preflight, no mutable aliases, full deep-copy comparator. No Actions.

## Result 2026-11-18 16:14 MSK
CODE SHA: d5c107a9d9c66e558e3ca30b21e6ba1e724698c1
TEST SHA: d60b740dd845f9be296aaf9f8ff59012d0ea4a2a
FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n151_consumption_owned_rows.gd
Implemented: real apply_population_phase N151 paid tickets now use shallow registries and lazy deep row detachment for populations, seller facilities and markets. Repeated purchases reuse detached rows; rolling consumption windows and sentiment-only changes detach on difference. All source preflight, ledger fork, full Schema and account oracle, atomic publish remain unchanged.
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED. Test models paid multi-ticket shared seller/market, full deep oracle, negative rejected late ticket, nested aliases and sentiment-only change. Real production parity/N38 restart still required.
NEXT ASTRA II-B: audit remaining N39 L129 repeated snapshot callers and isolate bounded source stages, with full Schema/rollback and exact paid-tick parity; coordinate ship/dock caller with C.
