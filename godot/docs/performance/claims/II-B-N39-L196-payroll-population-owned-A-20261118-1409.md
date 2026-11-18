# Astra II-B · N39 L196 payroll population ownership

STATUS: IN_PROGRESS
OWNER: A
DATE: 2026-11-18 14:09 Europe/Moscow
BASE HEAD: e9b03f1ac5377c4ef308883e2d75c786183e9980
TASK: Astra II-B L196 real paid N156 repair: replace unconditional full population deep copy with scoped owned household rows while preserving payroll assignment, blocked repair, rollback, Schema/N9 oracle.
INTENDED FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n39_l196_payroll_population_rows.gd
EXPECTED CHECK: same-seed full-copy oracle, paid and blocked payroll, multiple candidate factions/locations, nested alias isolation, full Schema accounts, no CI.
