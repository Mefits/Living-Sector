//! Markets panel — collapsing per-location header + commodity grid.
//!
//! Walks the hecs world for every `MarketIdentity`, `MarketPricing`,
//! `MarketHistory` triple and assembles a per-location row. Sorted
//! into three tiers so the eye lands on problem spots first:
//!
//!   * crisis (any commodity ≥ MARKET_CRISIS_SHORTAGE_TICKS)
//!   * any active shortage
//!   * normal
//!
//! Within each tier rows are alphabetised on location.
//!
//! Per-location collapsing header shows the location name (tinted
//! WARN/DANGER if shortages active) plus a chip painted next to the
//! header (CRISIS / SHORT). Expanded body lists active shortages
//! first then a grid of every commodity (price / supply / demand).
//!
//! Price colour banding compares the spot price to that commodity's
//! `base_price`: ≥ 1.25× DANGER (scarcity), ≤ 0.75× SUCCESS (glut),
//! TEXT otherwise. Glance reads matter more than precise numbers in
//! a debug panel like this.
//!
//! State: [`MarketsState`] — open flag, location-substring filter,
//! only-shortages toggle. Auto-open via `CLIENT_BEVY_OPEN_PANELS=
//! markets|all`.
//!
//! Extracted from `ui/mod.rs` in the Phase-21 god-module split.

use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};

use super::theme;
use crate::sim::Sim;

#[derive(Resource)]
pub(super) struct MarketsState {
    pub open: bool,
    filter: String,
    only_shortages: bool,
}

impl Default for MarketsState {
    fn default() -> Self {
        let auto_open = std::env::var("CLIENT_BEVY_OPEN_PANELS")
            .map(|s| s.contains("markets") || s == "all")
            .unwrap_or(false);
        Self {
            open: auto_open,
            filter: String::new(),
            only_shortages: false,
        }
    }
}

