use std::collections::HashMap;

/// Info about a star system loaded from DB.
#[derive(Debug, Clone)]
pub struct SystemInfo {
    pub db_id: i64,
    pub name: String,
    pub universe_offset: (f32, f32),
    /// Spectral class string ("M", "K", "G", "F", "A", "B", "O" or
    /// any custom marker the seed JSON uses). The renderer maps
    /// this to a colour + size; sim logic doesn't care. None = use
    /// the renderer's default (typically G-class yellow).
    pub star_type: Option<String>,
}

/// Info about a location (nav node) loaded from DB.
#[derive(Debug, Clone)]
pub struct LocationInfo {
    pub db_id: i64,
    pub name: String,
    pub loc_type: String,
    pub celestial_body_id: i64,
}

/// A travel connection between two locations.
#[derive(Debug, Clone)]
pub struct Route {
    pub to: String,
    pub distance: u32,
}

/// Read-only world topology loaded at startup.
/// Passed as `Arc<WorldRegistry>` so agents can read without locks.
#[derive(Debug, Default)]
pub struct WorldRegistry {
    pub systems: HashMap<String, SystemInfo>,   // name → info
    pub locations: HashMap<String, LocationInfo>, // name → info
    /// from_location → list of reachable destinations
    pub routes: HashMap<String, Vec<Route>>,
    pub faction_ids: Vec<String>,
}

impl WorldRegistry {
    pub fn travel_distance(&self, from: &str, to: &str) -> Option<u32> {
        self.routes
            .get(from)?
            .iter()
            .find(|r| r.to == to)
            .map(|r| r.distance)
    }

    /// Shortest physical cost across native travel corridors, ignoring
    /// jump-gate teleportation (conservative for strategic budget checks).
    /// Does not create a direct edge: the ship's leg-by-leg BT still uses
    /// pathfinder::PathfinderCtx and the direct-only travel_distance().
    pub fn shortest_distance(&self, from: &str, to: &str) -> Option<u32> {
        use std::cmp::Reverse;
        use std::collections::BinaryHeap;
        if from == to { return Some(0); }
        if !self.locations.contains_key(from) || !self.locations.contains_key(to) {
            return None;
        }
        let mut frontier: BinaryHeap<Reverse<(u32, String)>> = BinaryHeap::new();
        let mut costs: HashMap<String,u32> = HashMap::new();
        frontier.push(Reverse((0,from.to_owned())));
        costs.insert(from.to_owned(),0);
        while let Some(Reverse((cost,from))) = frontier.pop() {
            if from==to { return Some(cost); }
            if cost > costs.get(&from).copied().unwrap_or(u32::MAX) { continue; }
            for leg in self.reachable_from(&from) {
                if !self.locations.contains_key(&leg.to) { continue; }
                let sum = cost.saturating_add(leg.distance);
                if sum < costs.get(&leg.to).copied().unwrap_or(u32::MAX) {
                    costs.insert(leg.to.clone(),sum);
                    frontier.push(Reverse((sum,leg.to.clone())));
                }
            }
        }
        None
    }

    pub fn reachable_from(&self, location: &str) -> &[Route] {
        self.routes.get(location).map(|v| v.as_slice()).unwrap_or(&[])
    }

    pub fn location_universe_pos(&self, location: &str) -> Option<(f32, f32)> {
        // Locations don't have direct positions — bodies do. For now return None;
        // Phase 4 will compute positions from body orbital data.
        let _ = location;
        None
    }
}


#[cfg(test)]
mod galaxy04_multihop_strategy_distance_tests {
    use super::*;

    #[test]
    fn galaxy04_multihop_strategy_distance_preserves_real_ship_legs() {
        let mut g=WorldRegistry::default();
        for name in ["station-alpha","station-sol","mars-colony","isolated"] {
            g.locations.insert(name.into(),LocationInfo {
                db_id:0,name:name.into(),loc_type:"station".into(),
                celestial_body_id:0,
            });
        }
        g.routes.insert("station-alpha".into(),vec![
            Route{to:"station-sol".into(),distance:125}
        ]);
        g.routes.insert("station-sol".into(),vec![
            Route{to:"station-alpha".into(),distance:125},
            Route{to:"mars-colony".into(),distance:22}
        ]);
        g.routes.insert("mars-colony".into(),vec![
            Route{to:"station-sol".into(),distance:22}
        ]);
        assert_eq!(g.travel_distance("station-alpha","mars-colony"),None,
            "Ships must never transit across non-existing direct edge");
        assert_eq!(g.shortest_distance("station-alpha","mars-colony"),Some(147));
        assert_eq!(g.shortest_distance("mars-colony","station-alpha"),Some(147));
        assert_eq!(g.shortest_distance("mars-colony","mars-colony"),Some(0));
        assert_eq!(g.shortest_distance("isolated","mars-colony"),None);
        assert_eq!(g.shortest_distance("missing","mars-colony"),None);
    }
}
