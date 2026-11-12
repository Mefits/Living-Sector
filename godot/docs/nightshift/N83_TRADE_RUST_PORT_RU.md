# N83 — Native ship remembered-price trade selector

Rust source (read-only): `archive/rust-galaxy-067-reference/native/crates/sim_core/src/agents/ship/behavior.rs; native/crates/sim_core/src/agents/ship/mod.rs; native/crates/sim_core/src/agents/faction_relations.rs`.

Freshness half-life 1500, floor .10, 50-unit lot, 10% minimum margin, route-performance penalty after 3 attempts, ownership 1.25, full-lot buyer solvency gate, median fallback. Output intent only. Caller must provide commerce authorization and live ledger; actual stock/credit/docking revalidation deferred.

Stage: **CODE_UNVERIFIED**. Minimal static review only; no Godot runtime, no integration into P1, no claim of Rust-parity at runtime. Independent component branch from integration HEAD `1e4a1e9f34fff7313ce176107890ecdbe25fc85a`.

Next phase: assemble interfaces into the authoritative tick and transaction executor after all Rust components are ported; test as one combined Godot project.
