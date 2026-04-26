//! Admin "Add Ship" + "Add Facility" spawn dialogs.
//!
//! Two paired forms — almost identical structure, both reachable from
//! the top bar's `+Ship` / `+Fac` buttons. Both build their picker
//! options from the live world (faction list from `faction_by_id`,
//! locations / bodies from hecs queries) and persist field state
//! across openings so the user can re-spawn the same shape repeatedly
//! without re-picking.
//!
//! Spawn click writes a fully-typed payload into
//! `crate::sim::Spawn{Ship,Facility}Request`; a separate `process_*`
//! system in `crate::sim` consumes the request and calls
//! `sim_server::engine::admin_spawn_*`. Auto-closes on spawn so the
//! user sees their new entity; Cancel keeps form fields intact for
//! the next open.
//!
//! ## Add Ship
//!   * Ship classes hard-coded ([`SHIP_CLASSES`]) — they map onto
//!     `ShipClass` enum variants in sim_core.
//!   * Locations exclude gates (gates aren't dock points; spawning
//!     a ship there gets it immediately reset by gate logic).
//!   * Empty name → `admin_spawn_ship` auto-generates one.
//!
//! ## Add Facility
//!   * Facility types from [`FACILITY_TYPES`] (station / outpost /
//!     mining_rig / refinery / factory / farm / shipyard).
//!   * Bodies pulled from `BodyIdentity` query.
//!   * Name is required (Spawn button disabled until non-empty).
//!
//! Extracted from `ui/mod.rs` in the Phase-21 god-module split.

use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};

use super::theme;
use crate::sim::Sim;

/// State for the "Add Ship" admin dialog. Open/close via the
/// top-bar "+Ship" button. Form fields persist between openings so
/// repeated test spawns don't make the user re-pick everything.
#[derive(Resource)]
pub(super) struct AddShipDialogState {
    pub open: bool,
    class: String,
    faction_id: String,
    location_name: String,
    credits: i64,
    name: String,
}

impl Default for AddShipDialogState {
    fn default() -> Self {
        Self {
            open: false,
            class: "freighter".to_string(),
            faction_id: "independent".to_string(),
            location_name: "earth-station".to_string(),
            credits: 5_000,
            name: String::new(),
        }
    }
}

const SHIP_CLASSES: &[&str] = &["courier", "freighter", "hauler", "tanker", "miner"];

