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
