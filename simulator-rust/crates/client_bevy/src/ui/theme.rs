//! egui theme — port of `client/scripts/ui/theme_palette.gd`.
//!
//! Applied once on first frame via a Local<bool>-guarded Update
//! system. The Godot client uses a holographic dark / cyan-accent
//! HUD; we mirror the same palette so panels read consistently
//! across both clients.

use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};

// --- Palette (mirrors theme_palette.gd) ----------------------------------

pub const PRIMARY: egui::Color32 = egui::Color32::from_rgb(0x55, 0xd0, 0xff);
pub const PRIMARY_DIM: egui::Color32 = egui::Color32::from_rgb(0x2a, 0x7e, 0xa0);
#[allow(dead_code)]
pub const PRIMARY_BRIGHT: egui::Color32 = egui::Color32::from_rgb(0xaa, 0xe5, 0xff);

pub const PANEL_BG: egui::Color32 = egui::Color32::from_rgba_premultiplied(10, 15, 25, 218);
pub const PANEL_BG_SOLID: egui::Color32 = egui::Color32::from_rgb(10, 15, 25);
pub const PANEL_HEADER_BG: egui::Color32 =
    egui::Color32::from_rgba_premultiplied(20, 35, 50, 230);
/// Holo-glass fill for chrome panels (top bar). Same tint as
/// PANEL_BG_SOLID but slightly lifted so the dot-grid + gradient
/// overlay (`paint_holo_chrome_overlay`) reads against it. Reads
/// as a faint navy plane against the black 3D world.
pub const CHROME_BG: egui::Color32 = egui::Color32::from_rgb(12, 22, 36);

pub const TEXT: egui::Color32 = egui::Color32::from_rgb(0xdf, 0xf3, 0xff);
pub const TEXT_DIM: egui::Color32 = egui::Color32::from_rgb(0x8a, 0xaa, 0xcc);
#[allow(dead_code)]
pub const TEXT_BRIGHT: egui::Color32 = egui::Color32::WHITE;

pub const SUCCESS: egui::Color32 = egui::Color32::from_rgb(0x7c, 0xd9, 0x92);
pub const WARN: egui::Color32 = egui::Color32::from_rgb(0xff, 0xb3, 0x47);
pub const DANGER: egui::Color32 = egui::Color32::from_rgb(0xff, 0x5a, 0x5a);

const SEPARATOR: egui::Color32 = egui::Color32::from_rgba_premultiplied(89, 140, 191, 89);

/// Pick a status colour for a value compared against
/// `(success_at_or_above, warn_at_or_above)` thresholds. Below the
/// warn threshold returns DANGER. Used by perf / ship / facility
/// readouts so all panels share the same SUCCESS/WARN/DANGER
/// banding instead of each redefining its own RGB ladder.
pub fn status_color(value: f32, thresholds: (f32, f32)) -> egui::Color32 {
    if value >= thresholds.0 {
        SUCCESS
    } else if value >= thresholds.1 {
        WARN
    } else {
        DANGER
    }
}

/// Same idea but for "lower is better" metrics (latencies, etc.)
/// where SUCCESS = below the green ceiling and DANGER = above the
/// amber ceiling.
pub fn status_color_inv(value: f32, thresholds: (f32, f32)) -> egui::Color32 {
    if value < thresholds.0 {
        SUCCESS
    } else if value < thresholds.1 {
        WARN
    } else {
        DANGER
    }
}

/// Section header — strong, larger, PRIMARY-tinted. Used by
/// ship-details / facility-details to break the long scroll into
/// labelled blocks (Identity / Position / Economy / …).
pub fn section_header(label: &str) -> egui::RichText {
    egui::RichText::new(label).strong().size(14.0).color(PRIMARY)
}

/// Caption — left-column key in two-column inspector grids.
/// TEXT_DIM so the value next to it pops.
pub fn caption(label: &str) -> egui::RichText {
    egui::RichText::new(label).color(TEXT_DIM)
}

/// Status colour for crew morale / health / inverse hunger /
/// fatigue scaled 0..=100. SUCCESS ≥ 70, WARN ≥ 40, DANGER below.
pub fn crew_bar_color(v: f32) -> egui::Color32 {
    status_color(v, (70.0, 40.0))
}

/// Set egui Visuals to the holographic dark palette. Local<bool>
/// guards so we only do it once after the egui context is live —
/// no cost on subsequent frames.
pub fn apply_theme(mut ctx: EguiContexts, mut done: Local<bool>) {
    if *done {
        return;
    }
    let ctx = ctx.ctx_mut().unwrap();
    let mut visuals = egui::Visuals::dark();

    visuals.window_fill = PANEL_BG_SOLID;
    visuals.panel_fill = PANEL_BG_SOLID;
    visuals.extreme_bg_color = egui::Color32::from_rgb(5, 8, 13);
    visuals.faint_bg_color = egui::Color32::from_rgba_premultiplied(15, 22, 33, 200);
    visuals.code_bg_color = egui::Color32::from_rgb(8, 12, 18);

    // Widget backgrounds across the four interaction states.
    visuals.widgets.noninteractive.bg_fill = PANEL_BG;
    visuals.widgets.noninteractive.weak_bg_fill = PANEL_BG;
    visuals.widgets.noninteractive.fg_stroke.color = TEXT;
    visuals.widgets.noninteractive.bg_stroke.color = SEPARATOR;

    visuals.widgets.inactive.bg_fill = PANEL_HEADER_BG;
    visuals.widgets.inactive.weak_bg_fill = PANEL_BG;
    visuals.widgets.inactive.fg_stroke.color = TEXT;

    visuals.widgets.hovered.bg_fill = egui::Color32::from_rgb(25, 50, 70);
    visuals.widgets.hovered.weak_bg_fill = egui::Color32::from_rgb(20, 35, 50);
    visuals.widgets.hovered.fg_stroke.color = PRIMARY;
    visuals.widgets.hovered.bg_stroke.color = PRIMARY;

    visuals.widgets.active.bg_fill = PRIMARY_DIM;
    visuals.widgets.active.weak_bg_fill = PRIMARY_DIM;
    visuals.widgets.active.fg_stroke.color = TEXT;

    visuals.widgets.open.bg_fill = PRIMARY_DIM;
    visuals.widgets.open.weak_bg_fill = PRIMARY_DIM;
    visuals.widgets.open.fg_stroke.color = TEXT;

    visuals.selection.bg_fill = PRIMARY_DIM;
    visuals.selection.stroke.color = PRIMARY;

    visuals.hyperlink_color = PRIMARY;
    visuals.override_text_color = Some(TEXT);

    // Tone down the default rounded corners — flatter panels read
    // more sci-fi, and the holographic look uses sharp edges.
    let mut style = (*ctx.style()).clone();
    style.visuals = visuals;
    style.spacing.item_spacing = egui::vec2(8.0, 4.0);
    style.spacing.button_padding = egui::vec2(8.0, 4.0);
    ctx.set_style(style);

    *done = true;
}