pub(super) fn add_ship_dialog(
    mut ctx: EguiContexts,
    mut state: ResMut<AddShipDialogState>,
    sim: Res<Sim>,
    mut spawn_req: ResMut<crate::sim::SpawnShipRequest>,
) {
    if !state.open {
        return;
    }

    use sim_core::agents::facility::{FacilityIdentity, FacilityLocation};

    // Build picker options from the live world. Factions come from
    // the faction_by_id index; locations from facility ECS data.
    // Sorted + deduped so the dropdowns are stable across frames
    // (hashmap iteration order isn't).
    let mut factions: Vec<String> = sim.store.faction_by_id.keys().cloned().collect();
    factions.sort();

    let location_set: std::collections::BTreeSet<String> = sim
        .store
        .world
        .query::<(&FacilityIdentity, &FacilityLocation)>()
        .iter()
        .filter_map(|(_e, (id, loc))| {
            // Skip gates as spawn destinations — gates aren't dock
            // points and admin_spawn_ship at a gate gets the ship
            // immediately reset by the gate logic. Stations / mines /
            // factories / refineries / farms / outposts only.
            if id.facility_type == "gate" {
                None
            } else {
                Some(loc.location_name.clone())
            }
        })
        .collect();
    let locations: Vec<String> = location_set.into_iter().collect();

    let mut open = state.open;
    let mut spawn_clicked = false;
    egui::Window::new("Add Ship")
        .anchor(egui::Align2::CENTER_CENTER, egui::vec2(0.0, 0.0))
        .collapsible(false)
        .resizable(false)
        .default_width(360.0)
        .open(&mut open)
        .show(ctx.ctx_mut().unwrap(), |ui| {
            egui::Grid::new("add_ship_form")
                .num_columns(2)
                .spacing([12.0, 6.0])
                .show(ui, |ui| {
                    ui.label(theme::caption("Class"));
                    egui::ComboBox::from_id_salt("add_ship_class")
                        .selected_text(&state.class)
                        .show_ui(ui, |ui| {
                            for &c in SHIP_CLASSES {
                                ui.selectable_value(&mut state.class, c.to_string(), c);
                            }
                        });
                    ui.end_row();

                    ui.label(theme::caption("Faction"));
                    egui::ComboBox::from_id_salt("add_ship_faction")
                        .selected_text(&state.faction_id)
                        .show_ui(ui, |ui| {
                            for f in &factions {
                                ui.selectable_value(&mut state.faction_id, f.clone(), f);
                            }
                        });
                    ui.end_row();

                    ui.label(theme::caption("Location"));
                    egui::ComboBox::from_id_salt("add_ship_location")
                        .selected_text(&state.location_name)
                        .show_ui(ui, |ui| {
                            for l in &locations {
                                ui.selectable_value(&mut state.location_name, l.clone(), l);
                            }
                        });
                    ui.end_row();

                    ui.label(theme::caption("Credits"));
                    let mut credits = state.credits;
                    if ui
                        .add(
                            egui::DragValue::new(&mut credits)
                                .range(0..=10_000_000)
                                .speed(100.0),
                        )
                        .changed()
                    {
                        state.credits = credits;
                    }
                    ui.end_row();

                    ui.label(theme::caption("Name"));
                    ui.add(
                        egui::TextEdit::singleline(&mut state.name)
                            .hint_text("(auto-generated if empty)"),
                    );
                    ui.end_row();
                });

            ui.add_space(6.0);
            ui.horizontal(|ui| {
                if ui
                    .add(egui::Button::new(
                        egui::RichText::new("Spawn").color(theme::SUCCESS),
                    ))
                    .clicked()
                {
                    spawn_clicked = true;
                }
                if ui.button("Cancel").clicked() {
                    // Cancel just closes; we keep the form fields so
                    // the user can re-open and tweak without
                    // re-picking from scratch.
                    state.open = false;
                }
            });
        });

    if spawn_clicked {
        spawn_req.0 = Some(crate::sim::SpawnShipParams {
            class: state.class.clone(),
            faction_id: state.faction_id.clone(),
            location_name: state.location_name.clone(),
            credits: state.credits,
            name: state.name.clone(),
        });
        // Auto-close on spawn so the user sees their new ship; they
        // can re-open if they want to spawn a few in a row.
        state.open = false;
    } else {
        state.open = open;
    }
}

/// State for the "Add Facility" admin dialog. Mirrors AddShipDialog
/// — form fields persist between openings.
#[derive(Resource)]
pub(super) struct AddFacilityDialogState {
    pub open: bool,
    name: String,
    facility_type: String,
    body_id: String,
    faction_id: String,
    docking_capacity: u32,
    credits: i64,
}

impl Default for AddFacilityDialogState {
    fn default() -> Self {
        Self {
            open: false,
            name: String::new(),
            facility_type: "station".to_string(),
            body_id: "earth".to_string(),
            faction_id: "independent".to_string(),
            docking_capacity: 4,
            credits: 10_000,
        }
    }
}

const FACILITY_TYPES: &[&str] = &[
    "station",
    "outpost",
    "mining_rig",
    "refinery",
    "factory",
    "farm",
    "shipyard",
];

