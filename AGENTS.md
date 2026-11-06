> **Current economic block F1 (2026-11-06):** `feature/genesis-economy-foundation`, PR #25,
> based on S7 `31f29e719e8d734e6780e331acfe732cd3098c62`.
> Read `docs/living-sector/economy/F1_ECONOMY_FOUNDATION.md` and the latest STATUS
> first. The user's new economy brief supersedes the old no-issuance restriction.
> Workforce/payroll/production is the next block; do not call F1 a completed economy.

> **Current core handoff (2026-11-06, Astra → Sol):** read [HANDOFF.md](docs/living-sector/HANDOFF.md) first. Core development continues from S4, `feature/genesis-strategy-coordination` / PR #20, pinned base `a22e61a7df3d415a7c10a42dacce6f87d27301cb`. S1 remains the separately pinned Observer integration base; it is NOT the latest core. Work in blocks of 5–10 related tasks, one branch/PR per block, focused checks and milestone integration checks. No automatic merges or history rewrites. Next block: real autonomous execution and restart, not a fresh economy audit.

# Working rules for AI contributors — Living Sector

This repository is a **fork of [Kalcode/spaceprojectsim](https://github.com/Kalcode/spaceprojectsim)**. Our current project name is **Living Sector**. Work with the actual Rust/Bevy code; an older Godot prototype is *historical concept material*, **not** this repository's application architecture.

## Read before changing anything

1. [docs/living-sector/HANDOFF.md](docs/living-sector/HANDOFF.md) — current base, architecture boundaries, verified results and next block.
2. The current section of [STATUS.md](docs/living-sector/STATUS.md), plus [PARALLEL_DEVELOPMENT.md](docs/living-sector/PARALLEL_DEVELOPMENT.md) when changing API/ownership boundaries.
3. Relevant source files and their tests. Read VISION/DESIGN/ARCHITECTURE, upstream CLAUDE.md and CONTRIBUTING.md as needed for the affected area; do not repeat completed audits or reread the entire history by default.

## Rules

- Do not mistake inspiration, a discussion example, an engineering proposal, and an implemented feature.
- **Do not replace the existing Rust/Bevy simulator with Godot/C#/TypeScript.** The possibility of a future personal-scale mode does not authorize a rewrite.
- Do not start implementing features or updating upstream code without a concrete task.
- Preserve compatibility with the original fork when reasonable; prefer isolated modules, clear interfaces, and small changes.
- Main stays close to upstream. For core continuation use the pinned S4 base in HANDOFF.md; for independent Observer work use the pinned S1 base in PARALLEL_DEVELOPMENT.md. Never force-push, rewrite history or merge open PRs without instruction.
- Preserve the original MIT LICENSE and attribution. Avoid secrets, paid services, telemetry, unrequested publishing or unrelated refactors.
- Prefer the smallest relevant Rust check, e.g. `cargo check -p sim_core` / `cargo test -p sim_core`. Run full checks for integration changes when a tool environment is available.
- Minimize AI/Codex context cost: limit inspected files and log output to the affected modules. Do not claim tests passed if you did not run them.
- Keep simulation, presentation, persistence, and game decisions distinct. Confirm critical state transitions are applied once.
- For each substantive task, record changed files, checks performed / not performed, current risks and next action in [STATUS.md](docs/living-sector/STATUS.md). Record only explicitly agreed game rules in DESIGN.md.
- Reply in Russian by default, compactly, without repeatedly asking the owner to restate documented goals.
