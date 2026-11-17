# PERF D · 17.11.2026 · Head requestor alias

Code final: `77e993d262ac1cde2d2c0af482a40bc4a385b1b5` (intermediate `d60f569d` superseded in same file). Test: `1ab45f390f74f314c258e62f204060fc8997869d`.

Files: `godot/scripts/sim/phase2/unified_native_hybrid_planning.gd`; `godot/tests/p2_perf_d_head_requestor_alias_20261117.gd`.

The actual Head.capture ContractBoard scan previously concatenated `"faction/" + faction` for every scanned contract. Hoisted immutable alias once per capture. No status/owner/tie-break/SEARCH_BUDGET/World mutation changes. Negative test covers own, sponsored, lookalike, paid, expired, ownership transfer, snapshot isolation.

**CODE_UNVERIFIED / TEST_ADDED_NOT_RUN**: no Godot runtime invoked, no measured performance claim. Expected saving is minor and proportional to total contracts scanned; not proof of solving late tick growth. No new CI triggered. Previous 500-tick PASS #43972442164 does not validate this patch.

Next: profile N150 market DTO/copy and Head capture per-site calls and CPU in same-seed early/late windows; prioritize proven large allocation over more small scan edits. N152 ContractBoard ownership requires A/B coordination. Do not duplicate `99ab25e9`/`1676db61`.
