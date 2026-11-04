//! Serialisable snapshots for ships.
//!
//! `ShipSnapshot` is the wire-format type: built from a full bundle of
//! live components via `ShipSnapshot::build`, then cached in
//! `SnapshotCache` on the server side and pushed to the Godot client
//! over HTTP + WS. Field names match what the client reads; changes
//! here are breaking protocol changes.
//!
//! Extracted from the former monolithic `ship.rs` in the Phase-20
//! refactor.

use super::{
    ShipAI, ShipCargo, ShipCrew, ShipCrewSkills, ShipEconomy, ShipFitting, ShipFuel,
    ShipIdentity, ShipLifecycle, ShipPosition, ShipProgression, ShipTransit, Transit,
};
use serde::Serialize;
use std::collections::HashMap;

/// Subsystem loadout + derived stat roll-up mirror. Godot's details
/// panel reads `modules` for the slot-by-slot display and
/// `stats` for the tooltip line ("+15% speed, −5% fuel"). Slugs are
/// stable catalog keys; use them for `/api/admin/ships/:id/refit`
/// round-trips in Phase 18b.
#[derive(Debug, Clone, Serialize, Default)]
pub struct ShipFittingSnapshot {
    /// slot_name → module_slug (None → slot is empty).
    pub modules: HashMap<String, Option<String>>,
    pub stats: ShipDerivedStatsSnapshot,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct ShipDerivedStatsSnapshot {
    pub speed_mult: f32,
    pub cargo_capacity_mult: f32,
    pub fuel_efficiency_mult: f32,
    pub sensor_range_au: f32,
    pub comms_bonus: f32,
    pub power_use: u16,
    pub power_cap: u16,
}

impl From<&ShipFitting> for ShipFittingSnapshot {
    fn from(fit: &ShipFitting) -> Self {
        let mut modules: HashMap<String, Option<String>> = HashMap::new();
        for slot in crate::modules::SLOTS.iter().copied() {
            modules.insert(
                slot.as_str().to_string(),
                fit.slot_slug(slot).map(|s| s.to_string()),
            );
        }
        let d = fit.derived;
        Self {
            modules,
            stats: ShipDerivedStatsSnapshot {
                speed_mult: d.speed_mult,
                cargo_capacity_mult: d.cargo_capacity_mult,
                fuel_efficiency_mult: d.fuel_efficiency_mult,
                sensor_range_au: d.sensor_range_au,
                comms_bonus: d.comms_bonus,
                power_use: d.power_use,
                power_cap: d.power_cap,
            },
        }
    }
}

/// Serializable snapshot for HTTP/WS clients — built by querying components.
///
/// Field names match what the Godot client reads. Position uses the `{x, y}`
/// dict shape (via `Position` wrapper); `location` is the string name of the
/// ship's current location (None = in transit).
#[derive(Debug, Clone, Serialize)]
pub struct ShipSnapshot {
    pub id: String,
    pub name: String,
    pub class: String,
    pub faction_id: String,
    /// Authoritative star-system identifier for UI filtering, including
    /// ships in transit where location is None.
    pub system_id: String,
    /// Scale tier (Phase 18f). Snake-case name (e.g. `"large"`).
    /// Godot renders this alongside class in the details panel.
    pub size: &'static str,
    pub size_tier: u8,
    /// Current location string (e.g. "earth-station"). `None` while in transit.
    /// Godot's `ship.gd` reads this as `data["location"]` for docked checks.
    #[serde(rename = "location")]
    pub location_name: Option<String>,
    pub docked: bool,
    pub transit: Option<Transit>,
    pub cargo: HashMap<String, u32>,
    pub cargo_capacity: u32,
    pub fuel: f32,
    pub fuel_capacity: f32,
    pub credits: i64,
    pub current_goal: String,
    /// Contract currently being executed, if any — lets the UI pull the
    /// full contract record from `/api/contracts` for richer display.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub active_contract_id: Option<String>,
    /// Current BT action name (Debug-formatted enum variant). Godot UI
    /// panels display this under `current_bt`.
    #[serde(rename = "current_bt")]
    pub bt_action: Option<String>,
    pub position: crate::agents::Position,
    // Lifecycle counters — shown in the ship list UI
    pub broke_strikes: u8,
    pub hoard_strikes: u8,
    pub idle_ticks: u32,
    /// Aggregate crew stats (size/morale/fatigue), for the details panel.
    pub crew: ShipCrewSnapshot,
    /// Fitted subsystems + derived rollup (speed/cargo/sensors/power).
    /// Present on every ship; `None` only if the component somehow
    /// didn't attach (legacy save pre-Phase-18a — we default-fit on
    /// load now, so this is effectively always Some in practice).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub fitting: Option<ShipFittingSnapshot>,
    /// Level / XP / banked retrofit points (Phase 18d). Drives the
    /// agent-side retrofit gate. None on pre-18d saves; new spawns
    /// always attach a fresh level-1 progression.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub progression: Option<ShipProgressionSnapshot>,
    /// Per-faction reputation (0..=100), grown by delivering
    /// faction-tagged contracts and dinged by breaching them.
    /// Omitted when empty so fresh / unowned ships stay clean in
    /// the JSON. Phase 19e: exposed so the UI + diagnostics can see
    /// rep actually climbing (previously only lived on ShipEconomy
    /// and never hit the wire).
    #[serde(skip_serializing_if = "HashMap::is_empty")]
    pub faction_reputation: HashMap<String, u8>,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct ShipProgressionSnapshot {
    pub level: u8,
    pub xp: u32,
    pub retrofit_points: u8,
    /// XP needed to ding to `level + 1`. Godot uses it to render a
    /// progress bar without reimplementing the threshold formula.
    pub next_level_threshold: u32,
}

impl From<&ShipProgression> for ShipProgressionSnapshot {
    fn from(p: &ShipProgression) -> Self {
        Self {
            level: p.level,
            xp: p.xp,
            retrofit_points: p.retrofit_points,
            next_level_threshold: p.next_level_threshold(),
        }
    }
}

/// Crew section of `ShipSnapshot`. Small-enough to inline; Godot displays
/// it on the ship details panel. Godot reads `current_task` to render
/// "3 piloting, 1 eating" style labels; `skills` is shown on mission
/// eligibility tooltips.
#[derive(Debug, Clone, Serialize, Default)]
pub struct ShipCrewSnapshot {
    pub size: u32,
    /// Rounded for UI display — underlying state is f32 for smooth decay.
    pub morale: u8,
    pub fatigue: u8,
    pub hunger: u8,
    pub health: u8,
    pub current_task: &'static str,
    pub wages_credits: i64,
    /// Optional skills map (nav/eng/trade/combat), defaulting to None when
    /// the ship hasn't had a ShipCrewSkills component attached yet.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub skills: Option<ShipCrewSkillsSnapshot>,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct ShipCrewSkillsSnapshot {
    pub navigation: u8,
    pub engineering: u8,
    pub trading: u8,
    pub combat: u8,
}

impl ShipSnapshot {
    #[allow(clippy::too_many_arguments)]
    pub fn build(
        identity: &ShipIdentity,
        position: &ShipPosition,
        transit: &ShipTransit,
        cargo: &ShipCargo,
        fuel: &ShipFuel,
        economy: &ShipEconomy,
        ai: &ShipAI,
        lifecycle: &ShipLifecycle,
        crew: Option<&ShipCrew>,
        skills: Option<&ShipCrewSkills>,
        fitting: Option<&ShipFitting>,
        progression: Option<&ShipProgression>,
    ) -> Self {
        let cargo_map: HashMap<String, u32> = cargo
            .cargo
            .iter()
            .map(|(c, &qty)| (c.as_str().to_string(), qty))
            .collect();
        let crew_snap = crew
            .map(|c| ShipCrewSnapshot {
                size: c.size,
                morale: c.morale.round().clamp(0.0, 255.0) as u8,
                fatigue: c.fatigue.round().clamp(0.0, 255.0) as u8,
                hunger: c.hunger.round().clamp(0.0, 255.0) as u8,
                health: c.health.round().clamp(0.0, 255.0) as u8,
                current_task: c.current_task.as_str(),
                wages_credits: c.wages_credits,
                skills: skills.map(|s| ShipCrewSkillsSnapshot {
                    navigation: s.navigation,
                    engineering: s.engineering,
                    trading: s.trading,
                    combat: s.combat,
                }),
            })
            .unwrap_or_default();
        Self {
            id: identity.id.clone(),
            name: identity.name.clone(),
            class: identity.class.clone(),
            faction_id: identity.faction_id.clone(),
            size: identity.size.as_str(),
            size_tier: identity.size.tier(),
            location_name: position.location_name.clone(),
            docked: position.docked_at.is_some(),
            transit: transit.transit.clone(),
            cargo: cargo_map,
            cargo_capacity: cargo.capacity,
            fuel: fuel.fuel,
            fuel_capacity: fuel.fuel_capacity,
            credits: economy.credits,
            current_goal: ai.current_goal.clone(),
            active_contract_id: economy.active_contract_id.clone(),
            bt_action: ai.current_bt.as_ref().and_then(|bt| bt.current_action()),
            position: crate::agents::Position::from(position.position),
            broke_strikes: lifecycle.broke_strikes,
            hoard_strikes: lifecycle.hoard_strikes,
            idle_ticks: lifecycle.idle_ticks,
            crew: crew_snap,
            fitting: fitting.map(ShipFittingSnapshot::from),
            progression: progression.map(ShipProgressionSnapshot::from),
            faction_reputation: economy.faction_reputation.clone(),
        }
    }
}
