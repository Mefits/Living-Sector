//! Control commands sent from HTTP/WS handlers → tick loop.
//!
//! Two *independent* time knobs:
//! - `ticks_per_second` (aka tick resolution) — how often the tick loop fires.
//!   Higher = smoother client interpolation. Purely a rendering/cadence
//!   concern; does NOT change how much game-time passes per tick.
//! - `world_speed` — game-time multiplier. 1.0 = real-time, 0.25 = 4× slower
//!   (the shipping default), 4.0 = 4× faster. Tunes how much game-clock
//!   passes per wall-clock second. Does NOT change tick cadence.
//!
//! `tick_scale` (used by orbital physics, fuel burn, travel time) is derived:
//!   `tick_scale = world_speed / ticks_per_second`
//!
//! Keeping the two knobs separate means you can run at 8 tps × 0.25 speed for
//! normal play, bump ticks_per_second to 16 for smoother client interpolation
//! without speeding up the game, or bump world_speed to 4.0 for a smoke
//! test without making the client's packet rate jittery.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "action", rename_all = "snake_case")]
pub enum ControlCommand {
    /// Freeze the tick loop. Preserves current world_speed / tps.
    Pause,
    /// Unfreeze.
    Resume,
    /// Change tick resolution (interval_ms = 1000 / tps). Does NOT touch
    /// world_speed.
    SetTicksPerSecond { tps: u32 },
    /// Change game-time multiplier. Does NOT touch ticks_per_second.
    /// Accepts 0.0..=16.0; 0.0 is equivalent to pause.
    SetWorldSpeed { world_speed: f32 },
    /// Spatial-LOD observer (reserved).
    MoveObserver { id: String, x: f32, y: f32, radius: f32 },
}
