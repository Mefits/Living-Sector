# Astra II-A · N9 bounded receipt-order tail ownership
STATUS: IN_PROGRESS
OWNER: B
START: 2026-11-18 14:20 Europe/Moscow
BASE_SHA: 47323f5b42b632c560bb63b7d005c5732ba6f73f
SOURCE: ASTRA_FIVE_SHIFTS_RU.md / II-A append-only receipt history, owned transaction overlays
FILES: godot/scripts/sim/economy/credit_ledger.gd; godot/tests/p2_perf_b_order_tail_owned.gd
GOAL: Eliminate redundant repeated COW copies of the bounded receipt order tail between forks, preserve immutable historical order across parent/child, snapshot and restore. Verify same oracle order, alias isolation, duplicate/failed transaction behavior.
TEST: targeted positive and negative regression; NOT_RUN until Godot runtime.
