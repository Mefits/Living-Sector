//! Route planning over the location graph.
//!
//! Two edge kinds weave together:
//!
//! - **Normal** edges come from `WorldRegistry.routes` (the seeded
//!   `travel_routes` table). These are the local "burn between stations"
//!   lanes inside a star system.
//! - **Gate** edges connect a gate facility's location to its paired
//!   gate's location in another system. They're declared via a
//!   `gate_pairs` lookup (location → paired location) that the
//!   spawner builds after gate facilities register.
//!
//! Dijkstra over this graph yields a `Vec<Leg>` route. The ship's BT
//! feeds each leg to `ShipTransit`. Gate legs don't consume transit
//! time — they emit a `RequestGateJump` command; the apply phase
//! charges the fee + teleports the ship.
//!
//! **Why a separate module**: the registry is read-only topology; the
//! pathfinder is a function over it. Keeping them separate means we
//! can swap in A* / hierarchical pathfinding later without touching
//! the loader.

use crate::world::registry::WorldRegistry;
use std::collections::{BinaryHeap, HashMap};

/// One hop in a planned route.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Leg {
    pub from: String,
    pub to: String,
    pub distance: u32,
    pub kind: LegKind,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LegKind {
    /// Ordinary burn between two locations. Drives `ShipTransit.transit`
    /// and consumes `travel_ticks(distance, speed)` ticks.
    Travel,
    /// Gate jump from one gate location to its paired gate. Doesn't
    /// create a `ShipTransit` entry — the apply phase handles it.
    /// The `distance` is nominal (1 unit) so Dijkstra prefers gates
    /// over multi-system burns without being zero-weight (which would
    /// break the priority queue's ordering).
    Gate,
}

/// The edge weight we use for Dijkstra. Gate jumps get a tiny weight
/// plus a fixed per-jump overhead so the pathfinder considers them
/// "cheap but not free" — if a non-gate path is shorter, it'll win.
const GATE_EDGE_WEIGHT: u32 = 5;

/// Input to the pathfinder: the registry plus a gate-pair lookup. We
/// separate the gate map from `WorldRegistry` because gate pairings are
/// learned from gate facilities (which the spawner builds on top of
/// the registry), and we don't want `sim_core` to depend on spawner
/// internals. The caller passes the map in.
pub struct PathfinderCtx<'a> {
    pub registry: &'a WorldRegistry,
    /// location → paired location. Present for every gate location on
    /// both sides (mirror-paired).
    pub gate_pairs: &'a HashMap<String, String>,
}

