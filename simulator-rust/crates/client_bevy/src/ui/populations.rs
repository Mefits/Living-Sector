//! Populations panel — per-pop census + sentiment + food + wealth.
//!
//! One row per population (~27 today). Columns cover the levers the
//! sim moves: count, sentiment, food satisfaction, total wealth, and
//! migration pressure. Sort by any numeric column; filter by
//! label/location/faction/demographic.
//!
//! Sentiment and food cells colour-code against their natural ranges
//! so stressed pops jump out:
//!   * sentiment ≥ 50 SUCCESS, ≥ 30 WARN, ≥ 0 mid-amber, < 0 DANGER
//!   * food: status_color banding (70 / 30) — same as ship fuel
//!   * migration ≥ 1.0 DANGER (about to migrate), ≥ 0.5 WARN
//!
//! State: [`PopulationsState`] — open flag, sort key, sort direction,
//! filter substring. Auto-open via `CLIENT_BEVY_OPEN_PANELS` matching
//! `pops` / `populations` / `all`.
//!
//! Locally-private helpers `sentiment_color`, `food_color`, and
//! `format_int` are panel-specific so they live alongside the panel
//! rather than in `ui::format`. Promote if a second panel needs them.
//!
//! Extracted from `ui/mod.rs` in the Phase-21 god-module split.

use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};

use super::{format::format_credits, theme};
use crate::sim::Sim;

#[derive(Resource)]
pub(super) struct PopulationsState {
    pub open: bool,
    sort: PopSort,
    descending: bool,
    filter: String,
}

impl Default for PopulationsState {
    fn default() -> Self {
        let auto_open = std::env::var("CLIENT_BEVY_OPEN_PANELS")
            .map(|s| s.contains("pops") || s.contains("populations") || s == "all")
            .unwrap_or(false);
        Self {
            open: auto_open,
            sort: PopSort::default(),
            descending: false,
            filter: String::new(),
        }
    }
}

#[derive(Default, PartialEq, Eq, Clone, Copy)]
enum PopSort {
    #[default]
    Label,
    Location,
    Count,
    Sentiment,
    Food,
    Wealth,
    Migration,
}

struct PopRow {
    label: String,
    demographic: String,
    location: String,
    faction: String,
    count: i64,
    sentiment: i32,
    food: i32,
    wealth: i64,
    // Migration pressure is f32; keep as f32 for display, sort via bits
    // so NaN doesn't panic.
    migration: f32,
}

