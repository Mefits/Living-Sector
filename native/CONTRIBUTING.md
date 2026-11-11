# Contributing to The Space Project

First off — thank you for even looking. This project is shared in the
spirit of "here's a fun thing, do something with it." Whether you want to
fix a bug, add a system, or fork the whole thing and build a real game on
top of it, you're in the right place.

A little honesty up front: this isn't a project with a full-time
maintainer and a roadmap. It grew out of late-night sessions and it's
shared because the engine is genuinely solid and someone might get more
out of it than a private repo ever would. So:

- **PRs and issues are welcome**, and I'll read them — but I can't promise
  a fast turnaround.
- **Forking is a first-class outcome, not a fallback.** If your vision
  diverges from this one, fork it and run. That's a success, not a
  rejection.
- If you're planning something substantial, open an issue first so we
  don't duplicate work — but don't feel like you need permission to
  experiment.

---

## Getting set up

You need a stable [Rust toolchain](https://rustup.rs/). That's it — SQLite
is bundled, so there are no runtime dependencies to install.

```bash
git clone https://github.com/Kalcode/spaceprojectsim.git
cd spaceprojectsim
make run          # boots the Bevy client into the main menu
```

Useful commands:

| Command | What it does |
|---|---|
| `make run` | Windowed client, debug build |
| `make build` | Release binary → `target/release/client_bevy` |
| `cargo run -p client_bevy -- --headless` | Headless sim (HTTP/WS on `127.0.0.1:8080`) |
| `make verify` | **Build + ~250 tests + clippy, strict.** Run this before every PR. |
| `scripts/smoke.sh [secs]` | Boot headless with a temp DB, print DB counts |
| `scripts/persist-test.sh` | Boot → kill → reboot, verify the tick resumes |
| `WORLD_SPEED=4.0 scripts/smoke.sh 30` | Fast-forward game time to watch the economy converge |

The default play pace (`WORLD_SPEED=0.25`) is deliberately slow and
chill. Crank `WORLD_SPEED` up for tests and demos so you're not waiting on
Earth↔Mars transits.

---

## How the code is laid out

Five crates in one workspace. The dependency direction is strict and
one-way:

```
sim_core     Pure simulation — hecs ECS, GOAP planner, economy, contracts.
             No async, no IO, no framework. This is the heart of the thing.
sim_db       SQLite persistence (sqlx): pool, seeder, ECS loader, worker.
sim_server   Library crate: HTTP/WebSocket handlers + engine apply helpers.
sim_protocol WebSocket wire types (headless / CI only).
client_bevy  The binary. Bevy 0.18 + egui. Embeds sim_core directly.
```

If you're here for the simulation, you'll spend most of your time in
`sim_core`. If you're here for the client, `client_bevy`. See
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the tick loop, AI stack,
and ownership diagrams.

---

## The rules that keep it clean

These aren't bureaucracy — they're the invariants that make the codebase
possible to reason about. Please keep them intact.

1. **`sim_core` never imports tokio, sqlx, or axum.** It is pure,
   synchronous, IO-free logic. That's what makes the entire simulation
   unit-testable without spinning up a runtime or a database. If you need
   IO, enqueue a command and handle it outside the tick.

2. **hecs is the source of truth during a tick.** The tick loop holds
   exclusive mutable access to the world. Don't add `Mutex<Agent>` or
   per-agent locks — readers go through the snapshot cache after the tick.

3. **Cross-entity effects go through `SimCommand`.** A tick phase reads
   world state and writes commands to a buffer; the next phase drains and
   applies them. Same-entity mutations (a ship updating its own credits)
   happen in place. Cross-entity mutations (a trade changing a *market's*
   supply) must be a command. This is what makes ticks deterministic and
   free of write conflicts.

4. **Respect hecs borrow rules.** `query_mut` holds one mutable iterator
   at a time. When a phase needs to read markets while mutating ships,
   structure it as a read-only snapshot pass into a `HashMap`, then a
   mutating pass that closes over the snapshot. The existing tick
   functions (`tick_ships`, `tick_markets`, `tick_facilities`) are the
   canonical patterns — copy their shape.

5. **Document non-trivial files.** Every substantial module starts with a
   `//!` doc comment explaining what it owns and any non-obvious
   constraints. New files get the same treatment.

---

## Testing

- **Pure logic → `#[cfg(test)] mod` in the module.** No test database
  needed; the seeder is deterministic. Use `mktemp` for ephemeral DBs if a
  test genuinely needs persistence.
- **Integration smokes → `scripts/*.sh`.** Bash, exercising the headless
  binary end to end.
- Before opening a PR, `make verify` must pass clean — that's build, the
  full test suite, and clippy with warnings-as-errors.

---

## Pull requests

1. Branch off `main`.
2. Keep the change focused. If you find unrelated things to fix, that's
   great — but a separate PR.
3. Run `make verify` and make sure it's green.
4. Write a commit message that explains the *why*, not just the *what*.
5. Open the PR against `main` with a short description of the behavior
   change and how you verified it.

No CLA, no ceremony. Small, clear PRs get looked at fastest.

---

## Directions you could take this

If you want to build something real with this, here are concrete on-ramps
— roughly easiest to most ambitious. Every one of them is a legitimate
place to plant a flag.

**Warm-ups**
- **Windows build validation.** The cross-compile is wired up but hasn't
  been run in anger on a real Windows box. Verify it, fix what breaks.
- **Modding via world JSON.** The entire universe — systems, bodies,
  facilities, markets, ships, populations, factions — is seeded from JSON
  in `priv/data/`. New star systems and economies are pure data. Build a
  richer starting universe, or a different one entirely.

**Engine**
- **Parallelize the ship phase with rayon.** The dependency is already in
  and the architecture is designed for it (no cross-ship writes within a
  phase). It needs a snapshot-then-plan-then-apply refactor to get around
  hecs's single mutable iterator. Worth ~5× at 10k agents — the path to
  the 100k+ goal.
- **LOD rate-scaling for facilities and populations.** Ships already
  throttle by distance; facilities and pops carry the `AgentLod` field but
  don't gate on it yet. Recipe batch math and sentiment inertia need
  careful scaling.
- **Persistent replay log.** Commands are plain data, so a tick-by-tick
  append-to-disk log would enable full post-mortem replay of a multi-hour
  run. The live command-trace ring is already there as a starting point.

**Game**
- **Make it a game.** Right now you're a god-mode observer. Give the
  player a ship or a faction, add objectives, win/lose conditions, a
  progression loop. The whole simulated economy is a sandbox waiting for a
  player to matter inside it.
- **Combat.** Crew already carry an unused `combat` skill. Piracy,
  faction warfare, escorts, blockades — the economic stakes (contracts,
  reputation, subsidies) are already there to make it mean something.
- **Rip out `sim_core` as a standalone library.** It's a pure,
  IO-free, deterministic economy engine that happens to be attached to a
  Bevy client. Use it headless somewhere else entirely — a server, a
  different renderer, a text UI.

One thing this project has always deliberately *not* done: multiplayer.
That constraint is what let the client embed the engine and delete the
network boundary. If you want multiplayer, you'll be re-introducing that
boundary — very doable, but go in knowing it's a real architectural fork,
not a small feature.

Have fun with it. That's the whole point.
