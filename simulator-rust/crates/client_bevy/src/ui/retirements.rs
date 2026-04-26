//! Retirement ledger panel.
//!
//! Historical ship losses, loaded once at startup from the
//! `retired_ships` SQLite table (Phase-19g). Post-mortem view: name,
//! class, faction, final credits / fuel / morale, the strike
//! counters that tipped the ship into auto-retirement, the reason
//! string, and the tick they retired at.
//!
//! State: [`RetirementsState`] — open flag, sort key, sort direction,
//! filter substring. Auto-open via `CLIENT_BEVY_OPEN_PANELS`
//! containing `retired` / `retirements` / `all`.
//!
//! Reason colour-coding: `broke*` → DANGER, `hoard*` → WARN,
//! `admin` → PRIMARY, anything else → neutral TEXT (placeholder for
//! future strike kinds).
//!
//! The data is a frozen snapshot; new retirements during play
//! arrive in the underlying table but the panel reads from the
//! `Retirements` Resource which is only refreshed on startup.
//! Panel copy notes this so the user isn't surprised.
//!
//! Extracted from `ui/mod.rs` in the Phase-21 god-module split.

use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};

use super::{format::format_credits, theme};
use crate::sim::Retirements;

#[derive(Resource)]
pub(super) struct RetirementsState {
    pub open: bool,
    sort: RetirementSort,
    descending: bool,
    filter: String,
}

impl Default for RetirementsState {
    fn default() -> Self {
        let auto_open = std::env::var("CLIENT_BEVY_OPEN_PANELS")
            .map(|s| s.contains("retired") || s.contains("retirements") || s == "all")
            .unwrap_or(false);
        Self {
            open: auto_open,
            sort: RetirementSort::default(),
            descending: false,
            filter: String::new(),
        }
    }
}

#[derive(Default, PartialEq, Eq, Clone, Copy)]
enum RetirementSort {
    #[default]
    Tick,
    Name,
    Class,
    Faction,
    Credits,
    Reason,
}

