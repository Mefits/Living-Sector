//! Esc-closes-most-recently-opened-panel stack + global keyboard
//! shortcuts.
//!
//! ## Why a stack?
//!
//! User mental model: clicking through inspector panels is exploration;
//! Esc should walk back. Without a stack, Esc would have to know which
//! panel "should" close (most-recently-opened? all at once?), and
//! either choice surprises someone.
//!
//! The stack is reconciled each frame from individual `*State.open`
//! flags by [`reconcile_panel_stack`] — toggling a panel from any path
//! (top-bar button, hotkey, programmatic) keeps the stack honest. Esc
//! pops the back into [`CloseTopRequest`]; [`close_top_panel`] mutates
//! the matching panel's open flag. The split is mechanical: Bevy
//! caps a system at 16 SystemParams and we have ~14 panel kinds.
//! Keeping the input + the mutation in separate systems keeps both
//! under the limit.
//!
//! ## Global keyboard shortcuts
//!
//! Owned here because they all interact with the panel stack:
//!   * **Spacebar** — toggle Sim.running (pause/resume)
//!   * **Escape** — close most-recently-opened panel; if none open,
//!     open the pause menu. If pause is open, resume.
//!   * **P** — open pause menu directly (matches the top-bar "Menu"
//!     button — even with other panels open, P jumps straight to pause
//!     without unwinding the stack)
//!   * **H** / `?` — toggle help popup
//!
//! Skips when egui owns the keyboard (a filter text box is focused),
//! so typing in a panel's filter doesn't pause the sim or pop a
//! help window.
//!
//! Extracted from `ui/mod.rs` in the Phase-21 god-module split.

use bevy::prelude::*;
use bevy_egui::EguiContexts;

use super::construction::ConstructionState;
use super::contracts::ContractsState;
use super::events::EventsState;
use super::facility::FacilityListState;
use super::factions::FactionsState;
use super::help::HelpState;
use super::markets::MarketsState;
use super::menus::{OptionsState, PauseMenuState};
use super::populations::PopulationsState;
use super::retirements::RetirementsState;
use super::ship_list::ShipListState;
use super::spawn_dialogs::{AddFacilityDialogState, AddShipDialogState};
use super::PerfStats;
use crate::sim::Sim;

/// Enumeration of every panel that participates in the Esc-closes-
/// top-panel stack. Each variant maps to a single `*State.open`
/// (or equivalent) flag — see [`reconcile_panel_stack`] for the
/// read side and [`close_top_panel`] for the write side.
#[derive(Clone, Copy, Eq, PartialEq, Debug)]
pub enum PanelKind {
    Perf,
    ShipList,
    Contracts,
    Factions,
    Markets,
    Populations,
    FacilityList,
    Retirements,
    Construction,
    Events,
    Help,
    Options,
    AddShip,
    AddFacility,
}

/// LIFO stack of currently-open panels. Reconciled each frame from
/// individual `*State.open` flags so toggling a panel from any
/// path (top-bar button, hotkey, programmatic) keeps the stack
/// honest. Esc pops the back; the popped kind lands in
/// [`CloseTopRequest`] for [`close_top_panel`] to action.
#[derive(Resource, Default)]
pub struct OpenPanelStack {
    pub stack: Vec<PanelKind>,
}

/// One-shot request set by the Esc handler; consumed by
/// [`close_top_panel`]. Lives in its own resource so the system
/// that handles input doesn't need ResMut on every panel state
/// (Bevy's tuple-of-params limit).
#[derive(Resource, Default)]
pub struct CloseTopRequest(pub Option<PanelKind>);

#[allow(clippy::too_many_arguments)]
pub(super) fn reconcile_panel_stack(
    mut stack: ResMut<OpenPanelStack>,
    perf: Res<PerfStats>,
    ship_list: Res<ShipListState>,
    contracts: Res<ContractsState>,
    factions: Res<FactionsState>,
    markets: Res<MarketsState>,
    populations: Res<PopulationsState>,
    facility_list: Res<FacilityListState>,
    retirements: Res<RetirementsState>,
    construction: Res<ConstructionState>,
    events: Res<EventsState>,
    help: Res<HelpState>,
    options: Res<OptionsState>,
    add_ship: Res<AddShipDialogState>,
    add_facility: Res<AddFacilityDialogState>,
) {
    let table = [
        (PanelKind::Perf, perf.open),
        (PanelKind::ShipList, ship_list.open),
        (PanelKind::Contracts, contracts.open),
        (PanelKind::Factions, factions.open),
        (PanelKind::Markets, markets.open),
        (PanelKind::Populations, populations.open),
        (PanelKind::FacilityList, facility_list.open),
        (PanelKind::Retirements, retirements.open),
        (PanelKind::Construction, construction.open),
        (PanelKind::Events, events.open),
        (PanelKind::Help, help.open),
        (PanelKind::Options, options.open),
        (PanelKind::AddShip, add_ship.open),
        (PanelKind::AddFacility, add_facility.open),
    ];
    for (kind, is_open) in table {
        let in_stack = stack.stack.contains(&kind);
        if is_open && !in_stack {
            stack.stack.push(kind);
        } else if !is_open && in_stack {
            stack.stack.retain(|k| *k != kind);
        }
    }
}

