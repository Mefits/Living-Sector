//! In-game pause menu + Options window.
//!
//! Both are anchored centre-screen, modal-ish (collapsible / resizable
//! disabled). They share enough flavour — same layout helpers, same
//! credits block, both reachable from the pause overlay — that they
//! co-habit a single module.
//!
//! ## [`pause_menu`]
//!
//! Triggered by Esc / `P` / the top-bar Menu button. While open the
//! sim is forced paused; closing restores the prior running state via
//! `PauseMenuState.was_running`. Buttons: Resume / Save As / Options
//! / Help / Return to Main Menu / Quit. "Save" is folded into "Save
//! As" because the embedded client has no live persistence worker —
//! every save is effectively a snapshot copy of the load-tick state.
//!
//! Closing on the Main Menu button transitions `AppState::MainMenu`
//! and pauses the sim — the universe stays loaded, so a subsequent
//! Start resumes from where we left off.
//!
//! ## [`options_panel`]
//!
//! Audio sliders only at the moment (music + SFX). Sliders write
//! directly to `crate::audio::AudioSettings`; an `apply_music_volume`
//! system in `crate::audio` watches the resource for changes and pushes
//! the new value to the live `AudioSink`. SFX volume applies on the
//! next one-shot — pre-baked .ogg samples don't track a running
//! volume.
//!
//! Extracted from `ui/mod.rs` in the Phase-21 god-module split.

use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};

use super::help::HelpState;
use super::lifecycle::credits_block;
use super::theme;
use crate::sim::Sim;

/// Options window — audio + display settings. Toggled from the
/// pause menu's "Options" button (and, in a later bundle, from the
/// main menu). State is just `open`; the actual settings live on
/// `crate::audio::AudioSettings` etc. so they stay valid when the
/// window is closed.
#[derive(Resource, Default)]
pub(super) struct OptionsState {
    pub open: bool,
}

pub(super) fn options_panel(
    mut ctx: EguiContexts,
    mut state: ResMut<OptionsState>,
    mut audio: ResMut<crate::audio::AudioSettings>,
) {
    let mut open = state.open;
    if !open {
        return;
    }
    egui::Window::new("Options")
        .id(egui::Id::new("options_window"))
        .anchor(egui::Align2::CENTER_CENTER, egui::vec2(0.0, 0.0))
        .collapsible(false)
        .resizable(false)
        .default_width(360.0)
        .open(&mut open)
        .show(ctx.ctx_mut().unwrap(), |ui| {
            ui.add_space(4.0);
            ui.label(theme::section_header("Audio"));
            ui.add_space(4.0);

            // Bevy's AudioSink::set_volume is linear gain; volumes
            // 0..=1 map directly. Capping the sliders at 1.0 keeps
            // the user from blowing out — boost beyond unity gain
            // requires HDR mixing we don't ship.
            egui::Grid::new("options_audio")
                .num_columns(2)
                .spacing([12.0, 8.0])
                .show(ui, |ui| {
                    ui.label(theme::caption("Music"));
                    ui.add(
                        egui::Slider::new(&mut audio.music_volume, 0.0..=1.0)
                            .show_value(true)
                            .fixed_decimals(2),
                    );
                    ui.end_row();

                    ui.label(theme::caption("SFX"));
                    ui.add(
                        egui::Slider::new(&mut audio.sfx_volume, 0.0..=1.0)
                            .show_value(true)
                            .fixed_decimals(2),
                    );
                    ui.end_row();
                });

            ui.add_space(4.0);
            ui.separator();
            ui.add_space(2.0);
            ui.label(
                egui::RichText::new("Music applies live; SFX applies on the next one-shot.")
                    .small()
                    .italics()
                    .color(theme::TEXT_DIM),
            );
        });
    state.open = open;
}

/// Modal-ish "Pause" menu. Esc toggles it (see `keyboard_shortcuts`).
/// While open the sim is forced paused; closing the menu restores
/// the prior running state. Buttons: Resume, Save As, Quit. Save is
/// folded into Save As since the embedded client has no live
/// persistence worker — every save is effectively a snapshot copy.
#[derive(Resource, Default)]
pub(super) struct PauseMenuState {
    pub open: bool,
    /// Sim's `running` state at the moment the menu was opened, so
    /// closing the menu restores that state instead of always
    /// resuming.
    pub was_running: bool,
}

#[allow(clippy::too_many_arguments)]
pub(super) fn pause_menu(
    mut ctx: EguiContexts,
    mut menu: ResMut<PauseMenuState>,
    mut sim: ResMut<Sim>,
    mut save_req: ResMut<crate::sim::SaveAsRequest>,
    mut help: ResMut<HelpState>,
    mut options: ResMut<OptionsState>,
    mut next_state: ResMut<NextState<crate::AppState>>,
    mut exit: MessageWriter<AppExit>,
) {
    if !menu.open {
        return;
    }
    egui::Window::new("Paused")
        .anchor(egui::Align2::CENTER_CENTER, egui::vec2(0.0, 0.0))
        .collapsible(false)
        .resizable(false)
        .default_width(280.0)
        .show(ctx.ctx_mut().unwrap(), |ui| {
            ui.vertical_centered(|ui| {
                ui.add_space(6.0);
                ui.label(
                    egui::RichText::new("Game paused")
                        .strong()
                        .size(16.0)
                        .color(theme::PRIMARY),
                );
                ui.add_space(8.0);
                let btn_size = egui::vec2(220.0, 32.0);
                if ui
                    .add_sized(btn_size, egui::Button::new("Resume (Esc)"))
                    .clicked()
                {
                    menu.open = false;
                    sim.running = menu.was_running;
                }
                ui.add_space(2.0);
                if ui
                    .add_sized(btn_size, egui::Button::new("Save As…"))
                    .on_hover_text(
                        "Write a timestamped VACUUM INTO snapshot of sim.db. \
                         Embedded client has no persistence worker yet, so the \
                         snapshot reflects the load tick rather than live state.",
                    )
                    .clicked()
                {
                    save_req.0 = true;
                }
                ui.add_space(2.0);
                if ui
                    .add_sized(btn_size, egui::Button::new("Options"))
                    .on_hover_text("Audio + display settings.")
                    .clicked()
                {
                    options.open = true;
                }
                ui.add_space(2.0);
                if ui
                    .add_sized(btn_size, egui::Button::new("Help (?)"))
                    .on_hover_text("Show the hotkey reference popup.")
                    .clicked()
                {
                    help.open = true;
                }
                ui.add_space(2.0);
                if ui
                    .add_sized(btn_size, egui::Button::new("Return to Main Menu"))
                    .on_hover_text(
                        "Pause the sim and go back to the title screen. \
                         The world stays loaded — Start resumes from here.",
                    )
                    .clicked()
                {
                    sim.running = false;
                    menu.open = false;
                    next_state.set(crate::AppState::MainMenu);
                }
                ui.add_space(2.0);
                if ui
                    .add_sized(
                        btn_size,
                        egui::Button::new(egui::RichText::new("Quit").color(theme::DANGER)),
                    )
                    .on_hover_text("Close the window.")
                    .clicked()
                {
                    exit.write(AppExit::Success);
                }
                ui.add_space(14.0);
                credits_block(ui);
                ui.add_space(6.0);
            });
        });
}
