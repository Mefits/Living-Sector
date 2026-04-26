//! Ship list panel — sortable, filterable roster of every ship.
//!
//! Per-frame snapshot of (id, name, class, faction, location,
//! credits, fuel%, goal) from the hecs world, then sort + filter +
//! render into an egui Grid. Click a row to set the [`SelectedShip`]
//! resource (read by the details panel + render layer for highlight).
//!
//! State: [`ShipListState`] — open flag, sort key, sort direction,
//! filter substring. Auto-open via `CLIENT_BEVY_OPEN_PANELS=ships|all`.
//!
//! Selection: [`SelectedShip`] is `pub` so the render layer can
//! query it for the selection ring; everything else stays
//! `pub(super)`.
//!
//! Performance: hard cap at PAGE_SIZE=500 rows so a 1600-ship world
//! with a permissive filter doesn't force egui through 1600 cells of
//! sort + render every frame. Top hits surface naturally as the
//! filter narrows.
//!
//! Extracted from `ui/mod.rs` in the Phase-21 god-module split.

use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};

use super::{format::format_credits, theme};
use crate::sim::Sim;

/// Persistent UI state for the ship list (sort key, search filter,
/// whether the window is open). Anything that needs to survive
/// between frames lives on this Resource.
#[derive(Resource)]
pub(super) struct ShipListState {
    pub open: bool,
    sort: ShipSort,
    descending: bool,
    filter: String,
}

impl Default for ShipListState {
    fn default() -> Self {
        // CLIENT_BEVY_OPEN_PANELS=ships|all auto-opens this panel
        // on boot — used by the visual-loop screenshot path so the
        // panel is visible at the auto-screenshot frame without
        // simulating a click.
        let auto_open = std::env::var("CLIENT_BEVY_OPEN_PANELS")
            .map(|s| s.contains("ships") || s == "all")
            .unwrap_or(false);
        Self {
            open: auto_open,
            sort: ShipSort::default(),
            descending: false,
            filter: String::new(),
        }
    }
}

#[derive(Default, PartialEq, Eq, Clone, Copy)]
enum ShipSort {
    #[default]
    Name,
    Class,
    Faction,
    Location,
}

/// One egui row worth of ship data, extracted from the hecs world
/// once per frame. Keeps the render loop's query work bounded — we
/// iterate hecs once, build a Vec, sort, then render.
struct ShipRow {
    id: String,
    name: String,
    class: String,
    faction: String,
    location: String,
    // Hover-tooltip fields. Read every frame for every ship — at
    // 1604 ships × 3 numeric pulls each that's 4800 hash lookups,
    // trivial vs the rest of UI cost.
    credits: i64,
    fuel_frac: f32,
    goal: String,
}

/// Currently-selected ship, written by a click in the ship list and
/// read by the details panel. `None` means no selection (details
/// window closes itself). Public so the render layer can use it to
/// highlight the matching Bevy entity.
#[derive(Resource, Default)]
pub struct SelectedShip(pub Option<String>);

