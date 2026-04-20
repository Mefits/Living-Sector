//! Shared `Position` struct for snapshot JSON.
//!
//! Godot expects `{"x": f, "y": f}` for positions; Rust tuples `(f32, f32)`
//! serialize as JSON arrays `[x, y]` which doesn't match. This struct gives
//! us the dict shape while staying lightweight.

use serde::Serialize;

#[derive(Debug, Clone, Copy, Default, Serialize)]
pub struct Position {
    pub x: f32,
    pub y: f32,
}

impl From<(f32, f32)> for Position {
    fn from(v: (f32, f32)) -> Self {
        Self { x: v.0, y: v.1 }
    }
}