pub(super) fn add_facility_dialog(
    mut ctx: EguiContexts,
    mut state: ResMut<AddFacilityDialogState>,
    sim: Res<Sim>,
    mut spawn_req: ResMut<crate::sim::SpawnFacilityRequest>,
) {
    if !state.open {
        return;
    }

    use sim_core::agents::celestial_body::BodyIdentity;

    let mut factions: Vec<String> = sim.store.faction_by_id.keys().cloned().collect();
    factions.sort();

    let body_set: std::collections::BTreeSet<String> = sim
        .store
        .world
        .query::<&BodyIdentity>()
        .iter()
        .map(|(_e, id)| id.body_id.clone())
        .collect();
    let bodies: Vec<String> = body_set.into_iter().collect();

    let mut open = state.open;
    let mut spawn_clicked = false;
    egui::Window::new("Add Facility")
        .anchor(egui::Align2::CENTER_CENTER, egui::vec2(0.0, 0.0))
        .collapsible(false)
        .resizable(false)
        .default_width(360.0)
        .open(&mut open)
        .show(ctx.ctx_mut().unwrap(), |ui| {
            egui::Grid::new("add_fac_form")
                .num_columns(2)
                .spacing([12.0, 6.0])
                .show(ui, |ui| {
                    ui.label(theme::caption("Name"));
                    ui.add(
                        egui::TextEdit::singleline(&mut state.name)
                            .hint_text("e.g. Hyperion Outpost"),
                    );
                    ui.end_row();

                    ui.label(theme::caption("Type"));
                    egui::ComboBox::from_id_salt("add_fac_type")
                        .selected_text(&state.facility_type)
                        .show_ui(ui, |ui| {
                            for &t in FACILITY_TYPES {
                                ui.selectable_value(&mut state.facility_type, t.to_string(), t);
                            }
                        });
                    ui.end_row();

                    ui.label(theme::caption("Body"));
                    egui::ComboBox::from_id_salt("add_fac_body")
                        .selected_text(&state.body_id)
                        .show_ui(ui, |ui| {
                            for b in &bodies {
                                ui.selectable_value(&mut state.body_id, b.clone(), b);
                            }
                        });
                    ui.end_row();

                    ui.label(theme::caption("Faction"));
                    egui::ComboBox::from_id_salt("add_fac_faction")
                        .selected_text(&state.faction_id)
                        .show_ui(ui, |ui| {
                            for f in &factions {
                                ui.selectable_value(&mut state.faction_id, f.clone(), f);
                            }
                        });
                    ui.end_row();

                    ui.label(theme::caption("Dock cap"));
                    let mut cap = state.docking_capacity as i32;
                    if ui
                        .add(egui::DragValue::new(&mut cap).range(0..=200).speed(1.0))
                        .changed()
                    {
                        state.docking_capacity = cap.max(0) as u32;
                    }
                    ui.end_row();

                    ui.label(theme::caption("Credits"));
                    let mut credits = state.credits;
                    if ui
                        .add(
                            egui::DragValue::new(&mut credits)
                                .range(0..=10_000_000)
                                .speed(100.0),
                        )
                        .changed()
                    {
                        state.credits = credits;
                    }
                    ui.end_row();
                });

            ui.add_space(6.0);
            ui.horizontal(|ui| {
                let valid = !state.name.trim().is_empty();
                let spawn_btn = ui.add_enabled(
                    valid,
                    egui::Button::new(egui::RichText::new("Spawn").color(theme::SUCCESS)),
                );
                if spawn_btn.clicked() {
                    spawn_clicked = true;
                }
                if !valid {
                    ui.label(
                        egui::RichText::new("name required")
                            .small()
                            .color(theme::WARN),
                    );
                }
                if ui.button("Cancel").clicked() {
                    state.open = false;
                }
            });
        });

    if spawn_clicked {
        spawn_req.0 = Some(crate::sim::SpawnFacilityParams {
            name: state.name.clone(),
            facility_type: state.facility_type.clone(),
            body_id: state.body_id.clone(),
            faction_id: state.faction_id.clone(),
            docking_capacity: state.docking_capacity,
            credits: state.credits,
        });
        state.open = false;
    } else {
        state.open = open;
    }
}
