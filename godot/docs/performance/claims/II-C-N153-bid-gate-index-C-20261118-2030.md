# II-C — N153 proposal-local bidder gate index
STATUS: IN_PROGRESS
OWNER: C
DATE: 2026-11-18 20:30 MSK
BASE_SHA: 2878d1c38967e8d8ef9446f08842d2cf6127278c
ASTRA: II-C ship/contract/dock/route caches; indexed eligible ships & available contracts with deterministic invalidation and exact rejection/tie-break parity.
SCOPE: N153 repeated per-offer ship faction, outlaw and reputation posture gates; preserve per-offer blocker counts and per-ship bid order.
INTENDED_FILES: godot/scripts/sim/phase2/unified_n153_contract_dispatch.gd; godot/tests/p2_perf_c_n153_bid_gate_index.gd
EXPECTED_TEST: cached-vs-uncached independent oracle across multiple offers, missing faction, outlaw, reputation, assignment, mutation between calls, equal profit and source rejection ordering.
RISKS: no persistent cache, no skipped native N153/BT decisions, no changed blocker counts.
