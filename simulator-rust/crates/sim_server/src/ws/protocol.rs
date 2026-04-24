//! WebSocket protocol types — moved to the standalone `sim_protocol`
//! crate (2026-04-24 client-bevy port, Bundle 1.1) so Rust-native
//! clients can depend on the wire schema without pulling in the full
//! `sim_server` dependency graph. This file re-exports everything for
//! back-compat so existing imports like `crate::ws::protocol::ServerMsg`
//! keep working.

pub use sim_protocol::{ClientMsg, PositionEntry, ServerMsg, SimControl};