pub(super) fn ship_list(
    mut ctx: EguiContexts,
    sim: Res<Sim>,
    mut state: ResMut<ShipListState>,
    mut selected: ResMut<SelectedShip>,
) {
    use sim_core::agents::ship::{ShipAI, ShipEconomy, ShipFuel, ShipIdentity, ShipPosition};

    // Snapshot the mutable fields we'll need inside egui closures so
    // the borrow checker doesn't choke on overlapping mut refs into
    // the ResMut. We write back at the end of the function.
    let mut open = state.open;
    let mut filter = state.filter.clone();
    let mut sort = state.sort;
    let mut descending = state.descending;

    if !open {
        return;
    }

    let rows: Vec<ShipRow> = sim
        .store
        .world
        .query::<(
            &ShipIdentity,
            &ShipPosition,
            &ShipEconomy,
            &ShipFuel,
            &ShipAI,
        )>()
        .iter()
        .map(|(_e, (id, pos, econ, fuel, ai))| ShipRow {
            id: id.id.clone(),
            name: id.name.clone(),
            class: id.class.clone(),
            faction: id.faction_id.clone(),
            location: pos
                .location_name
                .clone()
                .unwrap_or_else(|| "(in transit)".into()),
            credits: econ.credits,
            fuel_frac: fuel.fraction(),
            goal: ai.current_goal.clone(),
        })
        .collect();

    let filter_lc = filter.to_lowercase();
    let mut filtered: Vec<&ShipRow> = rows
        .iter()
        .filter(|r| {
            if filter_lc.is_empty() {
                return true;
            }
            r.name.to_lowercase().contains(&filter_lc)
                || r.id.to_lowercase().contains(&filter_lc)
                || r.class.to_lowercase().contains(&filter_lc)
                || r.faction.to_lowercase().contains(&filter_lc)
                || r.location.to_lowercase().contains(&filter_lc)
        })
        .collect();

    filtered.sort_by(|a, b| {
        let cmp = match sort {
            ShipSort::Name => a.name.cmp(&b.name),
            ShipSort::Class => a.class.cmp(&b.class),
            ShipSort::Faction => a.faction.cmp(&b.faction),
            ShipSort::Location => a.location.cmp(&b.location),
        };
        if descending {
            cmp.reverse()
        } else {
            cmp
        }
    });

    let shown = filtered.len();
    let total = rows.len();
    // Use ScrollArea + rows cap so 1600-entry worlds stay responsive.
    // egui handles its own virtualisation via `show_rows`; we cap to
    // PAGE_SIZE upfront so sort work doesn't blow up on pathological
    // filters. 500 is plenty for typical play.
    const PAGE_SIZE: usize = 500;
    let page: Vec<&ShipRow> = filtered.into_iter().take(PAGE_SIZE).collect();

    egui::Window::new(format!("Ships · {shown}/{total}"))
        .id(egui::Id::new("ships_window"))
        .default_width(640.0)
        .default_height(400.0)
        .open(&mut open)
        .show(ctx.ctx_mut().unwrap(), |ui| {
            ui.horizontal(|ui| {
                ui.label("filter:");
                ui.text_edit_singleline(&mut filter);
                if shown > PAGE_SIZE {
                    ui.label(
                        egui::RichText::new(format!("(top {} shown)", PAGE_SIZE))
                            .small()
                            .color(theme::TEXT_DIM),
                    );
                }
            });
            ui.separator();

            egui::ScrollArea::vertical().show(ui, |ui| {
                egui::Grid::new("ship_list_grid")
                    .striped(true)
                    .num_columns(7)
                    .spacing([12.0, 3.0])
                    .show(ui, |ui| {
                        sort_header(ui, "Name", &mut sort, &mut descending, ShipSort::Name);
                        sort_header(ui, "Class", &mut sort, &mut descending, ShipSort::Class);
                        sort_header(ui, "Faction", &mut sort, &mut descending, ShipSort::Faction);
                        sort_header(
                            ui,
                            "Location",
                            &mut sort,
                            &mut descending,
                            ShipSort::Location,
                        );
                        // Goal / Fuel / Credits aren't sortable yet —
                        // keep header styling consistent so the row
                        // reads as a single header band.
                        ui.label(egui::RichText::new("Goal").strong().color(theme::TEXT_DIM));
                        ui.label(egui::RichText::new("Fuel").strong().color(theme::TEXT_DIM));
                        ui.label(
                            egui::RichText::new("Credits")
                                .strong()
                                .color(theme::TEXT_DIM),
                        );
                        ui.end_row();

                        for row in &page {
                            // Name cell doubles as the row selector —
                            // clicking highlights and opens the details
                            // panel on this ship.
                            let is_sel = selected.0.as_deref() == Some(row.id.as_str());
                            if ui.selectable_label(is_sel, &row.name).clicked() {
                                selected.0 = Some(row.id.clone());
                            }
                            ui.label(egui::RichText::new(&row.class).color(theme::TEXT_DIM));
                            ui.label(egui::RichText::new(&row.faction).color(theme::TEXT_DIM));
                            // Location: italicise "(in transit)" so a
                            // moving ship reads differently from a
                            // docked one without colour-shouting it.
                            if row.location == "(in transit)" {
                                ui.label(
                                    egui::RichText::new(&row.location)
                                        .italics()
                                        .color(theme::TEXT_DIM),
                                );
                            } else {
                                ui.label(&row.location);
                            }
                            // Goal is the planner's current goal name,
                            // monospaced so list lines up.
                            ui.label(egui::RichText::new(&row.goal).small().monospace());
                            // Fuel %: SUCCESS ≥ 50%, WARN ≥ 20%,
                            // DANGER below — same banding the Godot
                            // ship_list uses (theme_palette colours).
                            let fuel_pct = row.fuel_frac * 100.0;
                            ui.colored_label(
                                theme::status_color(fuel_pct, (50.0, 20.0)),
                                format!("{fuel_pct:.0}%"),
                            );
                            // Credits: thousands-separated for
                            // readability at typical 1k-100k+ range.
                            ui.label(egui::RichText::new(format_credits(row.credits)).monospace());
                            ui.end_row();
                        }
                    });
            });
        });

    // Write the local snapshot back to the Resource for next frame.
    state.open = open;
    state.filter = filter;
    state.sort = sort;
    state.descending = descending;
}

fn sort_header(
    ui: &mut egui::Ui,
    label: &str,
    current: &mut ShipSort,
    descending: &mut bool,
    target: ShipSort,
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
    // Frameless so the header row reads as a single band rather
    // than a row of boxed buttons. Active sort gets PRIMARY tint;
    // others use TEXT_DIM so the active column stands out.
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
            *descending = false;
        }
    }
}
