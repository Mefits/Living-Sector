# PERF C — N84 single-use BeginTransit preview (17.11.2026)

CODE COMMIT: 9e8aaa0ee35eb629b7d219f95681cf2950efd68f
TEST COMMIT: c67b2c7ef54441d595e12940b76fff79290bd48c
FILES: godot/scripts/sim/phase2/unified_ship_ai_execution.gd; godot/tests/p2_perf_c_n84_single_departure_preview_regression.gd

N84 Travel already called ShipPhase.preview_depart() while producing a BeginTransit command, then called it again while consuming the same command. Each invocation scans all growing ship rows for token/identity validation and restores a candidate. The proposal-local dock_ticks scratch now stores the first validated preview and consumes it once after Bt.tick, guarded by ship ID, destination, and current ship_next_token. Mismatches fall back to the previous authoritative preview call. Existing receipt arrival/from parity checks and N39 command application remain in place. This avoids one repeated fleet scan and candidate restore per successfully emitted BeginTransit leaf; not a claimed resolution of the dominant dock_queue cost.

TEST EXECUTED: NOT RUN (Godot runtime not used). Added structural negative regression covering one-time consumption, stale ship/destination/token fallback and receipt checks. This is NOT an independent behavioral oracle; must add exact old/new runtime oracle for multiple commands, failed BT leaves, paid cargo and N38 restart. CODE_UNVERIFIED. No measured CPU savings. Previous CI #43972442164 predates this commit.

NEXT: source-level count/time of N84 BeginTransit preview and N84 dock/contract scans on paid ticks 100/600/900; verify same-seed BT/RNG/contract/cargo/N38 parity, compare before/after phase p95, and prioritize the dominant measured growing site. No edits to N9/N39/N158 or Astra fixes.