pub(super) fn populations_panel(
    mut ctx: EguiContexts,
    _sim: Res<Sim>,
    mut state: ResMut<PopulationsState>,
    pops_q: Query<(
        &sim_core::agents::population::PopIdentity,
        &sim_core::agents::population::PopDemographics,
        &sim_core::agents::population::PopEconomy,
        &sim_core::agents::population::PopSentiment,
    )>,
) {
    let mut open = state.open;
    let mut sort = state.sort;
    let mut descending = state.descending;
    let mut filter = state.filter.clone();

    if !open {
        return;
    }

    let rows: Vec<PopRow> = {
        pops_q
            .iter()
            .map(|(id, demo, econ, sent)| PopRow {
                label: id.label.clone(),
                demographic: id.demographic.clone(),
                location: id.facility_location.clone(),
                faction: id.faction_id.clone(),
                count: demo.population_count,
                sentiment: sent.overall_sentiment,
                food: sent.food_satisfaction,
                wealth: econ.total_wealth,
                migration: demo.migration_pressure,
            })
            .collect()
    };

    let filter_lc = filter.to_lowercase();
    let mut filtered: Vec<&PopRow> = rows
        .iter()
        .filter(|r| {
            if filter_lc.is_empty() {
                return true;
            }
            r.label.to_lowercase().contains(&filter_lc)
                || r.location.to_lowercase().contains(&filter_lc)
                || r.faction.to_lowercase().contains(&filter_lc)
                || r.demographic.to_lowercase().contains(&filter_lc)
        })
        .collect();

    filtered.sort_by(|a, b| {
        let cmp = match sort {
            PopSort::Label => a.label.cmp(&b.label),
            PopSort::Location => a.location.cmp(&b.location),
            PopSort::Count => a.count.cmp(&b.count),
            PopSort::Sentiment => a.sentiment.cmp(&b.sentiment),
            PopSort::Food => a.food.cmp(&b.food),
            PopSort::Wealth => a.wealth.cmp(&b.wealth),
            // Bits-based ordering for f32 — safe for non-NaN values which
            // migration_pressure is by construction (clamped >= 0.0).
            PopSort::Migration => a
                .migration
                .partial_cmp(&b.migration)
                .unwrap_or(std::cmp::Ordering::Equal),
        };
        if descending {
            cmp.reverse()
        } else {
            cmp
        }
    });

    let total = rows.len();
    let shown = filtered.len();

    egui::Window::new(format!("Populations · {shown}/{total}"))
        .id(egui::Id::new("populations_window"))
        .default_width(820.0)
        .default_height(460.0)
        .open(&mut open)
        .show(ctx.ctx_mut().unwrap(), |ui| {
            ui.horizontal(|ui| {
                ui.label("filter:");
                ui.text_edit_singleline(&mut filter);
            });
            ui.separator();

            egui::ScrollArea::vertical().show(ui, |ui| {
                egui::Grid::new("pops_grid")
                    .striped(true)
                    .num_columns(8)
                    .spacing([12.0, 3.0])
                    .show(ui, |ui| {
                        pop_sort_header(ui, "Label", &mut sort, &mut descending, PopSort::Label);
                        ui.label(egui::RichText::new("Demo").strong().color(theme::TEXT_DIM));
                        pop_sort_header(
                            ui,
                            "Location",
                            &mut sort,
                            &mut descending,
                            PopSort::Location,
                        );
                        pop_sort_header(ui, "Count", &mut sort, &mut descending, PopSort::Count);
                        pop_sort_header(ui, "Sent", &mut sort, &mut descending, PopSort::Sentiment);
                        pop_sort_header(ui, "Food", &mut sort, &mut descending, PopSort::Food);
                        pop_sort_header(ui, "Wealth", &mut sort, &mut descending, PopSort::Wealth);
                        pop_sort_header(ui, "Mig", &mut sort, &mut descending, PopSort::Migration);
                        ui.end_row();

                        for r in &filtered {
                            ui.label(&r.label);
                            ui.label(egui::RichText::new(&r.demographic).color(theme::TEXT_DIM));
                            ui.label(egui::RichText::new(&r.location).color(theme::TEXT_DIM));
                            ui.label(egui::RichText::new(format_int(r.count)).monospace());
                            ui.colored_label(
                                sentiment_color(r.sentiment),
                                egui::RichText::new(format!("{}", r.sentiment)).monospace(),
                            );
                            ui.colored_label(
                                food_color(r.food),
                                egui::RichText::new(format!("{}", r.food)).monospace(),
                            );
                            ui.label(egui::RichText::new(format_credits(r.wealth)).monospace());
                            // Migration pressure: DANGER ≥ 1.0 (likely
                            // to migrate next tick), WARN ≥ 0.5
                            // (stress building), TEXT_DIM otherwise.
                            let mig_color = if r.migration >= 1.0 {
                                theme::DANGER
                            } else if r.migration >= 0.5 {
                                theme::WARN
                            } else {
                                theme::TEXT_DIM
                            };
                            ui.colored_label(
                                mig_color,
                                egui::RichText::new(format!("{:.2}", r.migration)).monospace(),
                            );
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

fn pop_sort_header(
    ui: &mut egui::Ui,
    label: &str,
    current: &mut PopSort,
    descending: &mut bool,
    target: PopSort,
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
    // Mirror the other panels: PRIMARY tint when active sort,
    // TEXT_DIM otherwise; frameless layout.
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
            // Numeric-y columns default to descending (biggest first),
            // text-y columns default to ascending.
            *descending = !matches!(target, PopSort::Label | PopSort::Location);
        }
    }
}

fn sentiment_color(s: i32) -> egui::Color32 {
    // Pop sentiment: SUCCESS ≥ 50 (content), WARN ≥ 30 (drift),
    // mid-band amber-ish below zero, DANGER strictly negative
    // (migration / unrest territory). Two amber tiers so the curve
    // is gentler than the binary status_color helper would give.
    if s >= 50 {
        theme::SUCCESS
    } else if s >= 30 {
        theme::WARN
    } else if s >= 0 {
        // Halfway between WARN and DANGER for the "low but not yet
        // crisis" band. Stays in the warm range rather than jumping
        // straight to red.
        egui::Color32::from_rgb(230, 150, 100)
    } else {
        theme::DANGER
    }
}

fn food_color(f: i32) -> egui::Color32 {
    // Food sat scale is roughly 0..=100. <30 is "emergency water"
    // territory; >70 is comfortable. Same SUCCESS / WARN / DANGER
    // banding as the rest of the panels.
    theme::status_color(f as f32, (70.0, 30.0))
}

fn format_int(n: i64) -> String {
    // Thousands separator for population counts so "1204000" reads
    // as "1,204,000" at a glance.
    let s = n.abs().to_string();
    let mut out = String::new();
    for (i, c) in s.chars().rev().enumerate() {
        if i > 0 && i % 3 == 0 {
            out.push(',');
        }
        out.push(c);
    }
    let result: String = out.chars().rev().collect();
    if n < 0 {
        format!("-{}", result)
    } else {
        result
    }
}
