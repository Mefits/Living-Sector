> **Current A1 (2026-11-07):** `feature/genesis-station-administrator`, PR #41.
> User paused finance work in favor of station administrators. Read
> `docs/living-sector/STATION_ADMINISTRATOR.md` first. Base unified fd4e3315f5502aa4c02619b8f84629997183f422.
> One faction/location administrator, existing local population, native payroll.
> A2 is durable ship orders/dispatch. Do not resume historical service/finance plans.

> **Current F4 (2026-11-07):** `feature/genesis-construction-executor`, PR #34.
> Verified code `6470013763fc893ac502b2c2017225b56814dbda`; CI 42355317764 passed.
> Read `docs/living-sector/economy/F4_CONSTRUCTION_EXECUTOR.md` first.
> Engineering ships choose construction duty; paid work requires actual attendance.
> Service staffing remains next. Historical F3/F2 instructions follow below.

> **Current F3 (2026-11-07):** `feature/genesis-construction-labor`, PR #32.
> Verified base `1ade8339afeef8e3f351a45a256e09d999078bb4`; CI 42351760363 passed.
> Read `docs/living-sector/economy/F3_CONSTRUCTION_LABOR.md` first.
> Construction requires paid local work after materials; native population and
> economic checkpoint are reused. No automatic merges with Observer branches.
> Earlier F2/F1/S4 next-block instructions below are historical.

> **Current F2 (2026-11-07):** `feature/genesis-paid-production`, PR #29.
> Verified code `c8cdf69dd94eb42963529f5e2c404ccd984d1936`, CI 42316233684 passed.
> Read `docs/living-sector/economy/F2_PAID_PRODUCTION.md` first: paid native
> production, workforce API, old-save behavior and parallel ownership boundaries.
> Next block: construction labor, not another general economy audit.
> Earlier S4/F1 base instructions below are historical, not the current core base.

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
- Main stays close to upstream. For core continuation use the latest verified base at the top of HANDOFF.md; for independent Observer work use the pinned S1 base in PARALLEL_DEVELOPMENT.md. Never force-push, rewrite history or merge open PRs without instruction.
- Preserve the original MIT LICENSE and attribution. Avoid secrets, paid services, telemetry, unrequested publishing or unrelated refactors.
- Prefer the smallest relevant Rust check, e.g. `cargo check -p sim_core` / `cargo test -p sim_core`. Run full checks for integration changes when a tool environment is available.
- Minimize AI/Codex context cost: limit inspected files and log output to the affected modules. Do not claim tests passed if you did not run them.
- Keep simulation, presentation, persistence, and game decisions distinct. Confirm critical state transitions are applied once.
- For each substantive task, record changed files, checks performed / not performed, current risks and next action in [STATUS.md](docs/living-sector/STATUS.md). Record only explicitly agreed game rules in DESIGN.md.
- Reply in Russian by default, compactly, without repeatedly asking the owner to restate documented goals.
