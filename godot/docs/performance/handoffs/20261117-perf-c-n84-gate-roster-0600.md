# C · N84 GateJump roster (17.11.2026)

CODE COMMIT: fc71cf60e0703111bf3d996fa1016274117d267e
TEST COMMIT: 3e222470355809966fca2eac1c15d52701226a6a

Files: phase2/unified_ship_ai_execution.gd; tests/p2_perf_c_n84_gate_roster_oracle_20261117.gd.

Actual hot path: N84 _dispatch(GateJump) scans every facility for each fired ship. For G gate leaves and F facilities the scan was O(G*F). The proposal-scoped scratch dictionary now builds one gate roster O(F), then selects a location in O(1) average per GateJump. No persistence, no N38 schema, no mutation of facilities; N39/N146 still revalidate and charge gate jumps. Original facility iteration order and ambiguous-gate failure retained. This is a source-level complexity improvement, not a measured end-to-end speedup. GateJump call frequency and fraction of ships phase cost are UNKNOWN.

Regression calls the actual dispatcher with 2000 facilities/40 repeated leaves and checks original ordered oracle, World/cargo immutability, cross-proposal invalidation, ambiguous source, unpaid fee and broken reverse link.

TEST EXECUTED: NOT RUN; CODE_UNVERIFIED. No Godot runtime or same-seed profiler executed in this run. Existing CI #43972442164 predates this patch; do not cite it as acceptance. No CI triggered (checkpoint batching).

NEXT: E source-level GateJump calls/time plus N84/N14/N21 per paid tick windows 100/600/900 and structures; run targeted test, then exact N38/BT/RNG/cargo/contract parity. If GateJump fraction negligible, do not extrapolate to 392ms/tick ships cost; prioritize measured N153 contract or N84 Travel sites.
