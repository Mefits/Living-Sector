# II-C N14/N140 validated borrowed fleet — C
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: C
START: 2026-11-19 14:34 MSK
BASE SHA: b6265a71e4a6b65755dd61a56c8e38200f198b80
ASTRA: II-C ship/contract/dock/route caches; remove redundant N14/N140 ship deep copies while retaining exact ShipState restore validation.
INTENDED FILES: godot/scripts/sim/ship_state.gd; godot/scripts/sim/phase2/unified_ship_phase.gd; godot/tests/p2_perf_c_n14_borrowed_restore_oracle.gd
EXPECTED: validated borrowed records only for advance preflight, N140 detached ownership before motion, depart remains deep-owned; positive/negative oracle incl invalid cargo/fitting/transit and alias checks.
TEST: NOT_RUN

CODE SHA: 87a62c1f3f6534101a3836347fb5acce3d077ed2 (also 8fe43caf0bf3cba239d19d43f1fe2f51af411d2f)
TEST SHA: 88728c59e3307dd6c0a363285082ba433e6c2c4e
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED
SOURCE: ShipState.restore(records, detach=true) validates both modes with unchanged rules; ShipPhase._load(world, detach=true) retains owned default for depart/external calls. ShipPhase.advance borrows only read-only validated preflight rows and replaces them with N140.stage's deep-detached gate fleet before ShipTransit.advance. This eliminates one full cargo/BT/memory deep clone on every paid ship tick without moving authority from N39.
REGRESSION: owned-vs-borrowed validation/token oracle, 24-ship N140 ownership, idle paid tick, malformed cargo/fuel/crew/identity/transit/cursor, original World isolation.
RISK: Godot runtime/parser and exact paid moving N14 replay not yet run; benchmark required to quantify benefit.
NEXT ASTRA II-C: active paid 24/100/500 ship+contract+dock fixtures and N84/N153 BT/cargo/fuel/route/N38 parity; only then consider further cache indices.
