# Astra II-C / D — Head faction capture-local facility/market roster

STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: D
START: 2026-11-18 11:42 MSK
BASE HEAD: 2bfd909c3b4607bea7478f9fdc9f773c9c2aea79
SOURCE: ASTRA_FIVE_SHIFTS_RU.md → II-C station/faction/market rosters (D).
CODE SHA: b8a82a37911cd4880bed28095b6a94bd7104a4c5
TEST SHA: 9a24d0a4ee2682deccb66db868ec7f73999435c1
TEST: NOT_RUN
PERFORMANCE: NOT_MEASURED

FILES:
- godot/scripts/sim/phase2/unified_native_hybrid_planning.gd
- godot/tests/p2_perf_d_head_capture_local_market_roster_20261118.gd

IMPLEMENTED: Head.capture now builds a per-invocation owned facility location lookup while collecting the sorted facility roster. Market selection reuses this owner lookup rather than repeatedly probing global facilities for every market. The lookup is rebuilt on every capture; no persistent stale state, same sorted market and facility ordering, same market DTO deep copies and wrong-source-owner rejection. Head decisions, search budget and source cadence unchanged. The initial idea of moving goal gating ahead of capture was deliberately NOT implemented because it could change malformed-world error precedence.

ORACLE: compares original global sorted market scan with new capture on initial state, ownership transfer, facility installation/removal, relocation error and relocation repair, plus World alias isolation. TEST NOT RUN (no Godot execution); code remains CODE_UNVERIFIED.

NEXT ASTRA II-C: measure and reduce Head's remaining repeated global contract/ship scans across factions using a version-safe per-tick faction read view, preserving requestor/status filtering and exact decisions. Run this and existing Head oracle before acceptance; same-seed early/late CPU p95 and N38 parity still pending.