pub(super) fn retirements_panel(
    mut ctx: EguiContexts,
    retirements: Res<Retirements>,
    mut state: ResMut<RetirementsState>,
) {
    let mut open = state.open;
    let mut sort = state.sort;
    let mut descending = state.descending;
    let mut filter = state.filter.clone();

    if !open {
        return;
    }

    let filter_lc = filter.to_lowercase();
    let mut filtered: Vec<&sim_db::persistence::RetirementRow> = retirements
        .0
        .iter()
        .filter(|r| {
            if filter_lc.is_empty() {
                return true;
            }
            r.name.to_lowercase().contains(&filter_lc)
                || r.agent_id.to_lowercase().contains(&filter_lc)
                || r.class.to_lowercase().contains(&filter_lc)
                || r.faction_id.to_lowercase().contains(&filter_lc)
                || r.final_location.to_lowercase().contains(&filter_lc)
                || r.reason.to_lowercase().contains(&filter_lc)
        })
        .collect();

    filtered.sort_by(|a, b| {
        let cmp = match sort {
            RetirementSort::Tick => a.retired_at_tick.cmp(&b.retired_at_tick),
            RetirementSort::Name => a.name.cmp(&b.name),
            RetirementSort::Class => a.class.cmp(&b.class),
            RetirementSort::Faction => a.faction_id.cmp(&b.faction_id),
            RetirementSort::Credits => a.final_credits.cmp(&b.final_credits),
            RetirementSort::Reason => a.reason.cmp(&b.reason),
        };
        if descending {
            cmp.reverse()
        } else {
            cmp
        }
    });

    let total = retirements.0.len();
    let shown = filtered.len();

    egui::Window::new(format!("Retired · {shown}/{total}"))
        .id(egui::Id::new("retired_window"))
        .default_width(860.0)
        .default_height(480.0)
        .open(&mut open)
        .show(ctx.ctx_mut().unwrap(), |ui| {
            ui.horizontal(|ui| {
                ui.label("filter:");
                ui.text_edit_singleline(&mut filter);
            });
            ui.label(
                egui::RichText::new(
                    "Snapshot of past decommissions. Newest-first by default. \
                     Loaded once at startup — new retirements during play \
                     will appear after a restart.",
                )
                .small()
                .color(theme::TEXT_DIM),
            );
            ui.separator();

            if total == 0 {
                ui.label(
                    egui::RichText::new("(no retirements yet — fresh DB or no decommissions)")
                        .italics()
                        .color(theme::TEXT_DIM),
                );
                return;
            }

            egui::ScrollArea::vertical().show(ui, |ui| {
                egui::Grid::new("retirements_grid")
                    .striped(true)
                    .num_columns(8)
                    .spacing([12.0, 3.0])
                    .show(ui, |ui| {
                        ret_sort_header(
                            ui,
                            "Tick",
                            &mut sort,
                            &mut descending,
                            RetirementSort::Tick,
                        );
                        ret_sort_header(
                            ui,
                            "Name",
                            &mut sort,
                            &mut descending,
                            RetirementSort::Name,
                        );
                        ret_sort_header(
                            ui,
                            "Class",
                            &mut sort,
                            &mut descending,
                            RetirementSort::Class,
                        );
                        ret_sort_header(
                            ui,
                            "Faction",
                            &mut sort,
                            &mut descending,
                            RetirementSort::Faction,
                        );
                        ui.label(
                            egui::RichText::new("Location")
                                .strong()
                                .color(theme::TEXT_DIM),
                        );
                        ret_sort_header(
                            ui,
                            "Credits",
                            &mut sort,
                            &mut descending,
                            RetirementSort::Credits,
                        );
                        ui.label(
                            egui::RichText::new("Morale / Fuel")
                                .strong()
                                .color(theme::TEXT_DIM),
                        );
                        ret_sort_header(
                            ui,
                            "Reason",
                            &mut sort,
                            &mut descending,
                            RetirementSort::Reason,
                        );
                        ui.end_row();

                        for r in &filtered {
                            ui.label(
                                egui::RichText::new(format!("{}", r.retired_at_tick)).monospace(),
                            );
                            ui.label(&r.name);
                            ui.label(egui::RichText::new(&r.class).color(theme::TEXT_DIM));
                            ui.label(egui::RichText::new(&r.faction_id).color(theme::TEXT_DIM));
                            ui.label(egui::RichText::new(&r.final_location).color(theme::TEXT_DIM));
                            ui.label(
                                egui::RichText::new(format_credits(r.final_credits)).monospace(),
                            );
                            ui.label(
                                egui::RichText::new(format!(
                                    "{} / {}",
                                    r.final_crew_morale, r.final_fuel_pct
                                ))
                                .monospace()
                                .color(theme::TEXT_DIM),
                            );
                            ui.colored_label(reason_color(&r.reason), &r.reason);
                            ui.end_row();
                        }
                    });
            });
        });

    state.open = open;
    state.filter = filter;
    state.sort = sort;
    state.descending = descending;
}

fn ret_sort_header(
    ui: &mut egui::Ui,
    label: &str,
    current: &mut RetirementSort,
    descending: &mut bool,
    target: RetirementSort,
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
            // Tick + credits default descending (newest / richest
            // first); text columns ascending.
            *descending = matches!(target, RetirementSort::Tick | RetirementSort::Credits,);
        }
    }
}

fn reason_color(reason: &str) -> egui::Color32 {
    // Theme-mapped colouring against the known strike kinds.
    // Anything else (future causes) renders neutral TEXT.
    let lc = reason.to_lowercase();
    if lc.contains("broke") {
        theme::DANGER
    } else if lc.contains("hoard") {
        theme::WARN
    } else if lc.contains("admin") {
        theme::PRIMARY
    } else {
        theme::TEXT
    }
}
