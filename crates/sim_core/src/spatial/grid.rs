//! Uniform spatial grid for fast proximity queries.
//!
//! Combat + faction-interaction-ready. An `UniformGrid<T>` buckets
//! world positions into fixed-size cells keyed by `(i32, i32)`;
//! proximity queries touch only the cells a query radius overlaps,
//! making "ships within R of point X" O(cells_touched + agents_in_those_cells)
//! instead of O(all_agents).
//!
//! ## When to use
//!
//! - **Combat AoE**: "every ship within 5 units of this explosion."
//! - **Sensors / radar**: "any hostile within my sensor range?"
//! - **Faction territory**: "ships currently inside our claim zone."
//! - **LOD recompute (marginal)**: the existing O(agents × observers)
//!   walk is already fast enough at 485 agents; grid shines more as
//!   scale grows past 5k agents.
//!
//! ## Cell sizing
//!
//! Pick a cell size close to the typical query radius. Too small →
//! queries touch many cells; too large → each cell has many agents.
//! For a universe spanning ~50 units with typical query radii of
//! 5–10 units, a cell_size of 5.0–10.0 is a reasonable default.
//!
//! ## Coordinate space
//!
//! Positions are `(f32, f32)` in universe units. Negative positions
//! are fine — we cast-truncate toward zero so `(-0.5, 0.5)` and
//! `(0.5, -0.5)` map to `(0, 0)`, which is intentional: adjacent
//! cells still handle any edge overlap via the query's cell-rectangle
//! sweep.
//!
//! ## Identity
//!
//! `T` is the entity-like identity the caller wants to track —
//! typically `hecs::Entity` or a string id. It needs `Clone + Eq +
//! Hash`. `move_to` is efficient because the grid caches the prior
//! position per id.

use std::collections::{HashMap, HashSet};
use std::hash::Hash;

/// 2D uniform spatial grid.
#[derive(Debug, Clone)]
pub struct UniformGrid<T: Clone + Eq + Hash> {
    cell_size: f32,
    /// Cell (cx, cy) → set of ids whose position falls in this cell.
    cells: HashMap<(i32, i32), HashSet<T>>,
    /// Id → last-known position. Required so `move_to` and `remove`
    /// know which cell to update without the caller re-passing the
    /// old position.
    positions: HashMap<T, (f32, f32)>,
}

impl<T: Clone + Eq + Hash> UniformGrid<T> {
    /// Build an empty grid with the given cell size. Panics if
    /// `cell_size <= 0` — a non-positive cell size has no sensible
    /// semantics.
    pub fn new(cell_size: f32) -> Self {
        assert!(cell_size > 0.0, "cell_size must be positive");
        Self {
            cell_size,
            cells: HashMap::new(),
            positions: HashMap::new(),
        }
    }

    pub fn cell_size(&self) -> f32 {
        self.cell_size
    }

    pub fn len(&self) -> usize {
        self.positions.len()
    }

    pub fn is_empty(&self) -> bool {
        self.positions.is_empty()
    }

    /// Convert a world position to its cell key. `(cx, cy)` where
    /// `cx = floor(x / cell_size)`. Uses integer truncation since
    /// f32→i32 cast rounds toward zero.
    pub fn cell_of(&self, pos: (f32, f32)) -> (i32, i32) {
        let cx = (pos.0 / self.cell_size).floor() as i32;
        let cy = (pos.1 / self.cell_size).floor() as i32;
        (cx, cy)
    }

    /// Insert or move `id` to `pos`. If the id was already present
    /// in a different cell we remove it from the old cell first.
    pub fn insert(&mut self, id: T, pos: (f32, f32)) {
        let new_cell = self.cell_of(pos);
        if let Some(&old_pos) = self.positions.get(&id) {
            let old_cell = self.cell_of(old_pos);
            if old_cell == new_cell {
                // Same cell — just update stored position, no bucket churn.
                self.positions.insert(id, pos);
                return;
            }
            // Different cell — remove from old bucket.
            if let Some(bucket) = self.cells.get_mut(&old_cell) {
                bucket.remove(&id);
                if bucket.is_empty() {
                    self.cells.remove(&old_cell);
                }
            }
        }
        self.cells.entry(new_cell).or_default().insert(id.clone());
        self.positions.insert(id, pos);
    }

    /// Move an existing `id` to `new_pos`. Equivalent to `insert`
    /// — the separate name reads nicer at call sites that want
    /// to signal "this was already here."
    pub fn move_to(&mut self, id: T, new_pos: (f32, f32)) {
        self.insert(id, new_pos);
    }

    /// Remove `id` from the grid. Returns the last-known position
    /// if it was present. No-op if absent.
    pub fn remove(&mut self, id: &T) -> Option<(f32, f32)> {
        let pos = self.positions.remove(id)?;
        let cell = self.cell_of(pos);
        if let Some(bucket) = self.cells.get_mut(&cell) {
            bucket.remove(id);
            if bucket.is_empty() {
                self.cells.remove(&cell);
            }
        }
        Some(pos)
    }

    /// Last-known position of `id`, if present.
    pub fn position(&self, id: &T) -> Option<(f32, f32)> {
        self.positions.get(id).copied()
    }

    /// Iterate every id in the grid. Useful for diagnostics /
    /// test assertions; not a hot-path API.
    pub fn iter(&self) -> impl Iterator<Item = (&T, (f32, f32))> {
        self.positions.iter().map(|(id, p)| (id, *p))
    }

