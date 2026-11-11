> **Living Sector / Genesis handoff (2026-11-05):** This README describes the **upstream 3D simulator**, not the current headless Genesis build. For the active development branch `feature/genesis-faction-economy` and handoff to Astra, start at **[docs/living-sector/ASTRA_START_HERE.md](docs/living-sector/ASTRA_START_HERE.md)**. The polished 2D Observer 0.14 is currently distributed separately in a Windows ZIP and is not yet committed as frontend source on that branch.

<div align="center">

# 🚀 The Space Project

**A self-running space-economy simulator, in Rust + Bevy.**

Hundreds of autonomous ships trade, mine, haul cargo, take out contracts,
run out of fuel, and occasionally go bankrupt across a living solar
economy — markets find their own prices, factions tax and subsidize,
populations migrate when they're unhappy, and abandoned stations rot.
It all runs in one native binary with no runtime dependencies.

<br>

[![License: MIT](https://img.shields.io/badge/license-MIT-3b82f6?style=for-the-badge)](LICENSE)
[![Rust](https://img.shields.io/badge/Rust-2021-orange?style=for-the-badge&logo=rust&logoColor=white)](https://www.rust-lang.org/)
[![Bevy 0.18](https://img.shields.io/badge/Bevy-0.18-cd6a51?style=for-the-badge)](https://bevyengine.org/)
[![Platforms](https://img.shields.io/badge/platform-macOS%20%7C%20Windows%20%7C%20Linux-8b5cf6?style=for-the-badge)](#building--packaging)
[![Single binary](https://img.shields.io/badge/deps-single%20binary%2C%20no%20runtime-22c55e?style=for-the-badge)](#quick-start)
[![Status](https://img.shields.io/badge/status-experimental-eab308?style=for-the-badge)](#-a-note-on-where-this-is-going)

<br>

![The Space Project — inner solar system with live ship trails](docs/screenshots/space_project_sim_1.png)

</div>

---

## What is this?

The Space Project is an **agent-driven economic simulation** wrapped in a
native 3D client. There's no scripted storyline and no player objective —
you're an observer (and god-mode admin) watching an economy run itself.

Every ship is an autonomous agent with its own credits, crew, fuel, cargo
hold, and a **GOAP planner** that decides what to do next: chase the
highest-margin trade route, accept a delivery contract, seek out a
shipyard to retrofit, or dock and let its crew rest before morale
collapses. Facilities run production recipes, degrade and self-repair,
level up, and get abandoned when they go broke. Factions collect taxes
and post subsidies. Populations consume food, produce labor, and pack up
and leave when sentiment craters. Markets price everything off a coverage
model with shortage urgency multipliers — no fixed prices anywhere.

It started as an Elixir/Phoenix prototype and was rewritten in Rust
because the BEAM scheduler struggled on Windows gaming PCs. The engine
(`sim_core`) is pure, synchronous, IO-free Rust; the Bevy client embeds
it directly as a library, so the simulation and the renderer share the
same ECS world with zero marshalling between them.

**Scale today:** ~485 live agents (282 ships · 93 facilities · 27
populations · 8 factions · 60 celestial bodies), ticking at p50 ≈ 10–20 ms
inside a 125 ms budget. The architecture is built to push toward 100k+.

---

## 🌌 A note on where this is going

> **Nowhere, on its own — and that's kind of the point.**
>
> This started as a fun idea: a from-scratch space economy that actually
> simulates itself instead of faking it. It grew *way* past what I
> expected, mostly in late-night sessions pairing with Claude. But I'm
> not pretending it's a game with a roadmap, and I'm not actively pushing
> it toward "shippable."
>
> I'm putting it out under MIT because the bones are genuinely good and I'd
> rather someone do something with it than let it sit in a private repo.
> So: **fork it, gut it, rename it, bolt a game on top of it, rip the
> economy engine out and use it somewhere else entirely.** Build the thing
> I didn't.
>
> PRs and issues are welcome and I'll look at them, but I can't promise a
> cadence. If you want to take it somewhere real, see
> [CONTRIBUTING.md](CONTRIBUTING.md) — there's a "directions you could
> take this" section written exactly for you.

---

## Screenshots

<table>
  <tr>
    <td width="50%"><img src="docs/screenshots/space_project_sim_2.png" alt="Title screen"><br><sub><b>Title screen</b> — start a fresh universe or load a save.</sub></td>
    <td width="50%"><img src="docs/screenshots/space_project_sim_3.png" alt="System overview map"><br><sub><b>System overview</b> — orbital rings across Sol and neighboring systems.</sub></td>
  </tr>
  <tr>
    <td width="50%"><img src="docs/screenshots/space_project_sim_4.png" alt="Asteroid mining cluster"><br><sub><b>Mining cluster</b> — tumbling asteroids, foundries, and ship trails.</sub></td>
    <td width="50%"><img src="docs/screenshots/space_project_sim_5.png" alt="Outer systems with nebulae"><br><sub><b>Outer reaches</b> — distant belts and stations against nebula backdrops.</sub></td>
  </tr>
  <tr>
    <td width="50%"><img src="docs/screenshots/space_project_sim_6.png" alt="Factions and contracts inspector panels"><br><sub><b>Live inspector</b> — faction ledger, relations matrix, full contract board.</sub></td>
    <td width="50%"><img src="docs/screenshots/space_project_sim_7.png" alt="Live events stream"><br><sub><b>Events stream</b> — market crises, dockings, deliveries, tick by tick.</sub></td>
  </tr>
</table>

---

## What it simulates

| System | What happens |
|---|---|
| **Ship AI (GOAP)** | A forward planner scores every goal — trade, deliver, refuel, retrofit, rest, explore — over an abstract world state, then builds a behavior tree to execute the cheapest plan. Ships replan mid-flight when a better option appears. |
| **Economy** | An order-book market per station prices 13 commodities off a coverage model with shortage-urgency multipliers. Ships move real supply between markets as they trade. |
| **Contracts** | Six kinds — Delivery, Courier, Passenger, Subsidy, Supply, CrewMission — with a full posted → accepted → paid lifecycle, reputation gating, auto-renewal, and age-escalating payments. |
| **Facilities** | Run production recipes (smelting, refining, manufacturing, farming, mining), degrade over time, self-repair with tools, level up 1–10, restock from local markets, and get abandoned when chronically broke. |
| **Factions** | Collect taxes on member facilities, post subsidy contracts for chronic shortages, fund construction of new facilities where demand is unmet, and hold pairwise relations. |
| **Populations** | Consume food and fuel, produce labor, post food and passenger contracts under stress, and physically migrate to happier systems when sentiment collapses. |
| **Crew** | Aggregate hunger / fatigue / morale with derived tasks (piloting, engineering, trading, eating, resting), skill progression, wages, and a morale death-spiral guard. |
| **Construction** | Chronic shortages spawn construction sites that accrete delivered cargo 0 → 1.0, then materialize into a real, persistent facility. |
| **Persistence** | Everything flushes to SQLite; a sim resumes from the exact tick it left off. A per-universe `world_seed` keeps the nebula backdrop and landmarks stable across restarts. |
| **Spatial LOD** | Distant ships tick less often (with rate-scaled state changes) so the frame budget goes where you're looking. |

For the deep dive — tick phase ordering, the AI stack, the economic
feedback loop, runtime ownership — see
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), which has mermaid diagrams
for all of it.

---

## Quick start

You need a [Rust toolchain](https://rustup.rs/) (stable). Then:

```bash
make run
# equivalent to: cargo run -p client_bevy
```

That boots the Bevy app into the main menu. **Start** opens a fresh
universe (name it, or take the default); **Load Game** lists every save
in the binary's directory. Saves live next to the binary as
`<universe-name>.db` — default `sim.db`.

Other entry points:

| Goal | Command |
|---|---|
| Windowed client (debug) | `make run` |
| Release build | `make build` → binary at `target/release/client_bevy` |
| **Headless** (no window, for CI / smoke tests) | `cargo run -p client_bevy -- --headless` |
| Verify (build + test + clippy, strict) | `make verify` |
| Smoke test (boot headless, print DB counts) | `scripts/smoke.sh [secs]` |

> **One binary, one process.** `client_bevy` *is* the whole thing — the
> simulation runs in-process. Headless mode spins up the HTTP/WebSocket
> server (from the `sim_server` library crate) for scripted and CI use;
> there is no separate server binary to run.

---

## Controls

| Input | Action |
|---|---|
| **Left-drag** | Orbit camera |
| **Right-drag** / **WASD** | Pan |
| **Scroll** | Zoom |
| **Left-click** | Select ship or facility → opens its details panel |
| **Right-click** | Context menu (Inspect / Follow / POV / Destroy) |
| **Space** | Pause / resume |
| **Esc** | Close top panel · clear selection · open pause menu |
| **P** | Pause menu |
| **F12** | Screenshot |
| Top bar | Toggle panels (Ships, Markets, Factions, Contracts, Events, …), set speed (1× / 2× / 5× / 10×), spawn ships/facilities |

Every panel reads the ECS world live — the inspector is effectively a
real-time debugger with full component access. Click a ship to see its
credits, crew, fuel, current goal, fitting, route memory, and its last
few AI commands.

---

## Architecture

Five crates in one Cargo workspace:

```
sim_core     Pure simulation logic — hecs ECS, GOAP planner, economy,
             contracts. No async, no IO, no framework. Trivially testable.
sim_db       SQLite persistence (sqlx) — pool, seeder, ECS loader,
             persistence worker, migrations.
sim_server   Library crate — HTTP/WebSocket handlers + engine apply
             helpers. Drives headless mode; embedded by the client.
sim_protocol WebSocket wire types (headless / CI only).
client_bevy  The binary. Bevy 0.18 + egui. Embeds sim_core as a Bevy
             Resource; the renderer queries the hecs world directly.
```

Three rules keep it honest:

1. **`sim_core` never imports tokio, sqlx, or axum.** Pure logic only, so
   the whole simulation is reasoned about and unit-tested without async.
2. **hecs is the source of truth during a tick.** The tick loop holds
   exclusive mutable access — no per-agent locks.
3. **Cross-entity effects go through a command buffer** (`SimCommand`). A
   phase reads world state and writes commands; the next phase applies
   them. Deterministic, no mid-phase write conflicts.

The full tick phase order, ownership model, and feedback loops are
diagrammed in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

> The original **Godot** client lives on in history as a parity reference,
> but it's no longer the front end — the pivot to an embedded Bevy client
> removed the socket boundary entirely, and every feature now lands in
> `client_bevy`.

---

## Building & packaging

The `Makefile` wraps cargo + rustup + codesign + packaging:

```bash
make build              # release binary (host target)
make build-mac          # arm64 macOS  (also: build-mac-intel, build-mac-universal)
make build-win          # Windows MSVC (run on a Windows host)
make build-linux        # Linux        (best on a Linux host)

make package-mac        # .app bundle + ad-hoc codesign + Info.plist
make dmg                # macOS .dmg
make package-win        # Windows .zip
make package-linux      # Linux .tar.gz
```

The workspace version in the root `Cargo.toml` is the single source of
truth — the binary reads it via `env!("CARGO_PKG_VERSION")` and the
`Makefile` greps the same field for `Info.plist` and archive names, so
packaged builds never drift.

---

## Tech stack

- **[Rust](https://www.rust-lang.org/)** (edition 2021) — the whole thing
- **[Bevy 0.18](https://bevyengine.org/)** — renderer, ECS-driven main loop, custom WGSL shaders (procedural planets, sun corona, nebulae, starfield)
- **[hecs](https://github.com/Ralith/hecs)** — the simulation's own ECS (separate from Bevy's, deliberately)
- **[egui](https://github.com/emilk/egui)** (via `bevy_egui`) — every inspector panel
- **[bevy_hanabi](https://github.com/djeedai/bevy_hanabi)** — GPU particle trails and explosions
- **[sqlx](https://github.com/launchbadge/sqlx)** + SQLite — persistence, bundled so there's no runtime dependency
- **[axum](https://github.com/tokio-rs/axum)** + tokio — the headless HTTP/WebSocket harness

---

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for dev
setup, the conventions that keep the codebase clean, and a list of
concrete directions if you want to take this somewhere real.

The fastest sanity check before any PR:

```bash
make verify   # build + ~250 tests + clippy, strict
```

---

## License

[MIT](LICENSE) © 2026 Kalcode (David Clausen). Do whatever you like with it.

---

<div align="center">
<sub>Built for fun in Rust &amp; Bevy · By Kalcode &amp; Claude · Made with ❤️ in Illinois</sub>
</div>
