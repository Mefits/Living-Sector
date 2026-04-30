//! Facility list + details panels.
//!
//! Two panels in one module because the list and details share state
//! (`SelectedFacility`) and have parallel shapes to ship_list +
//! ship_details. Splitting them would just be churn.
//!
//! ## List panel ([`facility_list_panel`])
//!
//! Sortable / filterable roster of every facility (~95 today).
//! Columns: Name (selectable, strikethrough when abandoned), Type,
//! Faction, Location, Credits, Dock occupancy `<docked>/<cap>`,
//! Level. Click any row to set [`SelectedFacility`] which opens the
//! details panel. Auto-open via `CLIENT_BEVY_OPEN_PANELS=
//! facilities|all`.
//!
//! ## Details panel ([`facility_details_panel`])
//!
//! Reads every facility component from hecs and renders one section
//! per: identity, operations (credits / condition / docking),
//! lifecycle (level / xp / abandon counter), reserves, fitting
//! (optional — gates don't have it), crew (optional), dock list.
//!
//! Dock subsection cross-navigates: clicking a docked or queued ship
//! row writes `SelectedShip`, opening that ship's details panel.
//! Tightens the facility → ship navigation path the way Godot's
//! version did.
//!
//! Admin actions:
//!   * **Focus camera** — looks up the body position by `id.body_id`
//!     and writes [`CameraFocusRequest`].
//!   * **Refill reserves** — floors every Commodity reserve entry at
//!     500 units. Won't downgrade a richer stockpile.
//!   * Per-commodity inline editor: `-100` / `+100` / `+1k` per
//!     existing commodity row, plus an "Add" picker that lists every
//!     [`Commodity::ALL`] not currently stocked.
//!
//! Borrow rules: all admin mutations are buffered into local Vec /
//! Option / bool variables inside the egui closure, then applied
//! after the read-only query borrow drops. Standard hecs pattern.
//!
//! [`SelectedFacility`] is `pub` so the render layer can read it for
//! the selection-ring highlight.
//!
//! Extracted from `ui/mod.rs` in the Phase-21 god-module split.

use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};

use super::ship_list::SelectedShip;
use super::{format::format_credits, theme};
use crate::camera::CameraFocusRequest;
use crate::render::SCALE_FACTOR;
use crate::sim::Sim;

#[derive(Resource)]
pub(super) struct FacilityListState {
    pub open: bool,
    sort: FacilitySort,
    descending: bool,
    filter: String,
}

impl Default for FacilityListState {
    fn default() -> Self {
        let auto_open = std::env::var("CLIENT_BEVY_OPEN_PANELS")
            .map(|s| s.contains("facilities") || s == "all")
            .unwrap_or(false);
        Self {
            open: auto_open,
            sort: FacilitySort::default(),
            descending: false,
            filter: String::new(),
        }
    }
}

#[derive(Default, PartialEq, Eq, Clone, Copy)]
enum FacilitySort {
    #[default]
    Name,
    Type,
    Faction,
    Location,
    Credits,
    Docked,
    Level,
}

#[derive(Resource, Default)]
pub struct SelectedFacility(pub Option<String>);

struct FacilityRow {
    id: String,
    name: String,
    facility_type: String,
    faction: String,
    location: String,
    credits: i64,
    docked: u32,
    capacity: u32,
    level: u8,
    abandoned: bool,
}