    /// Return every id whose stored position is within `radius`
    /// (Euclidean) of `center`. Touches only cells the query
    /// rectangle overlaps, then does exact distance² comparisons
    /// (so edge-of-cell false positives are filtered).
    pub fn query_radius(&self, center: (f32, f32), radius: f32) -> Vec<T> {
        if radius <= 0.0 {
            return Vec::new();
        }
        let r2 = radius * radius;
        let min_cx = ((center.0 - radius) / self.cell_size).floor() as i32;
        let max_cx = ((center.0 + radius) / self.cell_size).floor() as i32;
        let min_cy = ((center.1 - radius) / self.cell_size).floor() as i32;
        let max_cy = ((center.1 + radius) / self.cell_size).floor() as i32;
        let mut out: Vec<T> = Vec::new();
        for cx in min_cx..=max_cx {
            for cy in min_cy..=max_cy {
                let Some(bucket) = self.cells.get(&(cx, cy)) else {
                    continue;
                };
                for id in bucket {
                    let Some(&p) = self.positions.get(id) else {
                        continue;
                    };
                    let dx = p.0 - center.0;
                    let dy = p.1 - center.1;
                    if dx * dx + dy * dy <= r2 {
                        out.push(id.clone());
                    }
                }
            }
        }
        out
    }

    /// Nearest id to `center`, if any, along with its distance.
    /// Linear scan over the covered cells at expanding radii —
    /// useful for "find closest station" / "nearest hostile"
    /// patterns without the caller picking a radius.
    pub fn nearest(&self, center: (f32, f32), max_radius: f32) -> Option<(T, f32)> {
        let matches = self.query_radius(center, max_radius);
        matches
            .into_iter()
            .filter_map(|id| {
                let p = self.positions.get(&id)?;
                let dx = p.0 - center.0;
                let dy = p.1 - center.1;
                Some((id, (dx * dx + dy * dy).sqrt()))
            })
            .min_by(|(_, a), (_, b)| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal))
    }

    /// Rebuild the grid from a fresh `(id, pos)` iterator. Useful
    /// when the caller maintains its own position map and wants
    /// a one-shot rebuild rather than incremental updates.
    pub fn rebuild_from<I: IntoIterator<Item = (T, (f32, f32))>>(&mut self, entries: I) {
        self.cells.clear();
        self.positions.clear();
        for (id, pos) in entries {
            self.insert(id, pos);
        }
    }
}

impl<T: Clone + Eq + Hash> Default for UniformGrid<T> {
    /// Default grid uses a cell size of 10 universe units — a
    /// sensible middle for the current three-system sim.
    fn default() -> Self {
        Self::new(10.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn insert_and_query() {
        let mut g: UniformGrid<&'static str> = UniformGrid::new(10.0);
        g.insert("a", (0.0, 0.0));
        g.insert("b", (5.0, 5.0));
        g.insert("c", (25.0, 25.0));
        let hits = g.query_radius((0.0, 0.0), 10.0);
        assert!(hits.contains(&"a"));
        assert!(hits.contains(&"b"));
        assert!(!hits.contains(&"c"));
    }

    #[test]
    fn move_updates_bucket() {
        let mut g: UniformGrid<&'static str> = UniformGrid::new(10.0);
        g.insert("a", (0.0, 0.0));
        assert!(g.query_radius((0.0, 0.0), 5.0).contains(&"a"));
        g.move_to("a", (100.0, 100.0));
        assert!(!g.query_radius((0.0, 0.0), 5.0).contains(&"a"));
        assert!(g.query_radius((100.0, 100.0), 5.0).contains(&"a"));
    }

    #[test]
    fn remove_forgets_position() {
        let mut g: UniformGrid<&'static str> = UniformGrid::new(10.0);
        g.insert("a", (0.0, 0.0));
        assert_eq!(g.len(), 1);
        assert_eq!(g.remove(&"a"), Some((0.0, 0.0)));
        assert_eq!(g.len(), 0);
        assert!(g.query_radius((0.0, 0.0), 100.0).is_empty());
    }

    #[test]
    fn query_radius_respects_exact_distance() {
        // Two cells worth of entries; ensure the exact distance²
        // filter catches edge-of-cell false positives.
        let mut g: UniformGrid<&'static str> = UniformGrid::new(10.0);
        g.insert("near", (3.0, 4.0)); // distance 5
        g.insert("far", (9.0, 9.0));  // distance ~12.7
        let hits = g.query_radius((0.0, 0.0), 6.0);
        assert!(hits.contains(&"near"));
        assert!(!hits.contains(&"far"));
    }

    #[test]
    fn nearest_works() {
        let mut g: UniformGrid<&'static str> = UniformGrid::new(10.0);
        g.insert("a", (10.0, 0.0));
        g.insert("b", (3.0, 4.0));
        g.insert("c", (100.0, 100.0));
        let (id, dist) = g.nearest((0.0, 0.0), 50.0).unwrap();
        assert_eq!(id, "b");
        assert!((dist - 5.0).abs() < 1e-4);
    }

    #[test]
    fn negative_positions_bucket_correctly() {
        let mut g: UniformGrid<&'static str> = UniformGrid::new(10.0);
        g.insert("sol", (-5.0, -5.0));
        g.insert("ac", (20.0, 5.0));
        // Query around sol shouldn't hit AC.
        let hits = g.query_radius((-5.0, -5.0), 5.0);
        assert!(hits.contains(&"sol"));
        assert!(!hits.contains(&"ac"));
    }

    #[test]
    fn rebuild_from_iter_clears_previous() {
        let mut g: UniformGrid<&'static str> = UniformGrid::new(10.0);
        g.insert("old", (0.0, 0.0));
        g.rebuild_from(vec![("new", (50.0, 50.0))]);
        assert_eq!(g.len(), 1);
        assert!(!g.query_radius((0.0, 0.0), 5.0).contains(&"old"));
        assert!(g.query_radius((50.0, 50.0), 5.0).contains(&"new"));
    }
}
