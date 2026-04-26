//! Events ticker panel.
//!
//! Scrollable list over the bounded `EventsLog` ring (drained from
//! `tick_chain.events: Vec<serde_json::Value>` after every sim tick).
//! Each row shows tick, kind, and a short human summary built from
//! the event JSON. Filter by kind substring; "follow tail" is
//! informational because the newest event always sits at the top of
//! the list (display order is newest-first).
//!
//! Parity goal with the old Godot `events_ticker.gd`: "can you see
//! what just happened in the economy?" — not exact column / format
//! reproduction.
//!
//! State: [`EventsState`]. Default-open is gated on
//! `CLIENT_BEVY_OPEN_PANELS` matching `events` or `all`.
//!
//! Extracted from `ui/mod.rs` in the Phase-21 god-module split.

use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};

use super::theme;
use crate::sim::EventsLog;

#[derive(Resource)]
pub(super) struct EventsState {
    pub open: bool,
    filter: String,
    follow_tail: bool,
}

impl Default for EventsState {
    fn default() -> Self {
        let auto_open = std::env::var("CLIENT_BEVY_OPEN_PANELS")
            .map(|s| s.contains("events") || s == "all")
            .unwrap_or(false);
        Self {
            open: auto_open,
            filter: String::new(),
            follow_tail: false,
        }
    }
}

pub(super) fn events_panel(
    mut ctx: EguiContexts,
    events: Res<EventsLog>,
    mut state: ResMut<EventsState>,
) {
    let mut open = state.open;
    let mut filter = state.filter.clone();
    let mut follow_tail = state.follow_tail;
    if !open {
        return;
    }

    let filter_lc = filter.to_lowercase();
    // Collect matching entries newest-first for display. The
    // underlying ring is oldest-at-front so we iterate in reverse.
    let filtered: Vec<(&u64, &serde_json::Value)> = events
        .0
        .iter()
        .rev()
        .map(|(t, v)| (t, v))
        .filter(|(_, v)| {
            if filter_lc.is_empty() {
                return true;
            }
            let kind = v.get("kind").and_then(|k| k.as_str()).unwrap_or("");
            kind.to_lowercase().contains(&filter_lc)
                || v.to_string().to_lowercase().contains(&filter_lc)
        })
        .take(500) // panel cap — ring is larger
        .collect();

    let total = events.0.len();
    let shown = filtered.len();

    egui::Window::new(format!("Events · {shown}/{total}"))
        .id(egui::Id::new("events_window"))
        .default_width(640.0)
        .default_height(420.0)
        .open(&mut open)
        .show(ctx.ctx_mut(), |ui| {
            ui.horizontal(|ui| {
                ui.label("filter kind:");
                ui.text_edit_singleline(&mut filter);
                ui.separator();
                ui.checkbox(&mut follow_tail, "follow tail");
            });
            ui.separator();

            // Panel renders newest-first so scrolling the ScrollArea
            // down goes into the past. The "follow tail" toggle is
            // informational only — the newest event always sits at
            // the top of the list, so no scroll positioning needed.
            // Kept as a checkbox for the user to indicate intent.
            let _ = follow_tail;
            egui::ScrollArea::vertical()
                .auto_shrink([false, false])
                .show(ui, |ui| {
                    egui::Grid::new("events_grid")
                        .striped(true)
                        .num_columns(3)
                        .spacing([10.0, 3.0])
                        .show(ui, |ui| {
                            for header in ["Tick", "Kind", "Detail"] {
                                ui.label(
                                    egui::RichText::new(header).strong().color(theme::TEXT_DIM),
                                );
                            }
                            ui.end_row();

                            for (tick, v) in filtered {
                                let kind = v.get("kind").and_then(|k| k.as_str()).unwrap_or("?");
                                let summary = event_summary(v);
                                ui.label(
                                    egui::RichText::new(format!("{tick}"))
                                        .monospace()
                                        .color(theme::TEXT_DIM),
                                );
                                ui.colored_label(event_kind_color(kind), kind);
                                ui.label(egui::RichText::new(summary).color(theme::TEXT_DIM));
                                ui.end_row();
                            }
                        });
                });
        });

    state.open = open;
    state.filter = filter;
    state.follow_tail = follow_tail;
}

fn event_kind_color(kind: &str) -> egui::Color32 {
    // Theme palette buckets by subject. Nothing load-bearing — just
    // visual scan help. Unknown kinds fall through to neutral TEXT.
    match kind {
        "ship_docked" | "ship_spawned" | "ship_leveled_up" | "ship_refitted" | "treaty_changed" => {
            theme::PRIMARY
        }
        "ship_decommissioned" | "ship_destroyed_with_cargo" | "contract_expired" => theme::DANGER,
        "contract_delivered"
        | "crew_mission_completed"
        | "passengers_arrived"
        | "market_recovered"
        | "facility_recovered"
        | "construction_completed" => theme::SUCCESS,
        "market_crisis" | "facility_starving" | "facility_abandoned" => theme::WARN,
        _ => theme::TEXT,
    }
}

fn event_summary(v: &serde_json::Value) -> String {
    // Build a short, scan-readable summary from the most common
    // fields. Falls back to the kind if we can't compose anything
    // meaningful. Trying to be exhaustive is a losing game since
    // new event kinds keep getting added; a few high-value fields
    // cover the bulk of output volume.
    let get = |k: &str| {
        v.get(k)
            .map(|x| x.to_string().trim_matches('"').to_string())
    };

    let pieces: Vec<String> = [
        "ship_id",
        "id",
        "location",
        "facility_id",
        "commodity",
        "reason",
        "a",
        "b",
        "to",
        "from",
    ]
    .iter()
    .filter_map(|k| get(k).map(|val| format!("{k}={val}")))
    .collect();
    if pieces.is_empty() {
        return v.to_string();
    }
    pieces.join(" · ")
}
