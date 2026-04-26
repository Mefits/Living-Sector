//! UI icons — SVG assets embedded at compile time via egui's
//! `include_image!`. The Godot client lifted the same SVG set into
//! `assets/icons/`; we reuse them here verbatim so the two clients
//! show the same visual vocabulary.
//!
//! Pipeline: `egui_extras` with the `svg` feature provides the
//! image loader (registered once on first frame in
//! `install_image_loaders`); `egui::Image::new(include_image!(...))`
//! references the bytes via a `bytes://` URI which the loader
//! decodes on first use and caches.
//!
//! Usage in top-bar / button code:
//!
//! ```ignore
//! ui.add(egui::Button::image_and_text(icons::pause(), "Pause"));
//! ```

use bevy_egui::egui;

/// Image size used in top-bar buttons. Square; 18×18 pairs well
/// with the default egui body font (~14px) — icon dominates without
/// pushing the whole row taller.
pub const TOP_BAR_ICON: f32 = 18.0;

/// Smaller variant for inline status / chip use.
#[allow(dead_code)]
pub const SMALL_ICON: f32 = 14.0;

// ---------------- UI control icons (assets/icons/ui/) -----------------

pub fn pause() -> egui::Image<'static> {
    egui::Image::new(egui::include_image!("../../assets/icons/ui/pause.svg"))
        .fit_to_exact_size(egui::vec2(TOP_BAR_ICON, TOP_BAR_ICON))
}

pub fn play() -> egui::Image<'static> {
    egui::Image::new(egui::include_image!("../../assets/icons/ui/play.svg"))
        .fit_to_exact_size(egui::vec2(TOP_BAR_ICON, TOP_BAR_ICON))
}

pub fn save() -> egui::Image<'static> {
    egui::Image::new(egui::include_image!("../../assets/icons/ui/save.svg"))
        .fit_to_exact_size(egui::vec2(TOP_BAR_ICON, TOP_BAR_ICON))
}

pub fn refresh() -> egui::Image<'static> {
    egui::Image::new(egui::include_image!("../../assets/icons/ui/refresh.svg"))
        .fit_to_exact_size(egui::vec2(TOP_BAR_ICON, TOP_BAR_ICON))
}

#[allow(dead_code)]
pub fn plus() -> egui::Image<'static> {
    egui::Image::new(egui::include_image!("../../assets/icons/ui/plus.svg"))
        .fit_to_exact_size(egui::vec2(TOP_BAR_ICON, TOP_BAR_ICON))
}

#[allow(dead_code)]
pub fn close() -> egui::Image<'static> {
    egui::Image::new(egui::include_image!("../../assets/icons/ui/close.svg"))
        .fit_to_exact_size(egui::vec2(TOP_BAR_ICON, TOP_BAR_ICON))
}

#[allow(dead_code)]
pub fn settings() -> egui::Image<'static> {
    egui::Image::new(egui::include_image!("../../assets/icons/ui/settings.svg"))
        .fit_to_exact_size(egui::vec2(TOP_BAR_ICON, TOP_BAR_ICON))
}

#[allow(dead_code)]
pub fn eye() -> egui::Image<'static> {
    egui::Image::new(egui::include_image!("../../assets/icons/ui/eye.svg"))
        .fit_to_exact_size(egui::vec2(TOP_BAR_ICON, TOP_BAR_ICON))
}

// ---------------- Panel icons (assets/icons/panels/) -----------------

pub fn ships() -> egui::Image<'static> {
    egui::Image::new(egui::include_image!("../../assets/icons/panels/ships.svg"))
        .fit_to_exact_size(egui::vec2(TOP_BAR_ICON, TOP_BAR_ICON))
}

pub fn contracts() -> egui::Image<'static> {
    egui::Image::new(egui::include_image!(
        "../../assets/icons/panels/contracts.svg"
    ))
    .fit_to_exact_size(egui::vec2(TOP_BAR_ICON, TOP_BAR_ICON))
}

pub fn factions() -> egui::Image<'static> {
    egui::Image::new(egui::include_image!(
        "../../assets/icons/panels/factions.svg"
    ))
    .fit_to_exact_size(egui::vec2(TOP_BAR_ICON, TOP_BAR_ICON))
}

pub fn market() -> egui::Image<'static> {
    egui::Image::new(egui::include_image!("../../assets/icons/panels/market.svg"))
        .fit_to_exact_size(egui::vec2(TOP_BAR_ICON, TOP_BAR_ICON))
}

pub fn pops() -> egui::Image<'static> {
    egui::Image::new(egui::include_image!("../../assets/icons/panels/pops.svg"))
        .fit_to_exact_size(egui::vec2(TOP_BAR_ICON, TOP_BAR_ICON))
}

#[allow(dead_code)]
pub fn perf() -> egui::Image<'static> {
    egui::Image::new(egui::include_image!("../../assets/icons/panels/perf.svg"))
        .fit_to_exact_size(egui::vec2(TOP_BAR_ICON, TOP_BAR_ICON))
}

pub fn events() -> egui::Image<'static> {
    egui::Image::new(egui::include_image!("../../assets/icons/panels/events.svg"))
        .fit_to_exact_size(egui::vec2(TOP_BAR_ICON, TOP_BAR_ICON))
}

pub fn factory() -> egui::Image<'static> {
    egui::Image::new(egui::include_image!(
        "../../assets/icons/panels/factory.svg"
    ))
    .fit_to_exact_size(egui::vec2(TOP_BAR_ICON, TOP_BAR_ICON))
}

pub fn barrier() -> egui::Image<'static> {
    egui::Image::new(egui::include_image!(
        "../../assets/icons/panels/barrier.svg"
    ))
    .fit_to_exact_size(egui::vec2(TOP_BAR_ICON, TOP_BAR_ICON))
}

pub fn ledger() -> egui::Image<'static> {
    egui::Image::new(egui::include_image!("../../assets/icons/panels/ledger.svg"))
        .fit_to_exact_size(egui::vec2(TOP_BAR_ICON, TOP_BAR_ICON))
}

pub fn add_ship() -> egui::Image<'static> {
    egui::Image::new(egui::include_image!(
        "../../assets/icons/panels/add-ship.svg"
    ))
    .fit_to_exact_size(egui::vec2(TOP_BAR_ICON, TOP_BAR_ICON))
}

pub fn add_facility() -> egui::Image<'static> {
    egui::Image::new(egui::include_image!(
        "../../assets/icons/panels/add-facility.svg"
    ))
    .fit_to_exact_size(egui::vec2(TOP_BAR_ICON, TOP_BAR_ICON))
}

#[allow(dead_code)]
pub fn destroy() -> egui::Image<'static> {
    egui::Image::new(egui::include_image!(
        "../../assets/icons/panels/destroy.svg"
    ))
    .fit_to_exact_size(egui::vec2(TOP_BAR_ICON, TOP_BAR_ICON))
}

/// One-shot system that registers the egui_extras image loaders
/// (PNG / SVG decoders). Required before any `egui::Image` will
/// resolve a `bytes://` URI. Uses a `Local<bool>` so it only fires
/// the first time we have a live egui context.
pub fn install_image_loaders(
    mut ctx: bevy_egui::EguiContexts,
    mut done: bevy::prelude::Local<bool>,
) {
    if *done {
        return;
    }
    egui_extras::install_image_loaders(ctx.ctx_mut());
    *done = true;
}
