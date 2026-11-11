//! Help popup — keyboard + mouse hotkey reference.
//!
//! Toggled via `?` / `H` (see `panel_stack::keyboard_shortcuts`) or
//! by the `?` button on the pause menu. Centered modal-ish window
//! (anchored, non-resizable) listing every shortcut as a single
//! striped grid: sim control, camera, selection, misc.
//!
//! State: [`HelpState`] — open flag only. No persistence.
//!
//! When adding a hotkey: update both this grid and the
//! corresponding handler in `panel_stack::keyboard_shortcuts`.
//!
//! Extracted from `ui/mod.rs` in the Phase-21 god-module split.

use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};

use super::theme;

#[derive(Resource, Default)]
pub(super) struct HelpState {
    pub open: bool,
}

pub(super) fn help_panel(mut ctx: EguiContexts, mut help: ResMut<HelpState>) {
    let mut open = help.open;
    if !open {
        return;
    }
    egui::Window::new("Help · Hotkeys")
        .anchor(egui::Align2::CENTER_CENTER, egui::vec2(0.0, 0.0))
        .collapsible(false)
        .resizable(false)
        .default_width(380.0)
        .open(&mut open)
        .show(ctx.ctx_mut().unwrap(), |ui| {
            egui::Grid::new("help_keys")
                .num_columns(2)
                .striped(true)
                .spacing([12.0, 4.0])
                .show(ui, |ui| {
                    let key =
                        |label: &str| egui::RichText::new(label).monospace().color(theme::PRIMARY);
                    let row = |ui: &mut egui::Ui, k: &str, desc: &str| {
                        ui.label(key(k));
                        ui.label(desc);
                        ui.end_row();
                    };
                    ui.label(theme::section_header("Sim control"));
                    ui.label("");
                    ui.end_row();
                    row(ui, "Space", "Pause / resume the sim");
                    row(
                        ui,
                        "Esc",
                        "Close top open panel; opens pause menu when none",
                    );
                    row(ui, "P", "Open the pause menu directly");
                    ui.label(theme::section_header("Camera"));
                    ui.label("");
                    ui.end_row();
                    row(ui, "Left-drag", "Orbit around focus point");
                    row(ui, "Middle-drag", "Orbit around focus point");
                    row(ui, "Right-drag", "Pan focus across plane");
                    row(ui, "Shift-Left-drag", "Pan focus across plane");
                    row(ui, "WASD", "Pan focus relative to camera");
                    row(ui, "Scroll / Pinch", "Zoom in / out");
                    ui.label(theme::section_header("Selection"));
                    ui.label("");
                    ui.end_row();
                    row(ui, "Left-click", "Select ship / facility");
                    row(
                        ui,
                        "Right-click",
                        "Context menu (Inspect / Follow / POV / Destroy)",
                    );
                    row(ui, "✕ Clear (top bar)", "Deselect");
                    ui.label(theme::section_header("Misc"));
                    ui.label("");
                    ui.end_row();
                    row(ui, "F12", "Screenshot to /tmp/bevy_screenshot.png");
                    row(ui, "?  /  H", "Show this help popup");
                });
        });
    help.open = open;
}
