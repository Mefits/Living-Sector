//! Hanabi particle effects — engine trails, ship explosions, gate flashes.
//!
//! Two implementations behind a `target_os` cfg gate:
//!
//! * **`imp_hanabi`** (Windows / Linux) — the real GPU particle
//!   system using `bevy_hanabi`. Three shared `EffectAsset`s built once
//!   at startup; ship engine trails, despawn explosions, gate-jump
//!   flashes.
//! * **`imp_stub`** (macOS) — a no-op shim with the same public
//!   surface. Hanabi 0.18.0 panics on Metal at pipeline creation
//!   (`premultiplied_alpha_mesh_pipeline`: shader Uniform vs
//!   pipeline-layout Storage mismatch) so we compile it out of the
//!   macOS build until that upstream bug is fixed.
//!
//! `bevy_hanabi` is also a target-conditional dep in `Cargo.toml`, so
//! the macOS build doesn't even pull the crate. Re-enabling on macOS
//! is a two-line change once hanabi ships a fix: drop the cfg gate
//! here and the target filter in `Cargo.toml`.

#[cfg(not(target_os = "macos"))]
mod imp_hanabi;
#[cfg(not(target_os = "macos"))]
pub use imp_hanabi::*;

#[cfg(target_os = "macos")]
mod imp_stub;
#[cfg(target_os = "macos")]
pub use imp_stub::*;
