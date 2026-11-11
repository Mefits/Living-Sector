# AGENTS — scoped Godot port rules

Read [NIGHT_SHIFT_QUEUE_RU.md](docs/NIGHT_SHIFT_QUEUE_RU.md) and [CLAIM_PROTOCOL_RU.md](docs/nightshift/CLAIM_PROTOCOL_RU.md) FIRST.

- **Shared coordination branch:** `feature/godot-nightshift-20261112`. Two chats may work at the same time. To start an Nx block, create **new** `godot/docs/nightshift/claims/Nx.json` there with `IN_PROGRESS`, owner/run ID/time before editing Godot code. On conflict, don't claim or modify that block; move on. Update shared table and log right away. Work on a **separate code branch** with a PR. Do not touch someone else's claim or branch.
- **Source of truth:** frozen Rust 0.6.7 branch `archive/rust-galaxy-067-reference`, [inventory](docs/SOURCE_INVENTORY.json) and [roadmap](docs/MIGRATION_ROADMAP_RU.md). Do not fabricate resources, deliveries, prices, AI results, or mark mere design as implemented.
- **Optimal method:** examine official Godot built-ins and mature gamedev references per [tooling](docs/GODOT_TOOLING_DECISIONS_RU.md) before a new subsystem. Prefer built-in classes and thin data-driven models; addon only after proven compatible/license-safe, and only when it actually saves work.
- **Tick design:** common discrete `SimTick`, separate in-game calendar and wall-clock TPS, cadence + deterministic targeted events, visual interpolation distinct from physical transactions. 1 game hour/tick is a **candidate**. Existing 8 TPS/0.25 from upstream Rust is a parity baseline, not a performance mandate.
- **Limits:** complete 3–5 meaningful related tasks per iteration, test only relevant small scenarios, no lengthy Rust compilation or paid cloud Actions, no merging to stable/main or force push. Don't copy unreviewed sound/fonts.
- **Honest progress:** if Godot runtime absent, static checks only = `CODE_UNVERIFIED`. Update tracker/claims/run log with evidence. Always report **Текущее состояние**.
