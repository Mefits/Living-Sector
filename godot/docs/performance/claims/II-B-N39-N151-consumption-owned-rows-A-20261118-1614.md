# Astra II-B — N39 N151 paid consumption owned rows

STATUS: IN_PROGRESS
OWNER: A
START: 2026-11-18 16:14 MSK
BASE HEAD: e616f557bfc7ae05fb364accd98d22dd09bd13f3
SOURCE: ASTRA_FIVE_SHIFTS_RU.md — A World snapshots / bounded owned writes / full Schema oracle
SCOPE: `godot/scripts/sim/phase1/n39_native_world_production.gd`, `godot/tests/p2_perf_a_n151_consumption_owned_rows.gd`
TASK: Replace deep clones of all populations/facilities/markets on paid N151 consumption with detached registry and touched-row copies, covering successive tickets, market history and sentiment, rejected tickets and source full Schema/N9 oracle.
TEST: positive multi-ticket same seller/market, negative failed preflight, no mutable aliases, full deep-copy comparator. No Actions.
