//! sim_server library surface.
//!
//! Exposes the engine + supporting modules so other binaries
//! (notably `client_bevy`) can reuse the command-apply layer + admin
//! helpers without reaching through `main.rs`. The `simulator` binary
//! now imports from here rather than declaring its own `mod engine;`
//! etc. — a single compilation unit feeds both targets.
//!
//! This is a minimal-friction version of Bundle 2b.4: rather than
//! moving ~1200 lines of `apply_ship_commands` + helpers into
//! `sim_core::engine`, we just expose them through a lib surface.
//! `client_bevy` pays for a few extra dependencies in its build
//! (axum, flume, dashmap) that it doesn't exercise at runtime, but
//! that's cheap compared to the code-motion risk of a full move.

pub mod app_state;
pub mod control;
pub mod engine;
pub mod http;
pub mod runtime;
pub mod snapshot;
pub mod ws;
