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
    mut sim: ResMut<Sim>,
    mut state: ResMut<MarketsState>,
) {
    use sim_core::agents::market::{
        MarketHistory, MarketIdentity, MarketPricing, MARKET_CRISIS_SHORTAGE_TICKS,
    };
    use sim_core::economy::commodities::Commodity;
    // Phase 20d: trend sparkline rendering — see `draw_sparkline`
    // helper below the panel function.

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
        /// Phase 20d: per-commodity time series — `(tick, price, supply)`
        /// flattened from `MarketHistory.trend_samples`. The UI's
        /// sparkline draws these in chronological order; oldest at the
        /// left edge, newest at the right.
        trend: Vec<(Commodity, Vec<(u64, f32, f32)>)>,
    }

    let mut rows: Vec<MarketRow> = Vec::new();
    let entities: Vec<(Entity, String)> = {
        let mut q = sim.store.world.query::<(Entity, &MarketIdentity)>();
        q.iter(&sim.store.world)
            .map(|(e, id)| (e, id.facility_location.clone()))
            .collect()
    };
    for (entity, location) in entities {
        let pricing = sim
            .store
            .world
            .get::<MarketPricing>(entity)
            .map(|p| p.clone());
        let history = sim
            .store
            .world
            .get::<MarketHistory>(entity)
            .map(|h| h.clone());
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

        // Phase 20d: flatten trend_samples into per-commodity series.
        // `MarketHistory.trend_samples` carries one sample per
        // `MARKET_TREND_SAMPLE_INTERVAL_BASE` ticks, each holding the
        // full `prices` + `supply` HashMaps; the sparkline view wants
        // it pivoted: per-commodity `Vec<(tick, price, supply)>`.
        let mut trend_by_commodity: std::collections::HashMap<
            Commodity,
            Vec<(u64, f32, f32)>,
        > = std::collections::HashMap::new();
        for sample in history.trend_samples.iter() {
            for (commodity, &price) in &sample.prices {
                let supply = sample.supply.get(commodity).copied().unwrap_or(0.0);
                trend_by_commodity
                    .entry(*commodity)
                    .or_default()
                    .push((sample.tick, price, supply));
            }
        }
        let mut trend: Vec<(Commodity, Vec<(u64, f32, f32)>)> = trend_by_commodity
            .into_iter()
            .filter(|(_, v)| v.len() >= 2)
            .collect();
        trend.sort_by(|a, b| a.0.as_str().cmp(b.0.as_str()));

        rows.push(MarketRow {
            location,
            prices,
            supply,
            demand,
            shortage_ticks: shortages,
            crisis,
            any_short,
            trend,
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
        .show(ctx.ctx_mut().unwrap(), |ui| {
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

                        // Phase 20d: trends — per-commodity sparkline
                        // pair (price + supply) so users can spot
                        // sustained shortages, supply chain backups, or
                        // recovery curves at a glance. Only renders
                        // when ≥2 samples exist for at least one
                        // commodity (cold-start markets show nothing).
                        if !row.trend.is_empty() {
                            ui.add_space(4.0);
                            egui::CollapsingHeader::new(
                                egui::RichText::new("📈 Trends")
                                    .strong()
                                    .color(theme::PRIMARY),
                            )
                            .id_salt(format!("trends_hdr_{}", row.location))
                            .default_open(false)
                            .show(ui, |ui| {
                                ui.label(
                                    egui::RichText::new(
                                        "price (cyan) · supply (amber) — newest at right",
                                    )
                                    .small()
                                    .color(theme::TEXT_DIM),
                                );
                                for (commodity, samples) in &row.trend {
                                    ui.horizontal(|ui| {
                                        ui.add_sized(
                                            [70.0, 32.0],
                                            egui::Label::new(
                                                egui::RichText::new(commodity.as_str())
                                                    .monospace(),
                                            ),
                                        );
                                        draw_trend_sparkline(ui, samples);
                                        let last_p = samples
                                            .last()
                                            .map(|(_, p, _)| *p)
                                            .unwrap_or(0.0);
                                        let last_s = samples
                                            .last()
                                            .map(|(_, _, s)| *s)
                                            .unwrap_or(0.0);
                                        ui.add_sized(
                                            [80.0, 32.0],
                                            egui::Label::new(
                                                egui::RichText::new(format!(
                                                    "p {last_p:>5.1}  s {last_s:>5.0}"
                                                ))
                                                .monospace()
                                                .color(theme::TEXT_DIM),
                                            ),
                                        );
                                    });
                                }
                            });
                        }
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

/// Phase 20d: draw a two-line sparkline (price + supply) for one
/// commodity. Each series is min/max-normalised independently so a
/// commodity whose price hovers ~12 and whose supply hovers ~3000
/// still produces readable curves on the same canvas.
///
/// Hand-rolled rather than pulling in `egui_plot` — the sparkline is
/// ~30 line segments per commodity per market, well under the cost of
/// a dependency for the MVP. If the market panel grows zoom / hover-
/// tooltip / multi-line legends, switch to `egui_plot` later; the call
/// site is one line.
fn draw_trend_sparkline(ui: &mut egui::Ui, samples: &[(u64, f32, f32)]) {
    const W: f32 = 220.0;
    const H: f32 = 32.0;
    let (rect, _resp) = ui.allocate_exact_size(egui::vec2(W, H), egui::Sense::hover());
    if samples.len() < 2 {
        return;
    }
    let painter = ui.painter_at(rect);
    // Faint baseline so an empty / flat region still reads as "this is
    // a chart slot." Without it, a near-flat series looks like nothing.
    painter.line_segment(
        [
            egui::pos2(rect.left(), rect.bottom() - 0.5),
            egui::pos2(rect.right(), rect.bottom() - 0.5),
        ],
        egui::Stroke::new(1.0, theme::PRIMARY_DIM),
    );

    let n = samples.len();
    let plot_one = |painter: &egui::Painter, values: Vec<f32>, stroke: egui::Stroke| {
        let min = values.iter().copied().fold(f32::INFINITY, f32::min);
        let max = values.iter().copied().fold(f32::NEG_INFINITY, f32::max);
        let range = (max - min).max(0.001);
        let pts: Vec<egui::Pos2> = values
            .iter()
            .enumerate()
            .map(|(i, v)| {
                let x = rect.left() + rect.width() * i as f32 / (n - 1) as f32;
                let norm = (v - min) / range;
                let y = rect.bottom() - rect.height() * norm;
                egui::pos2(x, y)
            })
            .collect();
        for w in pts.windows(2) {
            painter.line_segment([w[0], w[1]], stroke);
        }
        // Latest-sample dot — bright so the eye snaps to "now."
        if let Some(last) = pts.last() {
            painter.circle_filled(*last, 2.5, stroke.color);
        }
    };

    let prices: Vec<f32> = samples.iter().map(|(_, p, _)| *p).collect();
    let supply: Vec<f32> = samples.iter().map(|(_, _, s)| *s).collect();
    plot_one(
        &painter,
        prices,
        egui::Stroke::new(1.5, theme::PRIMARY),
    );
    plot_one(
        &painter,
        supply,
        egui::Stroke::new(1.0, theme::WARN),
    );
}