impl PathfinderCtx<'_> {
    /// Find a route from `from` to `to`. Returns `Some(legs)` when a
    /// path exists, `None` otherwise (e.g. disconnected systems with
    /// no functioning gates).
    ///
    /// `from == to` returns `Some(vec![])` (no legs to travel).
    pub fn find_route(&self, from: &str, to: &str) -> Option<Vec<Leg>> {
        if from == to {
            return Some(Vec::new());
        }

        // Dijkstra with predecessor tracking so we can reconstruct the
        // actual leg sequence, not just the cost.
        #[derive(Eq, PartialEq)]
        struct Node {
            cost: u32,
            location: String,
        }
        impl Ord for Node {
            fn cmp(&self, other: &Self) -> std::cmp::Ordering {
                // Flip for min-heap.
                other.cost.cmp(&self.cost)
            }
        }
        impl PartialOrd for Node {
            fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
                Some(self.cmp(other))
            }
        }

        let mut dist: HashMap<String, u32> = HashMap::new();
        let mut prev: HashMap<String, (String, u32, LegKind)> = HashMap::new();
        let mut heap = BinaryHeap::new();

        dist.insert(from.to_string(), 0);
        heap.push(Node {
            cost: 0,
            location: from.to_string(),
        });

        while let Some(Node { cost, location }) = heap.pop() {
            if location == to {
                break;
            }
            // Stale entry — a shorter path was already found for this node.
            if cost > *dist.get(&location).unwrap_or(&u32::MAX) {
                continue;
            }
            // Normal edges — travel routes out of this location.
            for route in self.registry.reachable_from(&location) {
                let next_cost = cost.saturating_add(route.distance);
                let current = dist.get(&route.to).copied().unwrap_or(u32::MAX);
                if next_cost < current {
                    dist.insert(route.to.clone(), next_cost);
                    prev.insert(
                        route.to.clone(),
                        (location.clone(), route.distance, LegKind::Travel),
                    );
                    heap.push(Node {
                        cost: next_cost,
                        location: route.to.clone(),
                    });
                }
            }
            // Gate edge — if this location is a gate, we can jump to
            // its paired location in one step.
            if let Some(paired) = self.gate_pairs.get(&location) {
                let next_cost = cost.saturating_add(GATE_EDGE_WEIGHT);
                let current = dist.get(paired).copied().unwrap_or(u32::MAX);
                if next_cost < current {
                    dist.insert(paired.clone(), next_cost);
                    prev.insert(
                        paired.clone(),
                        (location.clone(), 1, LegKind::Gate),
                    );
                    heap.push(Node {
                        cost: next_cost,
                        location: paired.clone(),
                    });
                }
            }
        }

        // No path: the destination was never reached.
        if !dist.contains_key(to) {
            return None;
        }

        // Walk predecessors backward from `to` to `from`.
        let mut legs: Vec<Leg> = Vec::new();
        let mut cursor = to.to_string();
        while cursor != from {
            let (from_loc, distance, kind) = prev.get(&cursor)?.clone();
            legs.push(Leg {
                from: from_loc.clone(),
                to: cursor,
                distance,
                kind,
            });
            cursor = from_loc;
        }
        legs.reverse();
        Some(legs)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::world::registry::{Route, WorldRegistry};

    fn registry_with_routes(routes: &[(&str, &str, u32)]) -> WorldRegistry {
        let mut r = WorldRegistry::default();
        for (from, to, dist) in routes {
            r.routes
                .entry(from.to_string())
                .or_default()
                .push(Route {
                    to: to.to_string(),
                    distance: *dist,
                });
            // Bidirectional — matches how the seeder inserts routes.
            r.routes
                .entry(to.to_string())
                .or_default()
                .push(Route {
                    to: from.to_string(),
                    distance: *dist,
                });
        }
        r
    }

    #[test]
    fn same_location_is_empty_route() {
        let reg = WorldRegistry::default();
        let pairs = HashMap::new();
        let ctx = PathfinderCtx {
            registry: &reg,
            gate_pairs: &pairs,
        };
        assert_eq!(ctx.find_route("earth", "earth"), Some(vec![]));
    }

    #[test]
    fn single_hop_via_normal_route() {
        let reg = registry_with_routes(&[("earth", "mars", 100)]);
        let pairs = HashMap::new();
        let ctx = PathfinderCtx {
            registry: &reg,
            gate_pairs: &pairs,
        };
        let legs = ctx.find_route("earth", "mars").unwrap();
        assert_eq!(legs.len(), 1);
        assert_eq!(legs[0].from, "earth");
        assert_eq!(legs[0].to, "mars");
        assert_eq!(legs[0].distance, 100);
        assert_eq!(legs[0].kind, LegKind::Travel);
    }

    #[test]
    fn multi_hop_prefers_shorter() {
        // earth → mars: direct 300, vs earth → belt → mars: 100 + 80 = 180
        let reg = registry_with_routes(&[
            ("earth", "mars", 300),
            ("earth", "belt", 100),
            ("belt", "mars", 80),
        ]);
        let pairs = HashMap::new();
        let ctx = PathfinderCtx {
            registry: &reg,
            gate_pairs: &pairs,
        };
        let legs = ctx.find_route("earth", "mars").unwrap();
        assert_eq!(legs.len(), 2);
        assert_eq!(legs[0].to, "belt");
        assert_eq!(legs[1].to, "mars");
    }

    #[test]
    fn gate_jump_enables_cross_system() {
        // Two systems. Sol: earth → sol-gate (50). AC: ac-gate → haven
        // (40). Gate pair: sol-gate ↔ ac-gate.
        let reg = registry_with_routes(&[
            ("earth", "sol-gate", 50),
            ("ac-gate", "haven", 40),
        ]);
        let mut pairs = HashMap::new();
        pairs.insert("sol-gate".to_string(), "ac-gate".to_string());
        pairs.insert("ac-gate".to_string(), "sol-gate".to_string());
        let ctx = PathfinderCtx {
            registry: &reg,
            gate_pairs: &pairs,
        };
        let legs = ctx.find_route("earth", "haven").unwrap();
        assert_eq!(legs.len(), 3);
        assert_eq!(legs[0].kind, LegKind::Travel);
        assert_eq!(legs[0].to, "sol-gate");
        assert_eq!(legs[1].kind, LegKind::Gate);
        assert_eq!(legs[1].from, "sol-gate");
        assert_eq!(legs[1].to, "ac-gate");
        assert_eq!(legs[2].kind, LegKind::Travel);
        assert_eq!(legs[2].to, "haven");
    }

    #[test]
    fn unreachable_returns_none() {
        let reg = registry_with_routes(&[("a", "b", 1)]);
        let pairs = HashMap::new();
        let ctx = PathfinderCtx {
            registry: &reg,
            gate_pairs: &pairs,
        };
        assert!(ctx.find_route("a", "z").is_none());
    }
}
