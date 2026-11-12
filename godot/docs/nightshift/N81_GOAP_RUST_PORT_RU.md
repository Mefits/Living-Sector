# N81 — Native GOAP cost-weighted Dijkstra

Rust source (read-only): `archive/rust-galaxy-067-reference/native/crates/sim_core/src/ai/planner.rs`.

Pure abstract state, native 6 operator catalogues, source-backed preconditions/effects, fuel buckets, bounded Dijkstra and ShipAction-shaped intents. No actual execution, route_actions, payments or docking side effects. Integration must validate against live state.

Stage: **CODE_UNVERIFIED**. Minimal static review only; no Godot runtime, no integration into P1, no claim of Rust-parity at runtime. Independent component branch from integration HEAD `1e4a1e9f34fff7313ce176107890ecdbe25fc85a`.

Next phase: assemble interfaces into the authoritative tick and transaction executor after all Rust components are ported; test as one combined Godot project.
