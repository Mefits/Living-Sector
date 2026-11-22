# PERF D — Head ContractBoard status prefilter (17.11.2026)

CODE COMMIT: 5cfef8fd38e4756b4c8c6dbab3189c0b96315647
TEST COMMIT: 2b97fa8396f51ad0ee48a37f0491b35a0f376dd2

Files: phase2/unified_native_hybrid_planning.gd; tests/p2_perf_d_head_contract_owner_status_20261117.gd.

Head.capture scans all contracts per faction. The hot loop now checks requestor/faction ownership before normalizing status for unrelated rows; retained commitments still apply the exact original paid/expired filter and sorted-ID ordering. No indexing, caching, new World owner, or search budget changes. Negative test compares an independent old-order oracle with 240 mixed-owner/status contracts, sponsor-only contract and ownership mutation.

TEST EXECUTED: NOT RUN; CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No same-seed timing, p95, or late-tick speedup claim. CI deliberately not triggered (shared checkpoint policy).

NEXT: run targeted test in existing bounded checkpoint, profile Head.capture contract scan versus N150 market work at early/late same seed; consider residual N152 deep-copy only with A/B ownership agreement. Existing 500-tick PASS predates this patch. No N9/N39/N158 edits.
