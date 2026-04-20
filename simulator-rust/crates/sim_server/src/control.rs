//! Control commands sent from HTTP/WS handlers → tick loop.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "action", rename_all = "snake_case")]
pub enum ControlCommand {
    Pause,
    Resume,
    SetSpeed { interval_ms: u64 },
    MoveObserver { id: String, x: f32, y: f32, radius: f32 },
}
