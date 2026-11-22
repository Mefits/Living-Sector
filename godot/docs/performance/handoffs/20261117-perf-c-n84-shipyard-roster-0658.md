# PERF C · 17.11.2026 · N84 shipyard location scan

CODE SHA: 75e1ccdbd58b9981c63b4c32c58c8bacaaaf1eca
TEST SHA: 562b3c225398c4f45cf1dc55f60cbd9996d41853
FILES: godot/scripts/sim/phase2/unified_ship_ai_execution.gd; godot/tests/p2_perf_c_n84_shipyard_roster_oracle_20261117.gd

N84 DockAtShipyard previously scanned all growing facilities for each eligible ship. It now lazily builds the read-only eligible shipyard location roster once per N84 propose call. N39 facility mutations occur after this proposal, and the roster is discarded between paid ticks. The original abandoned/type/location predicate and dock commands remain unchanged. No N39/N9/N158 edits.

TEST EXECUTED: NOT RUN. CODE_UNVERIFIED. No measured speedup; frequency of N108 leaves in tick600/900 unknown. The negative oracle covers 2000 facilities, abandoned yards, duplicate locations and cross-tick ownership of the roster. Full N38/BT/RNG/paid contract parity NOT RUN.

NEXT: run targeted test in existing bounded checkpoint; use site-level call counts/time for N84 DockAtShipyard vs N84 Travel/N153 and same-seed tick100/600/900, then prioritize measured dominant path. Do not repeat 99ab25e9/1676db61.
