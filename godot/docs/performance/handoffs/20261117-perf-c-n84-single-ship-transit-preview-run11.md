# PERF C · N84 transit single-ship preview · 17.11.2026

CODE COMMIT c832d065a7c39dbdc34936aaedb86130d172be37: unified_ship_phase.gd introduces preview_depart. It validates fleet identity/transit/token envelope, restores only the selected ship, invokes the same ShipTransit.depart and returns a detached one-row receipt.

INTEGRATION COMMIT bcc7b3bc437d336c80a97aa717c21d252886440b: unified_ship_ai_execution.gd N84 Travel uses preview_depart instead of full-fleet depart. Authoritative depart and N39 Apply remain unchanged.

TEST COMMIT b8d918a4450c726d82ebb6a745c39003a808b137: p2_perf_c_n84_single_ship_transit_preview_oracle_20261117.gd compares receipt, token, rejection, alias, cargo, dock and invalid route against the full-fleet oracle with 100 distinct ships.

TEST EXECUTED: NOT RUN. CODE_UNVERIFIED. No measured speedup; existing 500-tick CI #43972442164 predates this patch. No 900/2600 or N38 parity claim. A remaining semantic caveat: preview validates all rows' identity/transit but ShipState.restore's full schema only for the selected row; upstream N39 schema is assumed authoritative. Targeted negative test and same-seed N38/BT/contract parity must be run before acceptance.

WHY: N84 Travel previously deep-restored every ship on every BeginTransit proposal solely to read the candidate transit receipt. New path scans fleet O(S) for token safety, deep-restores O(1) ship; no mutable alias to World. No change to AI budget, fuel, cargo or N146 Apply.

NEXT: run targeted test, compare N84 Travel callsite counts/time and ships+dock paid tick avg/p95 at tick100/600/900 with same seed; if no measurable win, revert. Coordinate with A if World snapshot dominates.
