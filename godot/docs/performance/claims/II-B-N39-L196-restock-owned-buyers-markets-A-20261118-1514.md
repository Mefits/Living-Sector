# Astra II-B — N39 L196 N130 restock owned rows
STATUS: IN_PROGRESS
OWNER: A
START: 2026-11-18 15:14 Europe/Moscow
BASE HEAD: 321ebb97567f5034b3bef110ba4609de7291fabd
ASTRA: II-B bounded owned write sets, local validators, versions & delta; N39 L196
INTENDED FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n39_l196_restock_owned_rows.gd
GOAL: Detach only N130 eligible buyer/seller facility rows and their market rows, after N156 changes, before restock; retain full Schema/N9 oracle, rollback and alias isolation; positive/negative exact old deep-copy oracle.
TEST: NOT_RUN