pub(super) fn facility_list_panel(
    mut ctx: EguiContexts,
    _sim: Res<Sim>,
    mut state: ResMut<FacilityListState>,
    mut selected: ResMut<SelectedFacility>,
    facilities_q: Query<(
        &sim_core::agents::facility::FacilityIdentity,
        &sim_core::agents::facility::FacilityLocation,
        &sim_core::agents::facility::FacilityOperations,
        &sim_core::agents::facility::FacilityStorage,
        &sim_core::agents::facility::FacilityLifecycle,
    )>,
) {
    let mut open = state.open;
    let mut sort = state.sort;
    let mut descending = state.descending;
    let mut filter = state.filter.clone();

    if !open {
        return;
    }

    let rows: Vec<FacilityRow> = facilities_q
        .iter()
        .map(|(id, loc, ops, stor, life)| FacilityRow {
            id: id.id.clone(),
            name: id.name.clone(),
            facility_type: id.facility_type.clone(),
            faction: id.faction_id.clone(),
            location: loc.location_name.clone(),
            credits: ops.credits,
            docked: stor.docked_ships.len() as u32,
            capacity: ops.docking_capacity,
            level: life.level,
            abandoned: life.abandoned,
        })
        .collect();

    let filter_lc = filter.to_lowercase();
    let mut filtered: Vec<&FacilityRow> = rows
        .iter()
        .filter(|r| {
            if filter_lc.is_empty() {
                return true;
            }
            r.name.to_lowercase().contains(&filter_lc)
                || r.id.to_lowercase().contains(&filter_lc)
                || r.facility_type.to_lowercase().contains(&filter_lc)
                || r.faction.to_lowercase().contains(&filter_lc)
                || r.location.to_lowercase().contains(&filter_lc)
        })
        .collect();

    filtered.sort_by(|a, b| {
        let cmp = match sort {
            FacilitySort::Name => a.name.cmp(&b.name),
            FacilitySort::Type => a.facility_type.cmp(&b.facility_type),
            FacilitySort::Faction => a.faction.cmp(&b.faction),
            FacilitySort::Location => a.location.cmp(&b.location),
            FacilitySort::Credits => a.credits.cmp(&b.credits),
            FacilitySort::Docked => a.docked.cmp(&b.docked),
            FacilitySort::Level => a.level.cmp(&b.level),
        };
        if descending {
            cmp.reverse()
        } else {
            cmp
        }
    });

    let total = rows.len();
    let shown = filtered.len();

    egui::Window::new(format!("Facilities · {shown}/{total}"))
        .id(egui::Id::new("facilities_window"))
        .default_width(800.0)
        .default_height(460.0)
        .open(&mut open)
        .show(ctx.ctx_mut().unwrap(), |ui| {
            ui.horizontal(|ui| {
                ui.label("filter:");
                ui.text_edit_singleline(&mut filter);
            });
            ui.separator();

            egui::ScrollArea::vertical().show(ui, |ui| {
                egui::Grid::new("facility_list_grid")
                    .striped(true)
                    .num_columns(7)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        fac_sort_header(ui, "Name", &mut sort, &mut descending, FacilitySort::Name);
                        fac_sort_header(ui, "Type", &mut sort, &mut descending, FacilitySort::Type);
                        fac_sort_header(
                            ui,
                            "Faction",
                            &mut sort,
                            &mut descending,
                            FacilitySort::Faction,
                        );
                        fac_sort_header(
                            ui,
                            "Location",
                            &mut sort,
                            &mut descending,
                            FacilitySort::Location,
                        );
                        fac_sort_header(
                            ui,
                            "Credits",
                            &mut sort,
                            &mut descending,
                            FacilitySort::Credits,
                        );
                        fac_sort_header(
                            ui,
                            "Dock",
                            &mut sort,
                            &mut descending,
                            FacilitySort::Docked,
                        );
                        fac_sort_header(ui, "Lvl", &mut sort, &mut descending, FacilitySort::Level);
                        ui.end_row();

                        for r in &filtered {
                            let is_sel = selected.0.as_deref() == Some(r.id.as_str());
                            let name_text = if r.abandoned {
                                egui::RichText::new(&r.name)
                                    .color(theme::TEXT_DIM)
                                    .strikethrough()
                            } else {
                                egui::RichText::new(&r.name)
                            };
                            if ui.selectable_label(is_sel, name_text).clicked() {
                                selected.0 = Some(r.id.clone());
                            }
                            ui.label(&r.facility_type);
                            ui.label(&r.faction);
                            ui.label(&r.location);
                            ui.label(format_credits(r.credits));
                            ui.label(format!("{}/{}", r.docked, r.capacity));
                            ui.label(format!("{}", r.level));
                            ui.end_row();
                        }
                    });
            });
        });

    state.open = open;
    state.sort = sort;
    state.descending = descending;
    state.filter = filter;
}

fn fac_sort_header(
    ui: &mut egui::Ui,
    label: &str,
    current: &mut FacilitySort,
    descending: &mut bool,
    target: FacilitySort,
) {
    let arrow = if *current == target {
        if *descending {
            " ▼"
        } else {
            " ▲"
        }
    } else {
        ""
    };
    let active = *current == target;
    let color = if active {
        theme::PRIMARY
    } else {
        theme::TEXT_DIM
    };
    let text = egui::RichText::new(format!("{label}{arrow}"))
        .strong()
        .color(color);
    if ui.add(egui::Button::new(text).frame(false)).clicked() {
        if *current == target {
            *descending = !*descending;
        } else {
            *current = target;
            *descending = matches!(
                target,
                FacilitySort::Credits | FacilitySort::Docked | FacilitySort::Level,
            );
        }
    }
}

