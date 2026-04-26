//! Factions panel — ledger + pairwise relations matrix.
//!
//! Two sections in one egui::Window:
//!   1. **Ledger** — per-faction row: treasury, ship count, facility
//!      count, active subsidies, home system. Sortable by clicking
//!      any column header. Treasury banding mirrors the broke-strike
//!      threshold (SUCCESS ≥ 10k, WARN ≥ 2k, DANGER below).
//!   2. **Relations** — every canonical (a, b) pair from
//!      `sim.store.relations`: standing in [-100, 100] and current
//!      treaty kind. Matrix is small (≤ 8 factions → 28 pairs) so a
//!      plain scrolling grid is fine.
//!
//! State: [`FactionsState`] — open flag, sort key, sort direction.
//! Auto-open via `CLIENT_BEVY_OPEN_PANELS=factions|all`.
//!
//! Ship + facility counts are built per-frame by walking the world
//! once for each kind — at <500 agents that's trivial vs the rest of
//! the UI cost.
//!
//! Extracted from `ui/mod.rs` in the Phase-21 god-module split.

use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};

use super::{format::format_credits, theme};
use crate::sim::Sim;

#[derive(Resource)]
pub(super) struct FactionsState {
    pub open: bool,
    sort: FactionSort,
    descending: bool,
}

impl Default for FactionsState {
    fn default() -> Self {
        let auto_open = std::env::var("CLIENT_BEVY_OPEN_PANELS")
            .map(|s| s.contains("factions") || s == "all")
            .unwrap_or(false);
        Self {
            open: auto_open,
            sort: FactionSort::default(),
            descending: false,
        }
    }
}

#[derive(Default, PartialEq, Eq, Clone, Copy)]
enum FactionSort {
    #[default]
    Name,
    Treasury,
    Ships,
    Facilities,
    Subsidies,
}

struct FactionRow {
    name: String,
    home_system: String,
    faction_type: String,
    treasury: i64,
    ships: u32,
    facilities: u32,
    subsidies: u32,
}

