//! Always-on performance overlay.
//!
//! Top-left anchored window with FPS, TPS (vs 8 × tick_mult target),
//! tick-compute p50/p99 (ms vs the 125 ms FixedUpdate budget), live
//! agent counts (ships / facilities / bodies / pops / factions /
//! contracts), world seed, and a collapsible "Phases (last tick µs)"
//! breakdown sorted by cost.
//!
//! [`PerfStats`] doubles as the rolling-window store for FPS samples
//! (last 60 frame durations) and TPS samples (last 60 (Instant, tick)
//! pairs). Keeping both on one Resource avoids a second
//! `init_resource` for the panel's `open` flag and keeps update +
//! display reading from the same place.
//!
//! [`track_fps`] runs every frame to refresh the rolling windows;
//! [`perf_overlay`] reads them. Splitting the update from the render
//! is normal Bevy ECS hygiene — the overlay would otherwise need a
//! `Local<Instant>` to track its own frame deltas.
//!
//! Auto-open via `CLIENT_BEVY_OPEN_PANELS=perf|all`. Default
//! closed because the always-on overlay competes with the Ships
//! toggle for the top-left corner during normal play; dev sessions
//! that want it visible can set the env var.
//!
//! Extracted from `ui/mod.rs` in the Phase-21 god-module split.

use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};
use std::time::{Duration, Instant};

use super::theme;
use crate::sim::{PhasePerf, Sim, TickPerf};

const FPS_WINDOW: usize = 60;
/// TPS sampling window — 60 entries × 1 sample-per-frame at 60 fps
/// is a 1-second window, plenty to smooth out tick-mult bursts
/// while still surfacing meaningful drops.
const TPS_WINDOW: usize = 60;

/// Rolling FPS window so the overlay doesn't flicker frame-to-frame.
/// Tracks the last N frame durations and averages them. Also carries
/// the panel's `open` flag — keeping it on the same Resource avoids
/// a second init_resource just for one bool.
#[derive(Resource)]
pub(super) struct PerfStats {
    frame_samples: Vec<Duration>,
    last_frame_instant: Instant,
    avg_fps: f32,
    /// Rolling window of (wall_time, sim_tick) samples for the
    /// derived ticks-per-second readout. Compared against the
    /// configured target (8 × tick_mult) to flag when the sim
    /// is falling behind. Bounded at TPS_WINDOW; older entries
    /// pop off the front each tracking pass.
    tick_samples: std::collections::VecDeque<(Instant, u64)>,
    avg_tps: f32,
    /// Whether the Perf window renders. Default true — the perf
    /// readout is the primary always-on overlay during dev. Top
    /// bar gives you a button to hide it when a panel needs the
    /// space (it's anchored top-left and fights for room with the
    /// Ships toggle).
    pub open: bool,
}

impl Default for PerfStats {
    fn default() -> Self {
        // Honour CLIENT_BEVY_OPEN_PANELS for parity with the other
        // panels — but default to closed for normal sessions. The
        // perf panel was the last one defaulting to open and felt
        // intrusive once the rest of the UX matured.
        let auto_open = std::env::var("CLIENT_BEVY_OPEN_PANELS")
            .map(|s| s.contains("perf") || s == "all")
            .unwrap_or(false);
        Self {
            frame_samples: Vec::with_capacity(FPS_WINDOW),
            last_frame_instant: Instant::now(),
            avg_fps: 0.0,
            tick_samples: std::collections::VecDeque::with_capacity(TPS_WINDOW),
            avg_tps: 0.0,
            open: auto_open,
        }
    }
}

pub(super) fn track_fps(mut stats: ResMut<PerfStats>, sim: Res<Sim>) {
    let now = Instant::now();
    let dt = now.saturating_duration_since(stats.last_frame_instant);
    stats.last_frame_instant = now;
    if stats.frame_samples.len() == FPS_WINDOW {
        stats.frame_samples.remove(0);
    }
    stats.frame_samples.push(dt);
    if !stats.frame_samples.is_empty() {
        let sum: Duration = stats.frame_samples.iter().sum();
        let avg_secs = sum.as_secs_f32() / stats.frame_samples.len() as f32;
        if avg_secs > 0.0 {
            stats.avg_fps = 1.0 / avg_secs;
        }
    }

    // Tick-rate sampling: record (wall_time, tick) each frame.
    // TPS = (newest_tick - oldest_tick) / window_seconds.
    let tick = sim.tick;
    if stats.tick_samples.len() >= TPS_WINDOW {
        stats.tick_samples.pop_front();
    }
    stats.tick_samples.push_back((now, tick));
    if let (Some(&(t0, k0)), Some(&(t1, k1))) =
        (stats.tick_samples.front(), stats.tick_samples.back())
    {
        let secs = t1.saturating_duration_since(t0).as_secs_f32();
        if secs > 0.05 {
            let dticks = k1.saturating_sub(k0) as f32;
            stats.avg_tps = dticks / secs;
        }
    }
}