#[allow(clippy::too_many_arguments)]
pub(super) fn facility_details_panel(
    mut ctx: EguiContexts,
    sim: Res<Sim>,
    mut selected: ResMut<SelectedFacility>,
    mut focus_req: ResMut<CameraFocusRequest>,
    mut ship_sel: ResMut<SelectedShip>,
    bodies_q: Query<(
        &sim_core::agents::celestial_body::BodyIdentity,
        &sim_core::agents::celestial_body::BodyOrbit,
    )>,
    fitting_q: Query<&sim_core::agents::facility::FacilityFitting>,
    crew_q: Query<&sim_core::agents::facility::FacilityCrew>,
    base_q: Query<(
        &sim_core::agents::facility::FacilityIdentity,
        &sim_core::agents::facility::FacilityLocation,
        &sim_core::agents::facility::FacilityOperations,
        &sim_core::agents::facility::FacilityStorage,
        &sim_core::agents::facility::FacilityLifecycle,
    )>,
    mut storage_mut_q: Query<&mut sim_core::agents::facility::FacilityStorage>,
    ships_id_q: Query<&sim_core::agents::ship::ShipIdentity>,
) {
    use sim_core::agents::facility::{
        FacilityCrew, FacilityFitting,
    };

    let Some(fac_id) = selected.0.clone() else {
        return;
    };
    let Some(&entity) = sim.store.facility_by_id.get(&fac_id) else {
        selected.0 = None;
        return;
    };

    let mut still_open = true;
    // Captured by the egui closure; consulted after the closure
    // ends so admin mutations don't conflict with the read-only
    // query that's live inside.
    let mut refill_requested = false;
    // Per-commodity reserve deltas captured by the +/- buttons in
    // the Reserves grid. Applied after the read-only query drops.
    let mut reserves_deltas: Vec<(sim_core::economy::commodities::Commodity, f32)> = Vec::new();
    // Optional "add new commodity" pick; if Some, the apply pass
    // inserts an entry initialised to 100 units.
    let mut add_commodity: Option<sim_core::economy::commodities::Commodity> = None;
    let title = format!("Facility · {}", fac_id);

    egui::Window::new(title)
        .default_width(520.0)
        .default_height(640.0)
        .open(&mut still_open)
        .show(ctx.ctx_mut().unwrap(), |ui| {
            // Phase B: queries are passed as system params, so the
            // bevy_ecs &mut-World conflict the old code worked around
            // is gone. Body positions still come from a precomputed
            // HashMap because the Reserves grid below iterates them
            // by body_id, not by entity.
            let body_positions: std::collections::HashMap<String, (f32, f32)> = bodies_q
                .iter()
                .map(|(b, o)| (b.body_id.clone(), o.universe_position()))
                .collect();
            // Clone optional components — gates don't have fitting/crew.
            let fitting: Option<FacilityFitting> = fitting_q.get(entity).ok().cloned();
            let crew: Option<FacilityCrew> = crew_q.get(entity).ok().cloned();

            let Ok((id, loc, ops, storage, life)) = base_q.get(entity) else {
                ui.label("(facility entity missing components)");
                return;
            };

            // Toolbar: focus camera + admin actions. Focus writes a
            // separate Resource (safe inline); Refill flips the
            // outer bool we apply after the read-query drops.
            ui.horizontal(|ui| {
                if ui.button("Focus camera").clicked() {
                    let body_pos = body_positions.get(&id.body_id).copied();
                    if let Some((x, y)) = body_pos {
                        focus_req.0 = Some(Vec3::new(x * SCALE_FACTOR, 0.0, y * SCALE_FACTOR));
                    }
                }
                ui.separator();
                ui.label(egui::RichText::new("admin:").small().color(theme::TEXT_DIM));
                if ui
                    .button(egui::RichText::new("Refill reserves").small())
                    .on_hover_text(
                        "Floor every commodity entry in this facility's \
                         reserves at 500 units. Use to unstick starving \
                         facilities during testing without rebuilding the \
                         whole market.",
                    )
                    .clicked()
                {
                    refill_requested = true;
                }
            });
            ui.separator();

            egui::ScrollArea::vertical().show(ui, |ui| {
                if life.abandoned {
                    ui.colored_label(theme::DANGER, egui::RichText::new("ABANDONED").strong());
                    ui.separator();
                }

                ui.label(theme::section_header("Identity"));
                egui::Grid::new("fac_details_identity")
                    .num_columns(2)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        ui.label("Name");
                        ui.label(&id.name);
                        ui.end_row();
                        ui.label("Type");
                        ui.label(&id.facility_type);
                        ui.end_row();
                        ui.label("Body");
                        ui.label(&id.body_id);
                        ui.end_row();
                        ui.label("Location");
                        ui.label(&loc.location_name);
                        ui.end_row();
                        ui.label("Faction");
                        ui.label(&id.faction_id);
                        ui.end_row();
                    });
                ui.separator();

                ui.label(theme::section_header("Operations"));
                egui::Grid::new("fac_details_ops")
                    .num_columns(2)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        ui.label("Credits");
                        ui.label(format_credits(ops.credits));
                        ui.end_row();
                        ui.label("Condition");
                        let cond_color = theme::status_color(ops.condition, (0.7, 0.3));
                        ui.colored_label(cond_color, format!("{:.0}%", ops.condition * 100.0));
                        ui.end_row();
                        ui.label("Docking");
                        ui.label(format!(
                            "{} / {} (+{} queued)",
                            storage.docked_ships.len(),
                            ops.docking_capacity,
                            storage.dock_queue.len(),
                        ));
                        ui.end_row();
                    });
                ui.separator();

                ui.label(theme::section_header("Lifecycle"));
                egui::Grid::new("fac_details_life")
                    .num_columns(2)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        ui.label("Level");
                        ui.label(format!(
                            "{} / {}",
                            life.level,
                            sim_core::agents::facility::FACILITY_LEVEL_CAP
                        ));
                        ui.end_row();
                        ui.label("XP");
                        ui.label(format!("{} / {}", life.xp, life.next_level_threshold()));
                        ui.end_row();
                        if life.abandon_counter > 0 {
                            ui.label("Abandon countdown");
                            ui.label(format!("{}", life.abandon_counter));
                            ui.end_row();
                        }
                    });
                ui.separator();

                ui.label(theme::section_header("Reserves"));
                if storage.reserves.is_empty() {
                    ui.label(
                        egui::RichText::new("(no reserves)")
                            .italics()
                            .color(theme::TEXT_DIM),
                    );
                } else {
                    egui::Grid::new("fac_details_reserves")
                        .striped(true)
                        .num_columns(5)
                        .spacing([6.0, 2.0])
                        .show(ui, |ui| {
                            let mut items: Vec<_> = storage.reserves.iter().collect();
                            items.sort_by_key(|(c, _)| c.as_str());
                            for (c, qty) in items {
                                ui.label(c.as_str());
                                ui.label(egui::RichText::new(format!("{:.0}", qty)).monospace());
                                if ui
                                    .add(egui::Button::new("-100").small())
                                    .on_hover_text("Subtract 100 units (floored at 0).")
                                    .clicked()
                                {
                                    reserves_deltas.push((*c, -100.0));
                                }
                                if ui
                                    .add(egui::Button::new("+100").small())
                                    .on_hover_text("Add 100 units.")
                                    .clicked()
                                {
                                    reserves_deltas.push((*c, 100.0));
                                }
                                if ui
                                    .add(egui::Button::new("+1k").small())
                                    .on_hover_text("Add 1000 units — quick top-up.")
                                    .clicked()
                                {
                                    reserves_deltas.push((*c, 1000.0));
                                }
                                ui.end_row();
                            }
                        });
                }
                // "Add commodity" picker — list any commodity not
                // already in reserves so the user can introduce a new
                // line without typing a string. Initialises new
                // entries at 100 units (small enough to feel like a
                // delta, big enough to be visible).
                ui.horizontal(|ui| {
                    let existing: std::collections::HashSet<_> =
                        storage.reserves.keys().copied().collect();
                    let missing: Vec<_> = sim_core::economy::commodities::Commodity::ALL
                        .iter()
                        .copied()
                        .filter(|c| !existing.contains(c))
                        .collect();
                    if !missing.is_empty() {
                        ui.label(theme::caption("Add"));
                        egui::ComboBox::from_id_salt("fac_reserves_add")
                            .selected_text("(pick a commodity)")
                            .show_ui(ui, |ui| {
                                for c in &missing {
                                    if ui.selectable_label(false, c.as_str()).clicked() {
                                        add_commodity = Some(*c);
                                    }
                                }
                            });
                    }
                });
                ui.separator();

                if let Some(fit) = fitting {
                    ui.label(theme::section_header("Fitting"));
                    egui::Grid::new("fac_details_fit")
                        .num_columns(2)
                        .spacing([12.0, 2.0])
                        .show(ui, |ui| {
                            for slot in sim_core::facility_modules::FACILITY_SLOTS.iter() {
                                ui.label(slot.as_str());
                                ui.label(fit.slots[slot.index()].unwrap_or("—"));
                                ui.end_row();
                            }
                            ui.label("Recipe output mult");
                            ui.label(format!("{:.2}×", fit.derived.recipe_output_mult));
                            ui.end_row();
                            ui.label("Max batches bonus");
                            ui.label(format!("+{}", fit.derived.max_batches_bonus));
                            ui.end_row();
                        });
                    ui.separator();
                }

                if let Some(crew) = crew {
                    ui.label(theme::section_header("Crew"));
                    egui::Grid::new("fac_details_crew")
                        .num_columns(2)
                        .spacing([12.0, 2.0])
                        .show(ui, |ui| {
                            ui.label("Count");
                            ui.label(format!("{}", crew.crew_count));
                            ui.end_row();
                            ui.label("Morale");
                            ui.colored_label(
                                theme::crew_bar_color(crew.morale),
                                format!("{:.0}", crew.morale),
                            );
                            ui.end_row();
                            ui.label("Hunger");
                            ui.colored_label(
                                theme::crew_bar_color(100.0 - crew.hunger),
                                format!("{:.0}", crew.hunger),
                            );
                            ui.end_row();
                            ui.label("Efficiency");
                            ui.label(format!("{:.2}×", crew.efficiency()));
                            ui.end_row();
                        });
                    ui.separator();
                }

                if !storage.docked_ships.is_empty() || !storage.dock_queue.is_empty() {
                    ui.label(theme::section_header("Dock"));
                    // Resolve each docked / queued entity back to
                    // its ShipIdentity so the panel can name them.
                    // Cheap even at Haven's 45-capacity — 45 hecs
                    // query_ones per facility click, maybe once a
                    // second when the user is browsing.
                    // Resolve a docked / queued entity back to
                    // (id, label). id is the sim_id we use for
                    // selection; label is "<name> (<class>)".
                    let resolve = |e| {
                        ships_id_q
                            .get(e)
                            .ok()
                            .map(|id| (id.id.clone(), format!("{} ({})", id.name, id.class)))
                    };

                    if !storage.docked_ships.is_empty() {
                        ui.label(
                            egui::RichText::new(format!("Docked ({})", storage.docked_ships.len()))
                                .italics()
                                .color(theme::TEXT_DIM),
                        );
                        for &e in &storage.docked_ships {
                            if let Some((sim_id, label)) = resolve(e) {
                                if ui
                                    .selectable_label(false, egui::RichText::new(label).small())
                                    .on_hover_text("Select this docked ship")
                                    .clicked()
                                {
                                    ship_sel.0 = Some(sim_id);
                                }
                            }
                        }
                    }
                    if !storage.dock_queue.is_empty() {
                        ui.label(
                            egui::RichText::new(format!(
                                "Queue ({} waiting)",
                                storage.dock_queue.len()
                            ))
                            .italics()
                            .color(theme::WARN),
                        );
                        for (i, &e) in storage.dock_queue.iter().enumerate() {
                            if let Some((sim_id, label)) = resolve(e) {
                                let line = format!("{:>2}. {}", i + 1, label);
                                if ui
                                    .selectable_label(false, egui::RichText::new(line).small())
                                    .on_hover_text("Select this queued ship")
                                    .clicked()
                                {
                                    ship_sel.0 = Some(sim_id);
                                }
                            }
                        }
                    }
                    if !storage.pending_deliveries.is_empty() {
                        ui.label(format!(
                            "Pending deliveries: {}",
                            storage.pending_deliveries.len()
                        ));
                    }
                }
            });
        });

    if refill_requested {
        use sim_core::economy::commodities::Commodity;
        if let Ok(mut storage) = storage_mut_q.get_mut(entity) {
            // Floor each commodity's reserve at 500. Don't downgrade
            // a richer facility — admins use this to recover from
            // crisis, not to nuke a healthy stockpile.
            for c in Commodity::ALL.iter().copied() {
                let entry = storage.reserves.entry(c).or_insert(0.0);
                if *entry < 500.0 {
                    *entry = 500.0;
                }
            }
            info!("client_bevy admin: refilled reserves on {fac_id}");
        }
    }

    // Apply per-commodity reserve deltas + new-commodity inserts
    // captured by the buttons inside the read-only render closure.
    if !reserves_deltas.is_empty() || add_commodity.is_some() {
        if let Ok(mut storage) = storage_mut_q.get_mut(entity) {
            for (c, d) in reserves_deltas {
                let entry = storage.reserves.entry(c).or_insert(0.0);
                *entry = (*entry + d).max(0.0);
            }
            if let Some(c) = add_commodity {
                storage.reserves.entry(c).or_insert(100.0);
            }
        }
    }

    if !still_open {
        selected.0 = None;
    }
}