#[allow(clippy::too_many_arguments)]
pub(super) fn keyboard_shortcuts(
    keys: Res<ButtonInput<KeyCode>>,
    mut sim: ResMut<Sim>,
    mut menu: ResMut<PauseMenuState>,
    mut help: ResMut<HelpState>,
    mut egui_ctx: EguiContexts,
    stack: Res<OpenPanelStack>,
    mut close_req: ResMut<CloseTopRequest>,
) {
    // When egui is capturing keyboard input (an editable text
    // widget has focus), don't fire shortcuts — typing "pause" in a
    // filter box would otherwise trigger pause on the 'p' the user
    // just wanted to search for.
    if egui_ctx.ctx_mut().wants_keyboard_input() {
        return;
    }
    // Suppress Spacebar pause-toggle while the pause menu is open —
    // otherwise Space would flip sim.running independently of the
    // menu's internal `was_running` bookkeeping, leaving the user
    // staring at a "Paused" overlay over a running sim.
    if keys.just_pressed(KeyCode::Space) && !menu.open {
        sim.running = !sim.running;
    }
    // `?` (Slash, with or without Shift) or `H` toggles the help
    // popup. egui consumes Shift natively when ShiftLeft is held;
    // we just react to either key landing.
    if keys.just_pressed(KeyCode::Slash) || keys.just_pressed(KeyCode::KeyH) {
        help.open = !help.open;
    }
    // P opens the pause menu unconditionally — even with panels
    // open. Lets the user jump straight to Save / Quit / Options
    // without first dismissing N stacked panels.
    if keys.just_pressed(KeyCode::KeyP) && !menu.open {
        menu.open = true;
        menu.was_running = sim.running;
        sim.running = false;
    }
    if keys.just_pressed(KeyCode::Escape) {
        if menu.open {
            // Pause menu is its own thing — Esc resumes.
            menu.open = false;
            sim.running = menu.was_running;
        } else if let Some(top) = stack.stack.last().copied() {
            // Defer the actual close to `close_top_panel`, which
            // owns the panel-state ResMuts we'd otherwise need
            // here. Setting the request and returning keeps Esc
            // single-step (one panel per press).
            close_req.0 = Some(top);
        } else {
            // No panels left — Esc opens the pause menu.
            menu.open = true;
            menu.was_running = sim.running;
            sim.running = false;
        }
    }
}

/// Drains [`CloseTopRequest`] by flipping the corresponding panel's
/// open flag. Split from [`keyboard_shortcuts`] so each system
/// stays under Bevy's SystemParam-tuple limit — input handling
/// over there, panel mutation here.
#[allow(clippy::too_many_arguments)]
pub(super) fn close_top_panel(
    mut close_req: ResMut<CloseTopRequest>,
    mut perf: ResMut<PerfStats>,
    mut ship_list: ResMut<ShipListState>,
    mut contracts: ResMut<ContractsState>,
    mut factions: ResMut<FactionsState>,
    mut markets: ResMut<MarketsState>,
    mut populations: ResMut<PopulationsState>,
    mut facility_list: ResMut<FacilityListState>,
    mut retirements: ResMut<RetirementsState>,
    mut construction: ResMut<ConstructionState>,
    mut events: ResMut<EventsState>,
    mut help: ResMut<HelpState>,
    mut options: ResMut<OptionsState>,
    mut add_ship: ResMut<AddShipDialogState>,
    mut add_facility: ResMut<AddFacilityDialogState>,
) {
    let Some(kind) = close_req.0.take() else {
        return;
    };
    match kind {
        PanelKind::Perf => perf.open = false,
        PanelKind::ShipList => ship_list.open = false,
        PanelKind::Contracts => contracts.open = false,
        PanelKind::Factions => factions.open = false,
        PanelKind::Markets => markets.open = false,
        PanelKind::Populations => populations.open = false,
        PanelKind::FacilityList => facility_list.open = false,
        PanelKind::Retirements => retirements.open = false,
        PanelKind::Construction => construction.open = false,
        PanelKind::Events => events.open = false,
        PanelKind::Help => help.open = false,
        PanelKind::Options => options.open = false,
        PanelKind::AddShip => add_ship.open = false,
        PanelKind::AddFacility => add_facility.open = false,
    }
}
