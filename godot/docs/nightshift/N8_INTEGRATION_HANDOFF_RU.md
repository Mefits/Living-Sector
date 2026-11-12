# N8 — integration acceptance boundary (CODE_UNVERIFIED)

Source: frozen Rust `native/crates/sim_server/src/engine.rs` facility phase and `native/crates/sim_core/src/agents/facility/workforce.rs`; existing N5/N9/N11/N6 ports.

This is an explicit, **local self-owned** integration of existing production, warehouse preflight and balanced payroll ledger. No invisible goods or cash: each successful shift consumes real input stock, produces recipe outputs and transfers wages exactly once. Facilities execute in stable ID order. A location-level labor budget avoids assigning the same available workforce twice; caller supplies actual population and workers. Failed facilities do not spend wages or create stock. Full coordinator checkpoint includes stock, ledger receipts and production idempotence; restoration is staged.

**Important limitations:** no connection to the global TickRunner's facilities phase yet, no cross-owner processing fees, workforce persistence outside the coordinator, construction, market orders or physical cargo integration. The 60% labor cap and 1 CR/worker are from the Rust baseline; the location budget is a conservative integration guard, not a replacement for native worker allocation.

Godot-native choice: RefCounted and Dictionary, deterministic sort, no per-facility Node or external ECS. GUT is deferred until Godot runtime acceptance. For thousands of facilities this should be profiled before choosing a packed-array implementation. Test checks shared labor, conservation, wages, replay, atomic restore, insufficient funds.

Run: `godot --headless --path godot --script res://tests/n8_integration_check.gd`.

Stack: N8 PR based on N6 PR #100, itself based on N9 #96 and N5 #93, with N11 #94 ledger copied. Review stacked diffs before merge. **No runtime execution performed; CODE_UNVERIFIED.**