pub(super) fn markets_panel(
    mut ctx: EguiContexts,
    sim: Res<Sim>,
    mut state: ResMut<MarketsState>,
) {
    use sim_core::agents::market::{
        MarketHistory, MarketIdentity, MarketPricing, MARKET_CRISIS_SHORTAGE_TICKS,
    };
    use sim_core::economy::commodities::Commodity;

    let mut open = state.open;
    let mut filter = state.filter.clone();
    let mut only_shortages = state.only_shortages;

    if !open {
        return;
    }

    // Collect one view-model per market. We query all three components
    // per entity via `query_one` below to keep borrow rules simple; at
    // ~40 markets this is trivially cheap.
    struct MarketRow {
        location: String,
        prices: Vec<(Commodity, f32)>,
        supply: Vec<(Commodity, f32)>,
        demand: Vec<(Commodity, f32)>,
        shortage_ticks: Vec<(Commodity, u32)>,
        crisis: bool,
        any_short: bool,
    }

    let mut rows: Vec<MarketRow> = Vec::new();
    let entities: Vec<_> = sim
        .store
        .world
        .query::<&MarketIdentity>()
        .iter()
        .map(|(e, id)| (e, id.facility_location.clone()))
        .collect();
    for (entity, location) in entities {
        let pricing = sim
            .store
            .world
            .query_one::<&MarketPricing>(entity)
            .ok()
            .and_then(|mut q| q.get().cloned());
        let history = sim
            .store
            .world
            .query_one::<&MarketHistory>(entity)
            .ok()
            .and_then(|mut q| q.get().cloned());
        let (Some(pricing), Some(history)) = (pricing, history) else {
            continue;
        };

        let mut prices: Vec<(Commodity, f32)> =
            pricing.prices.iter().map(|(c, v)| (*c, *v)).collect();
        prices.sort_by(|a, b| a.0.as_str().cmp(b.0.as_str()));
        let mut supply: Vec<(Commodity, f32)> =
            pricing.supply.iter().map(|(c, v)| (*c, *v)).collect();
        supply.sort_by(|a, b| a.0.as_str().cmp(b.0.as_str()));
        let mut demand: Vec<(Commodity, f32)> =
            pricing.demand.iter().map(|(c, v)| (*c, *v)).collect();
        demand.sort_by(|a, b| a.0.as_str().cmp(b.0.as_str()));
        let mut shortages: Vec<(Commodity, u32)> = history
            .shortage_ticks
            .iter()
            .filter(|(_, t)| **t > 0)
            .map(|(c, t)| (*c, *t))
            .collect();
        shortages.sort_by(|a, b| b.1.cmp(&a.1));

        let crisis = shortages
            .iter()
            .any(|(_, t)| *t >= MARKET_CRISIS_SHORTAGE_TICKS);
        let any_short = !shortages.is_empty();

        rows.push(MarketRow {
            location,
            prices,
            supply,
            demand,
            shortage_ticks: shortages,
            crisis,
            any_short,
        });
    }
    rows.sort_by(|a, b| {
        // Crises first, then shortages, then plain — each group
        // alphabetised. Makes the problem-spots jump to the top.
        let tier = |r: &MarketRow| -> u8 {
            if r.crisis {
                0
            } else if r.any_short {
                1
            } else {
                2
            }
        };
        tier(a).cmp(&tier(b)).then(a.location.cmp(&b.location))
    });

    let filter_lc = filter.to_lowercase();
    let filtered: Vec<&MarketRow> = rows
        .iter()
        .filter(|r| filter_lc.is_empty() || r.location.to_lowercase().contains(&filter_lc))
        .filter(|r| !only_shortages || r.any_short)
        .collect();

    let total = rows.len();
    let shown = filtered.len();

    egui::Window::new(format!("Markets · {shown}/{total}"))
        .id(egui::Id::new("markets_window"))
        .default_width(760.0)
        .default_height(520.0)
        .open(&mut open)
        .show(ctx.ctx_mut(), |ui| {
            ui.horizontal(|ui| {
                ui.label("filter:");
                ui.text_edit_singleline(&mut filter);
                ui.separator();
                ui.checkbox(&mut only_shortages, "only shortages");
            });
            ui.separator();

            egui::ScrollArea::vertical().show(ui, |ui| {
                for row in &filtered {
                    // Build the collapsing-header label inline so the
                    // tag (CRISIS / SHORT) sits next to the location
                    // name instead of below the section. The header
                    // accepts WidgetText, which won't take a styled
                    // RichText with background color out of the box —
                    // so we render the header via .show_unindented
                    // wrapped in a horizontal that paints location +
                    // chip side by side.
                    let header_text = match (row.crisis, row.any_short) {
                        (true, _) => Some((" CRISIS ", theme::DANGER)),
                        (false, true) => Some((" SHORT ", theme::WARN)),
                        _ => None,
                    };

                    let collapsing = egui::CollapsingHeader::new({
                        let mut t = egui::RichText::new(&row.location).strong();
                        if row.crisis {
                            t = t.color(theme::DANGER);
                        } else if row.any_short {
                            t = t.color(theme::WARN);
                        }
                        t
                    })
                    .id_salt(format!("market_hdr_{}", row.location));
                    let resp = collapsing.show(ui, |ui| {
                        if !row.shortage_ticks.is_empty() {
                            ui.label(
                                egui::RichText::new("Active shortages")
                                    .strong()
                                    .color(theme::WARN),
                            );
                            egui::Grid::new(format!("shortage_grid_{}", row.location))
                                .num_columns(2)
                                .spacing([10.0, 2.0])
                                .show(ui, |ui| {
                                    for (c, t) in &row.shortage_ticks {
                                        ui.label(c.as_str());
                                        let color = if *t >= MARKET_CRISIS_SHORTAGE_TICKS {
                                            theme::DANGER
                                        } else {
                                            theme::WARN
                                        };
                                        ui.colored_label(
                                            color,
                                            egui::RichText::new(format!("{t} ticks")).monospace(),
                                        );
                                        ui.end_row();
                                    }
                                });
                            ui.separator();
                        }

                        egui::Grid::new(format!("commodity_grid_{}", row.location))
                            .striped(true)
                            .num_columns(4)
                            .spacing([12.0, 2.0])
                            .show(ui, |ui| {
                                for header in ["Commodity", "Price", "Supply", "Demand"] {
                                    ui.label(
                                        egui::RichText::new(header).strong().color(theme::TEXT_DIM),
                                    );
                                }
                                ui.end_row();

                                // Union of commodities from the three maps — a
                                // commodity may appear in demand but not supply
                                // (or vice versa).
                                let mut commodities: Vec<Commodity> = row
                                    .prices
                                    .iter()
                                    .map(|(c, _)| *c)
                                    .chain(row.supply.iter().map(|(c, _)| *c))
                                    .chain(row.demand.iter().map(|(c, _)| *c))
                                    .collect();
                                commodities.sort_by_key(|c| c.as_str());
                                commodities.dedup();

                                for c in commodities {
                                    let price = row
                                        .prices
                                        .iter()
                                        .find(|(k, _)| *k == c)
                                        .map(|(_, v)| *v)
                                        .unwrap_or(c.base_price());
                                    let sup = row
                                        .supply
                                        .iter()
                                        .find(|(k, _)| *k == c)
                                        .map(|(_, v)| *v)
                                        .unwrap_or(0.0);
                                    let dem = row
                                        .demand
                                        .iter()
                                        .find(|(k, _)| *k == c)
                                        .map(|(_, v)| *v)
                                        .unwrap_or(0.0);

                                    ui.label(c.as_str());
                                    // Price banding vs the commodity's own
                                    // base — DANGER above 1.25× (scarcity),
                                    // SUCCESS below 0.75× (glut), TEXT in
                                    // the middle band. Glance reads >
                                    // precise number.
                                    let base = c.base_price();
                                    let price_color = if base > 0.0 {
                                        let r = price / base;
                                        if r >= 1.25 {
                                            theme::DANGER
                                        } else if r <= 0.75 {
                                            theme::SUCCESS
                                        } else {
                                            theme::TEXT
                                        }
                                    } else {
                                        theme::TEXT
                                    };
                                    ui.colored_label(
                                        price_color,
                                        egui::RichText::new(format!("{price:.1}")).monospace(),
                                    );
                                    ui.label(
                                        egui::RichText::new(format!("{sup:.0}"))
                                            .monospace()
                                            .color(theme::TEXT_DIM),
                                    );
                                    ui.label(
                                        egui::RichText::new(format!("{dem:.0}"))
                                            .monospace()
                                            .color(theme::TEXT_DIM),
                                    );
                                    ui.end_row();
                                }
                            });
                    });

                    // CRISIS / SHORT chip beside the header row,
                    // visible whether expanded or collapsed.
                    if let Some((label, color)) = header_text {
                        let header_rect = resp.header_response.rect;
                        let chip_pos =
                            egui::pos2(header_rect.right() + 8.0, header_rect.center().y);
                        ui.painter().text(
                            chip_pos,
                            egui::Align2::LEFT_CENTER,
                            label.trim(),
                            egui::FontId::proportional(11.0),
                            color,
                        );
                    }
                }
            });
        });

    state.open = open;
    state.filter = filter;
    state.only_shortages = only_shortages;
}
