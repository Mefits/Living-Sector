//! egui-based inspector panels.
//!
//! Pattern for every panel: a Bevy system that opens an `egui::Window`
//! and reads the `Sim` Resource directly. Zero marshalling, zero
//! snapshot layer — the inspector IS a live debugger with full
//! access to every hecs component. This is the key payoff of the
//! embedded architecture vs. the Godot client's WS-and-JSON path.
//!
//! `UiPlugin` is the wire-up: it registers every panel state Resource
//! and adds two `Update` system chains — one that runs in any
//! AppState (theme + main menu + options + load list), and one
//! gated on `AppState::InGame` for the live HUD. Each panel itself
//! lives in its own submodule with a `//!` top-level doc explaining
//! what it owns and how it reconciles its state.
//!
//! Phase-21 split moved the original ~5000-line god-module out into
//! a tree of focused submodules under `ui/`. mod.rs is now just the
//! `UiPlugin` builder.

use bevy::prelude::*;
use bevy_egui::EguiPlugin;

mod construction;
mod context;
mod contracts;
mod events;
mod facility;
mod factions;
mod format;
mod help;
mod icons;
mod labels;
mod lifecycle;
mod markets;
mod menus;
mod minimap;
mod panel_stack;
mod perf;
mod populations;
mod retirements;
mod ship_details;
mod ship_list;
mod spawn_dialogs;
mod theme;
mod top_bar;

use construction::{construction_panel, ConstructionState};
pub use context::{ContextMenuRequest, ContextMenuTarget};
use context::context_menu;
use contracts::{contracts_panel, ContractsState};
use events::{events_panel, EventsState};
pub use facility::SelectedFacility;
use facility::{facility_details_panel, facility_list_panel, FacilityListState};
use factions::{factions_panel, FactionsState};
use help::{help_panel, HelpState};
use labels::{
    body_labels_panel, construction_labels_panel, facility_labels_panel, ship_labels_panel,
    BodyLabelsState,
};
use lifecycle::{
    auto_load_from_env, main_menu_panel, new_universe_dialog, save_list_panel,
    NewUniverseDialogState, SaveListState,
};
use markets::{markets_panel, MarketsState};
use menus::{options_panel, pause_menu, OptionsState, PauseMenuState};
use minimap::{minimap_panel, MinimapState};
pub use panel_stack::{CloseTopRequest, OpenPanelStack};
use panel_stack::{close_top_panel, keyboard_shortcuts, reconcile_panel_stack};
use perf::{perf_overlay, track_fps, PerfStats};
use populations::{populations_panel, PopulationsState};
use retirements::{retirements_panel, RetirementsState};
use ship_details::ship_details_panel;
pub use ship_list::SelectedShip;
use ship_list::{ship_list, ShipListState};
use spawn_dialogs::{
    add_facility_dialog, add_ship_dialog, AddFacilityDialogState, AddShipDialogState,
};
use top_bar::{top_bar, top_bar_controls};

pub struct UiPlugin;

impl Plugin for UiPlugin {
    fn build(&self, app: &mut App) {
        // bevy_egui 0.39's EguiPlugin::default() enables multipass for
        // the primary context, which requires every UI system to run
        // inside EguiContextPass (not Update). Our ~20 panel systems
        // all run in Update; flipping multipass off keeps the prior
        // single-pass semantics with no scheduling churn. The field is
        // deprecated in 0.39 — revisit when bevy_egui drops it.
        #[allow(deprecated)]
        app.add_plugins(EguiPlugin {
                enable_multipass_for_primary_context: false,
                ..default()
            })
            .init_resource::<PerfStats>()
            .init_resource::<ShipListState>()
            .init_resource::<ContractsState>()
            .init_resource::<FactionsState>()
            .init_resource::<MarketsState>()
            .init_resource::<PopulationsState>()
            .init_resource::<SelectedShip>()
            .init_resource::<FacilityListState>()
            .init_resource::<SelectedFacility>()
            .init_resource::<RetirementsState>()
            .init_resource::<ConstructionState>()
            .init_resource::<MinimapState>()
            .init_resource::<BodyLabelsState>()
            .init_resource::<EventsState>()
            .init_resource::<PauseMenuState>()
            .init_resource::<HelpState>()
            .init_resource::<OptionsState>()
            .init_resource::<SaveListState>()
            .init_resource::<NewUniverseDialogState>()
            .init_resource::<AddShipDialogState>()
            .init_resource::<AddFacilityDialogState>()
            .init_resource::<ContextMenuRequest>()
            .init_resource::<OpenPanelStack>()
            .init_resource::<CloseTopRequest>()
            // Always-on systems: theme + image loaders init egui state
            // regardless of state, and the main_menu_panel needs to
            // render in MainMenu state. Options window is reachable
            // from both states (main menu's Options button + pause
            // menu's Options button) so it lives outside the gate.
            .add_systems(
                Update,
                (
                    icons::install_image_loaders,
                    theme::apply_theme,
                    auto_load_from_env,
                    main_menu_panel.run_if(in_state(crate::AppState::MainMenu)),
                    new_universe_dialog.run_if(in_state(crate::AppState::MainMenu)),
                    options_panel,
                    save_list_panel,
                ),
            )
            // In-game UI: gated on `AppState::InGame`. MainMenu hides
            // the entire HUD; only the title screen + 3D backdrop
            // show. The chain keeps system order stable — top bar
            // first so available_rect is correct for the labels
            // farther down.
            .add_systems(
                Update,
                (
                    track_fps,
                    top_bar_controls,
                    top_bar,
                    perf_overlay,
                    ship_list,
                    contracts_panel,
                    factions_panel,
                    markets_panel,
                    populations_panel,
                    ship_details_panel,
                    minimap_panel,
                    body_labels_panel,
                    events_panel,
                    reconcile_panel_stack,
                    keyboard_shortcuts,
                    close_top_panel,
                )
                    .chain()
                    .run_if(in_state(crate::AppState::InGame)),
            )
            // Second chain keeps each system's parameter list small
            // enough that Bevy's tuple-of-params limit isn't an issue,
            // and also separates the "details" family so ship_details
            // + facility_details don't compete for EguiContexts within
            // the same chain.
            //
            // `.after(top_bar)` is critical for the *_labels_panel
            // systems — they call `ctx.available_rect()` to find out
            // where the top bar ends, and that only returns the
            // reduced rect AFTER `top_bar` has shown.
            .add_systems(
                Update,
                (
                    facility_list_panel,
                    facility_details_panel,
                    retirements_panel,
                    construction_panel,
                    pause_menu,
                    add_ship_dialog,
                    add_facility_dialog,
                    context_menu,
                    help_panel,
                    construction_labels_panel,
                    facility_labels_panel,
                    ship_labels_panel,
                )
                    .chain()
                    .after(top_bar)
                    .run_if(in_state(crate::AppState::InGame)),
            );
    }
}