pub(super) fn perf_overlay(
    mut ctx: EguiContexts,
    sim: Res<Sim>,
    mut stats: ResMut<PerfStats>,
    tick_perf: Res<TickPerf>,
    phase: Res<PhasePerf>,
) {
    if !stats.open {
        return;
    }
    let mut open = stats.open;
    egui::Window::new("Perf")
        // Anchor below the two-row top bar so the panel doesn't
        // sit on top of the panel-toggle row (≈52 px tall: one
        // row of controls, one row of panel toggles).
        .anchor(egui::Align2::LEFT_TOP, egui::vec2(8.0, 60.0))
        .default_width(220.0)
        .open(&mut open)
        .show(ctx.ctx_mut().unwrap(), |ui| {
            egui::Grid::new("perf_grid")
                .num_columns(2)
                .spacing([12.0, 4.0])
                .show(ui, |ui| {
                    // Helper: dim label column matches the holographic
                    // theme — keys read as muted captions, values pop
                    // in TEXT or status colour.
                    let key = |s: &str| egui::RichText::new(s).color(theme::TEXT_DIM);

                    ui.label(key("FPS"));
                    ui.colored_label(
                        theme::status_color(stats.avg_fps, (55.0, 30.0)),
                        format!("{:.0}", stats.avg_fps),
                    );
                    ui.end_row();

                    ui.label(key("Tick"));
                    ui.label(format!("{}", sim.tick));
                    ui.end_row();

                    // Sim TPS — actual ticks/sec from the rolling
                    // window, coloured against the configured target
                    // (DEFAULT_TICK_INTERVAL_S = 0.125 → 8 tps ×
                    // tick_mult). Green when keeping up, amber within
                    // ~25%, red when significantly behind.
                    ui.label(key("TPS"));
                    let target = 8.0 * sim.tick_mult.max(1) as f32;
                    let tps_color =
                        theme::status_color(stats.avg_tps, (target * 0.95, target * 0.75));
                    ui.colored_label(tps_color, format!("{:.1} / {:.0}", stats.avg_tps, target));
                    ui.end_row();

                    // Tick-compute p50/p99 (ms). FixedUpdate fires at
                    // 125 ms; well under means headroom for higher
                    // tick_mult. Approaching 125 ms = sim is the
                    // bottleneck.
                    let p50_ms = tick_perf.p50_us as f32 / 1000.0;
                    let p99_ms = tick_perf.p99_us as f32 / 1000.0;
                    ui.label(key("Tick p50"));
                    ui.colored_label(
                        theme::status_color_inv(p50_ms, (30.0, 80.0)),
                        format!("{p50_ms:.1} ms"),
                    );
                    ui.end_row();

                    ui.label(key("Tick p99"));
                    ui.colored_label(
                        theme::status_color_inv(p99_ms, (80.0, 125.0)),
                        format!("{p99_ms:.1} ms"),
                    );
                    ui.end_row();

                    ui.label(key("Ships"));
                    ui.label(format!("{}", sim.store.ship_by_id.len()));
                    ui.end_row();

                    ui.label(key("Facilities"));
                    ui.label(format!("{}", sim.store.facility_by_id.len()));
                    ui.end_row();

                    ui.label(key("Bodies"));
                    ui.label(format!("{}", sim.store.body_by_id.len()));
                    ui.end_row();

                    ui.label(key("Populations"));
                    ui.label(format!("{}", sim.store.population_by_id.len()));
                    ui.end_row();

                    ui.label(key("Factions"));
                    ui.label(format!("{}", sim.store.faction_by_id.len()));
                    ui.end_row();

                    ui.label(key("Contracts"));
                    ui.label(format!("{}", sim.store.contracts.iter().count()));
                    ui.end_row();

                    ui.label(key("World seed"));
                    ui.label(
                        egui::RichText::new(format!("{}", sim.world_seed))
                            .small()
                            .monospace(),
                    );
                    ui.end_row();
                });
            ui.separator();
            // Per-phase breakdown of the most recent tick — sums
            // approximately to tick_p50 (last-tick-wins for
            // tick_mult > 1). Names mirror the sim_server tick
            // phases. Sorted by decreasing cost so the dominant
            // phase is at the top.
            egui::CollapsingHeader::new("Phases (last tick µs)")
                .default_open(false)
                .show(ui, |ui| {
                    let mut rows: Vec<(&str, u64)> = vec![
                        ("ships", phase.ships_us),
                        ("apply1", phase.apply1_us),
                        ("apply2", phase.apply2_us),
                        ("facilities", phase.facilities_us),
                        ("markets", phase.markets_us),
                        ("populations", phase.populations_us),
                        ("factions", phase.factions_us),
                        ("relations", phase.relations_us),
                        ("regen", phase.regen_us),
                        ("crisis", phase.crisis_us),
                        ("dock_queue", phase.dock_queue_us),
                        ("drains", phase.drains_us),
                        ("bodies", phase.bodies_us),
                        ("events_log", phase.events_log_us),
                    ];
                    rows.sort_by(|a, b| b.1.cmp(&a.1));
                    egui::Grid::new("phase_grid")
                        .num_columns(2)
                        .spacing([10.0, 2.0])
                        .show(ui, |ui| {
                            for (name, us) in rows {
                                ui.label(egui::RichText::new(name).small().color(theme::TEXT_DIM));
                                ui.label(
                                    egui::RichText::new(format!("{:.2} ms", us as f32 / 1000.0))
                                        .small()
                                        .monospace(),
                                );
                                ui.end_row();
                            }
                        });
                });
            ui.separator();
            ui.label(
                egui::RichText::new("embedded sim — no network")
                    .small()
                    .italics()
                    .color(theme::TEXT_DIM),
            );
        });
    // Write the close-button click back so future frames respect
    // it. egui's Window builder writes `false` into `open` when the
    // user clicks the X header button.
    stats.open = open;
}