pub(super) fn factions_panel(
    mut ctx: EguiContexts,
    sim: Res<Sim>,
    mut state: ResMut<FactionsState>,
) {
    use sim_core::agents::{
        facility::FacilityIdentity, faction::FactionData, faction_relations::TreatyKind,
        ship::ShipIdentity,
    };
    use std::collections::HashMap;

    let mut open = state.open;
    let mut sort = state.sort;
    let mut descending = state.descending;

    if !open {
        return;
    }

    // Ship + facility counts per faction id, built once.
    let mut ship_counts: HashMap<String, u32> = HashMap::new();
    for (_e, id) in sim.store.world.query::<&ShipIdentity>().iter() {
        *ship_counts.entry(id.faction_id.clone()).or_insert(0) += 1;
    }
    let mut fac_counts: HashMap<String, u32> = HashMap::new();
    for (_e, id) in sim.store.world.query::<&FacilityIdentity>().iter() {
        *fac_counts.entry(id.faction_id.clone()).or_insert(0) += 1;
    }

    let mut rows: Vec<FactionRow> = sim
        .store
        .world
        .query::<&FactionData>()
        .iter()
        .map(|(_e, f)| FactionRow {
            name: f.name.clone(),
            home_system: f.home_system.clone(),
            faction_type: f.faction_type.clone(),
            treasury: f.treasury,
            ships: ship_counts.get(&f.id).copied().unwrap_or(0),
            facilities: fac_counts.get(&f.id).copied().unwrap_or(0),
            subsidies: f.active_subsidies,
        })
        .collect();

    rows.sort_by(|a, b| {
        let cmp = match sort {
            FactionSort::Name => a.name.cmp(&b.name),
            FactionSort::Treasury => a.treasury.cmp(&b.treasury),
            FactionSort::Ships => a.ships.cmp(&b.ships),
            FactionSort::Facilities => a.facilities.cmp(&b.facilities),
            FactionSort::Subsidies => a.subsidies.cmp(&b.subsidies),
        };
        if descending {
            cmp.reverse()
        } else {
            cmp
        }
    });

    egui::Window::new(format!("Factions · {}", rows.len()))
        .id(egui::Id::new("factions_window"))
        .default_width(720.0)
        .default_height(520.0)
        .open(&mut open)
        .show(ctx.ctx_mut(), |ui| {
            ui.label(egui::RichText::new("Ledger").strong().color(theme::PRIMARY));
            egui::Grid::new("factions_ledger_grid")
                .striped(true)
                .num_columns(6)
                .spacing([12.0, 3.0])
                .show(ui, |ui| {
                    faction_sort_header(
                        ui,
                        "Faction",
                        &mut sort,
                        &mut descending,
                        FactionSort::Name,
                    );
                    ui.label(
                        egui::RichText::new("System")
                            .strong()
                            .color(theme::TEXT_DIM),
                    );
                    faction_sort_header(
                        ui,
                        "Treasury",
                        &mut sort,
                        &mut descending,
                        FactionSort::Treasury,
                    );
                    faction_sort_header(
                        ui,
                        "Ships",
                        &mut sort,
                        &mut descending,
                        FactionSort::Ships,
                    );
                    faction_sort_header(
                        ui,
                        "Fac",
                        &mut sort,
                        &mut descending,
                        FactionSort::Facilities,
                    );
                    faction_sort_header(
                        ui,
                        "Subs",
                        &mut sort,
                        &mut descending,
                        FactionSort::Subsidies,
                    );
                    ui.end_row();

                    for r in &rows {
                        // Faction name strong, type as small dim
                        // suffix so the row name stands out.
                        ui.horizontal(|ui| {
                            ui.label(egui::RichText::new(&r.name).strong());
                            ui.label(
                                egui::RichText::new(format!("({})", r.faction_type))
                                    .small()
                                    .color(theme::TEXT_DIM),
                            );
                        });
                        ui.label(egui::RichText::new(&r.home_system).color(theme::TEXT_DIM));
                        // Treasury banding via theme helper —
                        // SUCCESS ≥ 10k, WARN ≥ 2k, DANGER below.
                        // Mirrors the broke-strike threshold the
                        // sim uses for bailouts.
                        ui.colored_label(
                            theme::status_color(r.treasury as f32, (10_000.0, 2_000.0)),
                            egui::RichText::new(format_credits(r.treasury)).monospace(),
                        );
                        ui.label(egui::RichText::new(format!("{}", r.ships)).monospace());
                        ui.label(egui::RichText::new(format!("{}", r.facilities)).monospace());
                        ui.label(egui::RichText::new(format!("{}", r.subsidies)).monospace());
                        ui.end_row();
                    }
                });

            ui.separator();
            ui.label(
                egui::RichText::new("Relations")
                    .strong()
                    .color(theme::PRIMARY),
            );
            ui.label(
                egui::RichText::new("canonical pairs · standing in [-100, 100]")
                    .small()
                    .color(theme::TEXT_DIM),
            );

            egui::ScrollArea::vertical()
                .id_salt("relations_scroll")
                .max_height(240.0)
                .show(ui, |ui| {
                    egui::Grid::new("relations_grid")
                        .striped(true)
                        .num_columns(4)
                        .spacing([10.0, 2.0])
                        .show(ui, |ui| {
                            for header in ["A", "B", "Standing", "Treaty"] {
                                ui.label(
                                    egui::RichText::new(header).strong().color(theme::TEXT_DIM),
                                );
                            }
                            ui.end_row();

                            let mut pairs: Vec<_> = sim.store.relations.iter().collect();
                            pairs.sort_by(|(ka, _), (kb, _)| ka.cmp(kb));

                            for ((a, b), state) in pairs {
                                ui.label(egui::RichText::new(a).color(theme::TEXT_DIM));
                                ui.label(b);
                                // Standing: SUCCESS ≥ 25, neutral
                                // band TEXT, DANGER ≤ -25.
                                let s_color = if state.standing >= 25 {
                                    theme::SUCCESS
                                } else if state.standing <= -25 {
                                    theme::DANGER
                                } else {
                                    theme::TEXT
                                };
                                ui.colored_label(
                                    s_color,
                                    egui::RichText::new(format!("{:+}", state.standing))
                                        .monospace(),
                                );
                                // Treaty palette: Allied/TradePact
                                // green-on-cyan, Neutral text,
                                // Tense/Hostile/War warming reds.
                                let t_color = match state.treaty {
                                    TreatyKind::Allied => theme::PRIMARY,
                                    TreatyKind::TradePact => theme::SUCCESS,
                                    TreatyKind::Neutral => theme::TEXT_DIM,
                                    TreatyKind::Tense => theme::WARN,
                                    TreatyKind::Hostile | TreatyKind::War => theme::DANGER,
                                };
                                ui.colored_label(t_color, state.treaty.as_str());
                                ui.end_row();
                            }
                        });
                });
        });

    state.open = open;
    state.sort = sort;
    state.descending = descending;
}

fn faction_sort_header(
    ui: &mut egui::Ui,
    label: &str,
    current: &mut FactionSort,
    descending: &mut bool,
    target: FactionSort,
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
    // Mirror sort_header (ship list): PRIMARY tint when this column
    // is the active sort, TEXT_DIM otherwise; frameless button.
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
            // Treasury / ships / facilities / subsidies default to
            // descending so "biggest first" feels natural; name
            // defaults to ascending (A→Z).
            *descending = !matches!(target, FactionSort::Name);
        }
    }
}
