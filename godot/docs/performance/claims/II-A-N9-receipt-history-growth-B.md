# Astra II-A — N9 receipt history growth / paid path

STATUS: IN_PROGRESS
OWNER: B
STARTED: 2026-11-18 10:17 MSK
BASE_SHA: 0719842b7526cd91f4decf2bd1f30fe0563c4ca8
SOURCE: ASTRA_FIVE_SHIFTS_RU.md, II-A and B — N9 Ledger append-only history, stage overlays, remaining deep copies.
INTENDED_FILES: godot/scripts/sim/economy/credit_ledger.gd; godot/tests/p2_perf_b_*.gd
EXPECTED_CHECK: targeted negative receipt immutability/idempotency and old-vs-new ledger snapshot; Godot runtime NOT RUN if unavailable.
SCOPE: one independently safe B-owned paid-receipt hotpath block; do not repeat WeakRef or N158 projections.
