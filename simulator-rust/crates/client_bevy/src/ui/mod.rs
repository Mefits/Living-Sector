//! egui-based inspector panels. First panel: perf overlay.
//!
//! Pattern for every panel: a Bevy system that opens an `egui::Window`
//! and reads the `Sim` Resource directly. Zero marshalling, zero
//! snapshot layer — the inspector IS a live debugger with full
//! access to every hecs component. This is the key payoff of the
//! embedded architecture vs. the Godot client's WS-and-JSON path.

use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts, EguiPlugin};
use std::time::{Duration, Instant};

use crate::camera::{CameraFocusRequest, OrbitCamera};
use crate::render::SCALE_FACTOR;
use crate::sim::{Retirements, Sim};

pub struct UiPlugin;

impl Plugin for UiPlugin {
    fn build(&self, app: &mut App) {
        app.add_plugins(EguiPlugin)
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
            .add_systems(
                Update,
                (
                    track_fps,
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
                )
                    .chain(),
            )
            // Second chain keeps each system's parameter list small
            // enough that Bevy's tuple-of-params limit isn't an issue,
            // and also separates the "details" family so ship_details
            // + facility_details don't compete for EguiContexts within
            // the same chain.
            .add_systems(
                Update,
                (
                    facility_list_panel,
                    facility_details_panel,
                    retirements_panel,
                    construction_panel,
                )
                    .chain(),
            );
    }
}

/// Single top-bar system. Reads counts from the sim, hands out
/// open/close toggles to each panel's state Resource. Runs first
/// in the UI chain so the panels below see up-to-date `open`
/// flags the same frame the user clicks.
#[allow(clippy::too_many_arguments)]
fn top_bar(
    mut ctx: EguiContexts,
    mut sim: ResMut<Sim>,
    retirements: Res<Retirements>,
    mut ships: ResMut<ShipListState>,
    mut contracts: ResMut<ContractsState>,
    mut factions: ResMut<FactionsState>,
    mut markets: ResMut<MarketsState>,
    mut pops: ResMut<PopulationsState>,
    mut facilities: ResMut<FacilityListState>,
    mut retired_state: ResMut<RetirementsState>,
    mut construction: ResMut<ConstructionState>,
    mut minimap: ResMut<MinimapState>,
    mut body_labels: ResMut<BodyLabelsState>,
) {
    // Count construction sites via an ECS query — the sim store
    // doesn't index them by id (sites aren't frequently looked up
    // by id). At typical counts (<20) the iteration is trivial.
    use sim_core::agents::construction::ConstructionSite;
    let construction_count = sim.store.world.query::<&ConstructionSite>().iter().count();
    egui::TopBottomPanel::top("top_bar").show(ctx.ctx_mut(), |ui| {
        ui.horizontal(|ui| {
            ui.label(egui::RichText::new("spaceproject").strong());
            ui.separator();
            // Pause toggle — empty string = play, dot = paused. Matches
            // ▶/⏸ iconography without pulling a font in.
            let running = sim.running;
            let label = if running { "⏸ Pause" } else { "▶ Play" };
            if ui.button(label).clicked() {
                sim.running = !running;
            }
            // Speed combo. Stays in effect across pause/resume —
            // pausing just freezes the tick loop.
            let mut speed = sim.tick_mult.max(1);
            egui::ComboBox::from_id_salt("sim_speed_combo")
                .selected_text(format!("{}×", speed))
                .show_ui(ui, |ui| {
                    for &s in &[1u32, 2, 4, 8] {
                        if ui.selectable_value(&mut speed, s, format!("{}×", s)).clicked() {
                            sim.tick_mult = s;
                        }
                    }
                });
            ui.separator();
            ui.label(
                egui::RichText::new(format!("tick {}", sim.tick))
                    .monospace()
                    .color(egui::Color32::from_gray(180)),
            );
            ui.separator();
            if ui
                .selectable_label(
                    ships.open,
                    format!("Ships ({})", sim.store.ship_by_id.len()),
                )
                .clicked()
            {
                ships.open = !ships.open;
            }
            if ui
                .selectable_label(
                    contracts.open,
                    format!("Contracts ({})", sim.store.contracts.iter().count()),
                )
                .clicked()
            {
                contracts.open = !contracts.open;
            }
            if ui
                .selectable_label(
                    factions.open,
                    format!("Factions ({})", sim.store.faction_by_id.len()),
                )
                .clicked()
            {
                factions.open = !factions.open;
            }
            // Markets live in the ECS under MarketIdentity — counted
            // by iterating the world in the panel itself. Top-bar
            // label just says "Markets" without a count to keep the
            // shared top_bar system from having to query hecs too.
            if ui
                .selectable_label(markets.open, "Markets")
                .clicked()
            {
                markets.open = !markets.open;
            }
            if ui
                .selectable_label(
                    pops.open,
                    format!("Pops ({})", sim.store.population_by_id.len()),
                )
                .clicked()
            {
                pops.open = !pops.open;
            }
            if ui
                .selectable_label(
                    facilities.open,
                    format!("Facilities ({})", sim.store.facility_by_id.len()),
                )
                .clicked()
            {
                facilities.open = !facilities.open;
            }
            if ui
                .selectable_label(
                    retired_state.open,
                    format!("Retired ({})", retirements.0.len()),
                )
                .clicked()
            {
                retired_state.open = !retired_state.open;
            }
            if ui
                .selectable_label(
                    construction.open,
                    format!("Construction ({})", construction_count),
                )
                .clicked()
            {
                construction.open = !construction.open;
            }
            if ui
                .selectable_label(minimap.open, "Map")
                .clicked()
            {
                minimap.open = !minimap.open;
            }
            if ui
                .selectable_label(body_labels.show, "Labels")
                .clicked()
            {
                body_labels.show = !body_labels.show;
            }
        });
    });
}

/// Rolling FPS window so the overlay doesn't flicker frame-to-frame.
/// Tracks the last N frame durations and averages them.
#[derive(Resource)]
struct PerfStats {
    frame_samples: Vec<Duration>,
    last_frame_instant: Instant,
    avg_fps: f32,
}

impl Default for PerfStats {
    fn default() -> Self {
        Self {
            frame_samples: Vec::with_capacity(FPS_WINDOW),
            last_frame_instant: Instant::now(),
            avg_fps: 0.0,
        }
    }
}

const FPS_WINDOW: usize = 60;

fn track_fps(mut stats: ResMut<PerfStats>) {
    let now = Instant::now();
    let dt = now.saturating_duration_since(stats.last_frame_instant);
    stats.last_frame_instant = now;
    if stats.frame_samples.len() == FPS_WINDOW {
        stats.frame_samples.remove(0);
    }
    stats.frame_samples.push(dt);
    // Average frame time → FPS. Skip if we haven't gathered any
    // samples yet (first frame).
    if stats.frame_samples.is_empty() {
        return;
    }
    let sum: Duration = stats.frame_samples.iter().sum();
    let avg_secs = sum.as_secs_f32() / stats.frame_samples.len() as f32;
    if avg_secs > 0.0 {
        stats.avg_fps = 1.0 / avg_secs;
    }
}

fn perf_overlay(
    mut ctx: EguiContexts,
    sim: Res<Sim>,
    stats: Res<PerfStats>,
) {
    egui::Window::new("Perf")
        .anchor(egui::Align2::LEFT_TOP, egui::vec2(8.0, 8.0))
        .default_width(220.0)
        .show(ctx.ctx_mut(), |ui| {
            egui::Grid::new("perf_grid")
                .num_columns(2)
                .spacing([12.0, 4.0])
                .show(ui, |ui| {
                    ui.label("FPS");
                    let fps_color = if stats.avg_fps >= 55.0 {
                        egui::Color32::from_rgb(120, 220, 120)
                    } else if stats.avg_fps >= 30.0 {
                        egui::Color32::from_rgb(230, 200, 90)
                    } else {
                        egui::Color32::from_rgb(240, 100, 90)
                    };
                    ui.colored_label(fps_color, format!("{:.0}", stats.avg_fps));
                    ui.end_row();

                    ui.label("Tick");
                    ui.label(format!("{}", sim.tick));
                    ui.end_row();

                    ui.label("Ships");
                    ui.label(format!("{}", sim.store.ship_by_id.len()));
                    ui.end_row();

                    ui.label("Facilities");
                    ui.label(format!("{}", sim.store.facility_by_id.len()));
                    ui.end_row();

                    ui.label("Bodies");
                    ui.label(format!("{}", sim.store.body_by_id.len()));
                    ui.end_row();

                    ui.label("Populations");
                    ui.label(format!("{}", sim.store.population_by_id.len()));
                    ui.end_row();

                    ui.label("Factions");
                    ui.label(format!("{}", sim.store.faction_by_id.len()));
                    ui.end_row();

                    ui.label("Contracts");
                    ui.label(format!("{}", sim.store.contracts.iter().count()));
                    ui.end_row();

                    ui.label("World seed");
                    ui.label(format!("{}", sim.world_seed));
                    ui.end_row();
                });
            ui.separator();
            ui.label(
                egui::RichText::new("embedded sim — no network")
                    .small()
                    .italics()
                    .color(egui::Color32::from_gray(140)),
            );
        });
}

// =============================================================================
// Ship list panel
// =============================================================================

/// Persistent UI state for the ship list (sort key, search filter,
/// whether the window is open). Anything that needs to survive
/// between frames lives on this Resource.
#[derive(Resource, Default)]
struct ShipListState {
    open: bool,
    sort: ShipSort,
    descending: bool,
    filter: String,
}

#[derive(Default, PartialEq, Eq, Clone, Copy)]
enum ShipSort {
    #[default]
    Name,
    Class,
    Faction,
    Location,
}

/// One egui row worth of ship data, extracted from the hecs world
/// once per frame. Keeps the render loop's query work bounded — we
/// iterate hecs once, build a Vec, sort, then render.
struct ShipRow {
    id: String,
    name: String,
    class: String,
    faction: String,
    location: String,
}

/// Currently-selected ship, written by a click in the ship list and
/// read by the details panel. `None` means no selection (details
/// window closes itself). Public so the render layer can use it to
/// highlight the matching Bevy entity.
#[derive(Resource, Default)]
pub struct SelectedShip(pub Option<String>);

fn ship_list(
    mut ctx: EguiContexts,
    sim: Res<Sim>,
    mut state: ResMut<ShipListState>,
    mut selected: ResMut<SelectedShip>,
) {
    use sim_core::agents::ship::{ShipIdentity, ShipPosition};

    // Snapshot the mutable fields we'll need inside egui closures so
    // the borrow checker doesn't choke on overlapping mut refs into
    // the ResMut. We write back at the end of the function.
    let mut open = state.open;
    let mut filter = state.filter.clone();
    let mut sort = state.sort;
    let mut descending = state.descending;

    if !open {
        return;
    }

    let rows: Vec<ShipRow> = sim
        .store
        .world
        .query::<(&ShipIdentity, &ShipPosition)>()
        .iter()
        .map(|(_e, (id, pos))| ShipRow {
            id: id.id.clone(),
            name: id.name.clone(),
            class: id.class.clone(),
            faction: id.faction_id.clone(),
            location: pos
                .location_name
                .clone()
                .unwrap_or_else(|| "(in transit)".into()),
        })
        .collect();

    let filter_lc = filter.to_lowercase();
    let mut filtered: Vec<&ShipRow> = rows
        .iter()
        .filter(|r| {
            if filter_lc.is_empty() {
                return true;
            }
            r.name.to_lowercase().contains(&filter_lc)
                || r.id.to_lowercase().contains(&filter_lc)
                || r.class.to_lowercase().contains(&filter_lc)
                || r.faction.to_lowercase().contains(&filter_lc)
                || r.location.to_lowercase().contains(&filter_lc)
        })
        .collect();

    filtered.sort_by(|a, b| {
        let cmp = match sort {
            ShipSort::Name => a.name.cmp(&b.name),
            ShipSort::Class => a.class.cmp(&b.class),
            ShipSort::Faction => a.faction.cmp(&b.faction),
            ShipSort::Location => a.location.cmp(&b.location),
        };
        if descending {
            cmp.reverse()
        } else {
            cmp
        }
    });

    let shown = filtered.len();
    let total = rows.len();
    // Use ScrollArea + rows cap so 1600-entry worlds stay responsive.
    // egui handles its own virtualisation via `show_rows`; we cap to
    // PAGE_SIZE upfront so sort work doesn't blow up on pathological
    // filters. 500 is plenty for typical play.
    const PAGE_SIZE: usize = 500;
    let page: Vec<&ShipRow> = filtered.into_iter().take(PAGE_SIZE).collect();

    egui::Window::new(format!("Ships · {shown}/{total}"))
        .default_width(640.0)
        .default_height(400.0)
        .open(&mut open)
        .show(ctx.ctx_mut(), |ui| {
            ui.horizontal(|ui| {
                ui.label("filter:");
                ui.text_edit_singleline(&mut filter);
                if shown > PAGE_SIZE {
                    ui.label(
                        egui::RichText::new(format!("(top {} shown)", PAGE_SIZE))
                            .small()
                            .color(egui::Color32::from_gray(160)),
                    );
                }
            });
            ui.separator();

            egui::ScrollArea::vertical().show(ui, |ui| {
                egui::Grid::new("ship_list_grid")
                    .striped(true)
                    .num_columns(4)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        sort_header(ui, "Name", &mut sort, &mut descending, ShipSort::Name);
                        sort_header(ui, "Class", &mut sort, &mut descending, ShipSort::Class);
                        sort_header(ui, "Faction", &mut sort, &mut descending, ShipSort::Faction);
                        sort_header(ui, "Location", &mut sort, &mut descending, ShipSort::Location);
                        ui.end_row();

                        for row in &page {
                            // Name cell doubles as the row selector —
                            // clicking highlights and opens the details
                            // panel on this ship. Click-through the
                            // whole row would be nicer but egui's grid
                            // doesn't give us per-row click regions
                            // without some contortion, and the name
                            // column is the most natural thing to
                            // click anyway.
                            let is_sel = selected.0.as_deref() == Some(row.id.as_str());
                            if ui.selectable_label(is_sel, &row.name).clicked() {
                                selected.0 = Some(row.id.clone());
                            }
                            ui.label(&row.class);
                            ui.label(&row.faction);
                            ui.label(&row.location);
                            ui.end_row();
                        }
                    });
            });
        });

    // Write the local snapshot back to the Resource for next frame.
    state.open = open;
    state.filter = filter;
    state.sort = sort;
    state.descending = descending;
}

fn sort_header(
    ui: &mut egui::Ui,
    label: &str,
    current: &mut ShipSort,
    descending: &mut bool,
    target: ShipSort,
) {
    let arrow = if *current == target {
        if *descending {
            " ▼"
        } else {
            " ▲"
        }
    } else {
        ""
    };
    let text = egui::RichText::new(format!("{label}{arrow}")).strong();
    if ui.button(text).clicked() {
        if *current == target {
            *descending = !*descending;
        } else {
            *current = target;
            *descending = false;
        }
    }
}

// =============================================================================
// Contracts panel
// =============================================================================

#[derive(Resource, Default)]
struct ContractsState {
    open: bool,
    kind_filter: ContractKindFilter,
    status_filter: ContractStatusFilter,
    show_expired: bool,
}

#[derive(Default, PartialEq, Eq, Clone, Copy)]
enum ContractKindFilter {
    #[default]
    All,
    Delivery,
    Courier,
    Passenger,
    Subsidy,
    Supply,
    CrewMission,
    Construction,
}

#[derive(Default, PartialEq, Eq, Clone, Copy)]
enum ContractStatusFilter {
    #[default]
    All,
    Posted,
    Accepted,
    PickedUp,
    Delivered,
    Paid,
    Expired,
}

fn contracts_panel(
    mut ctx: EguiContexts,
    sim: Res<Sim>,
    mut state: ResMut<ContractsState>,
) {
    use sim_core::economy::contracts::{ContractStatus, ContractType};

    let mut open = state.open;
    let mut kind_filter = state.kind_filter;
    let mut status_filter = state.status_filter;
    let mut show_expired = state.show_expired;

    if !open {
        return;
    }

    // Build the view slice. We walk the board once and filter upfront
    // so the render loop doesn't re-check predicates per row. At 500+
    // contracts the full walk is trivial.
    struct Row {
        id: String,
        kind: &'static str,
        status: &'static str,
        commodity: String,
        quantity: u32,
        source: String,
        dest: String,
        payment: i64,
        faction: String,
        min_rep: u8,
    }
    let rows: Vec<Row> = sim
        .store
        .contracts
        .iter()
        .filter(|c| match kind_filter {
            ContractKindFilter::All => true,
            ContractKindFilter::Delivery => matches!(c.contract_type, ContractType::Delivery),
            ContractKindFilter::Courier => matches!(c.contract_type, ContractType::Courier),
            ContractKindFilter::Passenger => matches!(c.contract_type, ContractType::Passenger),
            ContractKindFilter::Subsidy => matches!(c.contract_type, ContractType::Subsidy),
            ContractKindFilter::Supply => matches!(c.contract_type, ContractType::Supply),
            ContractKindFilter::CrewMission => {
                matches!(c.contract_type, ContractType::CrewMission)
            }
            ContractKindFilter::Construction => {
                matches!(c.contract_type, ContractType::Construction)
            }
        })
        .filter(|c| match status_filter {
            ContractStatusFilter::All => true,
            ContractStatusFilter::Posted => matches!(c.status, ContractStatus::Posted),
            ContractStatusFilter::Accepted => matches!(c.status, ContractStatus::Accepted),
            ContractStatusFilter::PickedUp => matches!(c.status, ContractStatus::PickedUp),
            ContractStatusFilter::Delivered => matches!(c.status, ContractStatus::Delivered),
            ContractStatusFilter::Paid => matches!(c.status, ContractStatus::Paid),
            ContractStatusFilter::Expired => matches!(c.status, ContractStatus::Expired),
        })
        .filter(|c| show_expired || !matches!(c.status, ContractStatus::Expired))
        .map(|c| Row {
            id: c.id.clone(),
            kind: c.contract_type.as_str(),
            status: status_str(&c.status),
            commodity: c.commodity.as_str().to_string(),
            quantity: c.quantity,
            source: c.source_location.clone(),
            dest: c.destination_location.clone(),
            payment: c.payment,
            faction: c.faction_id.clone().unwrap_or_default(),
            min_rep: c.min_reputation,
        })
        .collect();

    let total = sim.store.contracts.iter().count();
    let shown = rows.len();

    egui::Window::new(format!("Contracts · {shown}/{total}"))
        .default_width(820.0)
        .default_height(440.0)
        .open(&mut open)
        .show(ctx.ctx_mut(), |ui| {
            ui.horizontal(|ui| {
                ui.label("kind:");
                kind_combo(ui, &mut kind_filter);
                ui.separator();
                ui.label("status:");
                status_combo(ui, &mut status_filter);
                ui.separator();
                ui.checkbox(&mut show_expired, "show expired");
            });
            ui.separator();

            const PAGE_SIZE: usize = 400;
            let page_rows: Vec<&Row> = rows.iter().take(PAGE_SIZE).collect();

            egui::ScrollArea::vertical().show(ui, |ui| {
                egui::Grid::new("contracts_grid")
                    .striped(true)
                    .num_columns(9)
                    .spacing([10.0, 2.0])
                    .show(ui, |ui| {
                        for header in [
                            "Kind", "Status", "Item", "Qty", "Source → Dest", "Pay", "Faction", "Rep", "ID",
                        ] {
                            ui.label(egui::RichText::new(header).strong());
                        }
                        ui.end_row();

                        for r in &page_rows {
                            ui.label(r.kind);
                            let status_color = status_color(r.status);
                            ui.colored_label(status_color, r.status);
                            ui.label(&r.commodity);
                            ui.label(format!("{}", r.quantity));
                            ui.label(format!("{} → {}", r.source, r.dest));
                            ui.label(format!("{}", r.payment));
                            ui.label(&r.faction);
                            if r.min_rep > 0 {
                                ui.label(format!("{}", r.min_rep));
                            } else {
                                ui.label("–");
                            }
                            ui.label(
                                egui::RichText::new(&r.id)
                                    .small()
                                    .color(egui::Color32::from_gray(140)),
                            );
                            ui.end_row();
                        }
                    });
            });
            if shown > PAGE_SIZE {
                ui.separator();
                ui.label(
                    egui::RichText::new(format!(
                        "{} more contracts past page cap",
                        shown - PAGE_SIZE
                    ))
                    .small()
                    .color(egui::Color32::from_gray(160)),
                );
            }
        });

    state.open = open;
    state.kind_filter = kind_filter;
    state.status_filter = status_filter;
    state.show_expired = show_expired;
}

fn status_str(s: &sim_core::economy::contracts::ContractStatus) -> &'static str {
    use sim_core::economy::contracts::ContractStatus as S;
    match s {
        S::Posted => "posted",
        S::Accepted => "accepted",
        S::PickedUp => "picked_up",
        S::Delivered => "delivered",
        S::Paid => "paid",
        S::Expired => "expired",
    }
}

fn status_color(s: &'static str) -> egui::Color32 {
    match s {
        "posted" => egui::Color32::from_rgb(120, 180, 230),
        "accepted" | "picked_up" => egui::Color32::from_rgb(230, 200, 90),
        "delivered" | "paid" => egui::Color32::from_rgb(120, 220, 120),
        "expired" => egui::Color32::from_rgb(200, 110, 110),
        _ => egui::Color32::WHITE,
    }
}

fn kind_combo(ui: &mut egui::Ui, current: &mut ContractKindFilter) {
    egui::ComboBox::from_id_salt("kind_filter_combo")
        .selected_text(match current {
            ContractKindFilter::All => "all",
            ContractKindFilter::Delivery => "delivery",
            ContractKindFilter::Courier => "courier",
            ContractKindFilter::Passenger => "passenger",
            ContractKindFilter::Subsidy => "subsidy",
            ContractKindFilter::Supply => "supply",
            ContractKindFilter::CrewMission => "crew_mission",
            ContractKindFilter::Construction => "construction",
        })
        .show_ui(ui, |ui| {
            for (label, value) in [
                ("all", ContractKindFilter::All),
                ("delivery", ContractKindFilter::Delivery),
                ("courier", ContractKindFilter::Courier),
                ("passenger", ContractKindFilter::Passenger),
                ("subsidy", ContractKindFilter::Subsidy),
                ("supply", ContractKindFilter::Supply),
                ("crew_mission", ContractKindFilter::CrewMission),
                ("construction", ContractKindFilter::Construction),
            ] {
                ui.selectable_value(current, value, label);
            }
        });
}

fn status_combo(ui: &mut egui::Ui, current: &mut ContractStatusFilter) {
    egui::ComboBox::from_id_salt("status_filter_combo")
        .selected_text(match current {
            ContractStatusFilter::All => "all",
            ContractStatusFilter::Posted => "posted",
            ContractStatusFilter::Accepted => "accepted",
            ContractStatusFilter::PickedUp => "picked_up",
            ContractStatusFilter::Delivered => "delivered",
            ContractStatusFilter::Paid => "paid",
            ContractStatusFilter::Expired => "expired",
        })
        .show_ui(ui, |ui| {
            for (label, value) in [
                ("all", ContractStatusFilter::All),
                ("posted", ContractStatusFilter::Posted),
                ("accepted", ContractStatusFilter::Accepted),
                ("picked_up", ContractStatusFilter::PickedUp),
                ("delivered", ContractStatusFilter::Delivered),
                ("paid", ContractStatusFilter::Paid),
                ("expired", ContractStatusFilter::Expired),
            ] {
                ui.selectable_value(current, value, label);
            }
        });
}

// =============================================================================
// Factions panel
// =============================================================================
//
// Godot-parity faction ledger. Two sections in one window:
//   1. Per-faction ledger: treasury + ship count + facility count +
//      active subsidies + home system. Sortable by clicking headers.
//   2. Pairwise relations matrix: each (a,b) shows standing + treaty.
//      Matrix is small (≤8 factions → 28 pairs) so plain grid is fine.
//
// Reads `FactionData` components straight out of hecs, counts ships +
// facilities by iterating their identity components once per frame
// (tiny work at this scale).

#[derive(Resource, Default)]
struct FactionsState {
    open: bool,
    sort: FactionSort,
    descending: bool,
}

#[derive(Default, PartialEq, Eq, Clone, Copy)]
enum FactionSort {
    #[default]
    Name,
    Treasury,
    Ships,
    Facilities,
    Subsidies,
}

struct FactionRow {
    name: String,
    home_system: String,
    faction_type: String,
    treasury: i64,
    ships: u32,
    facilities: u32,
    subsidies: u32,
}

fn factions_panel(
    mut ctx: EguiContexts,
    sim: Res<Sim>,
    mut state: ResMut<FactionsState>,
) {
    use sim_core::agents::{
        facility::FacilityIdentity,
        faction::FactionData,
        faction_relations::TreatyKind,
        ship::ShipIdentity,
    };
    use std::collections::HashMap;

    let mut open = state.open;
    let mut sort = state.sort;
    let mut descending = state.descending;

    if !open {
        return;
    }

    // Ship + facility counts per faction id, built once.
    let mut ship_counts: HashMap<String, u32> = HashMap::new();
    for (_e, id) in sim.store.world.query::<&ShipIdentity>().iter() {
        *ship_counts.entry(id.faction_id.clone()).or_insert(0) += 1;
    }
    let mut fac_counts: HashMap<String, u32> = HashMap::new();
    for (_e, id) in sim.store.world.query::<&FacilityIdentity>().iter() {
        *fac_counts.entry(id.faction_id.clone()).or_insert(0) += 1;
    }

    let mut rows: Vec<FactionRow> = sim
        .store
        .world
        .query::<&FactionData>()
        .iter()
        .map(|(_e, f)| FactionRow {
            name: f.name.clone(),
            home_system: f.home_system.clone(),
            faction_type: f.faction_type.clone(),
            treasury: f.treasury,
            ships: ship_counts.get(&f.id).copied().unwrap_or(0),
            facilities: fac_counts.get(&f.id).copied().unwrap_or(0),
            subsidies: f.active_subsidies,
        })
        .collect();

    rows.sort_by(|a, b| {
        let cmp = match sort {
            FactionSort::Name => a.name.cmp(&b.name),
            FactionSort::Treasury => a.treasury.cmp(&b.treasury),
            FactionSort::Ships => a.ships.cmp(&b.ships),
            FactionSort::Facilities => a.facilities.cmp(&b.facilities),
            FactionSort::Subsidies => a.subsidies.cmp(&b.subsidies),
        };
        if descending { cmp.reverse() } else { cmp }
    });

    egui::Window::new(format!("Factions · {}", rows.len()))
        .default_width(720.0)
        .default_height(520.0)
        .open(&mut open)
        .show(ctx.ctx_mut(), |ui| {
            ui.label(egui::RichText::new("Ledger").strong());
            egui::Grid::new("factions_ledger_grid")
                .striped(true)
                .num_columns(6)
                .spacing([12.0, 3.0])
                .show(ui, |ui| {
                    faction_sort_header(ui, "Faction", &mut sort, &mut descending, FactionSort::Name);
                    ui.label(egui::RichText::new("System").strong());
                    faction_sort_header(ui, "Treasury", &mut sort, &mut descending, FactionSort::Treasury);
                    faction_sort_header(ui, "Ships", &mut sort, &mut descending, FactionSort::Ships);
                    faction_sort_header(ui, "Fac", &mut sort, &mut descending, FactionSort::Facilities);
                    faction_sort_header(ui, "Subs", &mut sort, &mut descending, FactionSort::Subsidies);
                    ui.end_row();

                    for r in &rows {
                        ui.label(format!("{} ({})", r.name, r.faction_type));
                        ui.label(&r.home_system);
                        let t_color = if r.treasury >= 10_000 {
                            egui::Color32::from_rgb(120, 220, 120)
                        } else if r.treasury >= 2_000 {
                            egui::Color32::from_rgb(230, 200, 90)
                        } else {
                            egui::Color32::from_rgb(240, 100, 90)
                        };
                        ui.colored_label(t_color, format_credits(r.treasury));
                        ui.label(format!("{}", r.ships));
                        ui.label(format!("{}", r.facilities));
                        ui.label(format!("{}", r.subsidies));
                        ui.end_row();
                    }
                });

            ui.separator();
            ui.label(egui::RichText::new("Relations").strong());
            ui.label(
                egui::RichText::new("canonical pairs — standing ∈ [-100, 100]")
                    .small()
                    .color(egui::Color32::from_gray(150)),
            );

            egui::ScrollArea::vertical()
                .id_salt("relations_scroll")
                .max_height(240.0)
                .show(ui, |ui| {
                    egui::Grid::new("relations_grid")
                        .striped(true)
                        .num_columns(4)
                        .spacing([10.0, 2.0])
                        .show(ui, |ui| {
                            for header in ["A", "B", "Standing", "Treaty"] {
                                ui.label(egui::RichText::new(header).strong());
                            }
                            ui.end_row();

                            let mut pairs: Vec<_> = sim.store.relations.iter().collect();
                            pairs.sort_by(|(ka, _), (kb, _)| ka.cmp(kb));

                            for ((a, b), state) in pairs {
                                ui.label(a);
                                ui.label(b);
                                let s_color = if state.standing >= 25 {
                                    egui::Color32::from_rgb(120, 220, 120)
                                } else if state.standing <= -25 {
                                    egui::Color32::from_rgb(240, 100, 90)
                                } else {
                                    egui::Color32::from_gray(200)
                                };
                                ui.colored_label(s_color, format!("{:+}", state.standing));
                                let t_color = match state.treaty {
                                    TreatyKind::Allied => egui::Color32::from_rgb(100, 200, 255),
                                    TreatyKind::TradePact => egui::Color32::from_rgb(120, 220, 120),
                                    TreatyKind::Neutral => egui::Color32::from_gray(200),
                                    TreatyKind::Tense => egui::Color32::from_rgb(230, 200, 90),
                                    TreatyKind::Hostile => egui::Color32::from_rgb(240, 140, 90),
                                    TreatyKind::War => egui::Color32::from_rgb(240, 80, 80),
                                };
                                ui.colored_label(t_color, state.treaty.as_str());
                                ui.end_row();
                            }
                        });
                });
        });

    state.open = open;
    state.sort = sort;
    state.descending = descending;
}

fn faction_sort_header(
    ui: &mut egui::Ui,
    label: &str,
    current: &mut FactionSort,
    descending: &mut bool,
    target: FactionSort,
) {
    let arrow = if *current == target {
        if *descending { " ▼" } else { " ▲" }
    } else {
        ""
    };
    let text = egui::RichText::new(format!("{label}{arrow}")).strong();
    if ui.button(text).clicked() {
        if *current == target {
            *descending = !*descending;
        } else {
            *current = target;
            // Treasury / ships / facilities / subsidies default to
            // descending so "biggest first" feels natural; name
            // defaults to ascending (A→Z).
            *descending = !matches!(target, FactionSort::Name);
        }
    }
}

fn format_credits(n: i64) -> String {
    // Quick humanise so the ledger column isn't a wall of digits. Keeps
    // precision under 10k since that's where the interesting drift is.
    if n.abs() >= 1_000_000 {
        format!("{:.2}M", n as f64 / 1_000_000.0)
    } else if n.abs() >= 10_000 {
        format!("{:.1}k", n as f64 / 1_000.0)
    } else {
        format!("{}", n)
    }
}

// =============================================================================
// Markets panel
// =============================================================================
//
// One collapsing header per market location. Expanded view shows every
// commodity's price / supply / demand / shortage-tick counter. Top-level
// row badges the market as `crisis` (MARKET_CRISIS_SHORTAGE_TICKS hit
// on any commodity) or `short` (any commodity with shortage_ticks > 0).
// Filter narrows by location substring, and a toggle collapses normal
// markets so the eye goes straight to the problem spots.

#[derive(Resource, Default)]
struct MarketsState {
    open: bool,
    filter: String,
    only_shortages: bool,
}

fn markets_panel(
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
        let (Some(pricing), Some(history)) = (pricing, history) else { continue };

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
            if r.crisis { 0 } else if r.any_short { 1 } else { 2 }
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
                    let badge = if row.crisis {
                        egui::RichText::new(" CRISIS ")
                            .background_color(egui::Color32::from_rgb(180, 60, 60))
                            .color(egui::Color32::WHITE)
                            .strong()
                    } else if row.any_short {
                        egui::RichText::new(" SHORT ")
                            .background_color(egui::Color32::from_rgb(180, 140, 40))
                            .color(egui::Color32::BLACK)
                            .strong()
                    } else {
                        egui::RichText::new("")
                    };

                    egui::CollapsingHeader::new(
                        egui::RichText::new(&row.location).strong(),
                    )
                    .id_salt(format!("market_hdr_{}", row.location))
                    .show(ui, |ui| {
                        if !row.shortage_ticks.is_empty() {
                            ui.label(
                                egui::RichText::new("Active shortages:")
                                    .color(egui::Color32::from_rgb(230, 170, 90)),
                            );
                            egui::Grid::new(format!("shortage_grid_{}", row.location))
                                .num_columns(2)
                                .spacing([10.0, 2.0])
                                .show(ui, |ui| {
                                    for (c, t) in &row.shortage_ticks {
                                        ui.label(c.as_str());
                                        let color = if *t >= MARKET_CRISIS_SHORTAGE_TICKS {
                                            egui::Color32::from_rgb(240, 100, 90)
                                        } else {
                                            egui::Color32::from_rgb(230, 200, 90)
                                        };
                                        ui.colored_label(color, format!("{} ticks", t));
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
                                    ui.label(egui::RichText::new(header).strong());
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
                                    // Colour price relative to its own base:
                                    // > 1.25× red (scarcity), <0.75× green
                                    // (glut). Reading at a glance matters
                                    // more than exactness.
                                    let base = c.base_price();
                                    let price_color = if base > 0.0 {
                                        let r = price / base;
                                        if r >= 1.25 {
                                            egui::Color32::from_rgb(240, 120, 90)
                                        } else if r <= 0.75 {
                                            egui::Color32::from_rgb(120, 220, 150)
                                        } else {
                                            egui::Color32::from_gray(220)
                                        }
                                    } else {
                                        egui::Color32::from_gray(220)
                                    };
                                    ui.colored_label(price_color, format!("{:.1}", price));
                                    ui.label(format!("{:.0}", sup));
                                    ui.label(format!("{:.0}", dem));
                                    ui.end_row();
                                }
                            });
                    });

                    if row.crisis || row.any_short {
                        ui.horizontal(|ui| {
                            ui.add_space(20.0);
                            ui.label(badge);
                        });
                    }
                }
            });
        });

    state.open = open;
    state.filter = filter;
    state.only_shortages = only_shortages;
}

// =============================================================================
// Populations panel
// =============================================================================
//
// One row per population (~27 today). Columns cover the levers: count,
// sentiment, food satisfaction, total wealth, migration pressure. Sort
// by any numeric column; filter by label/location/faction. Sentiment
// and food cells colour-code against their natural ranges so stressed
// pops jump out.

#[derive(Resource, Default)]
struct PopulationsState {
    open: bool,
    sort: PopSort,
    descending: bool,
    filter: String,
}

#[derive(Default, PartialEq, Eq, Clone, Copy)]
enum PopSort {
    #[default]
    Label,
    Location,
    Count,
    Sentiment,
    Food,
    Wealth,
    Migration,
}

struct PopRow {
    label: String,
    demographic: String,
    location: String,
    faction: String,
    count: i64,
    sentiment: i32,
    food: i32,
    wealth: i64,
    // Migration pressure is f32; keep as f32 for display, sort via bits
    // so NaN doesn't panic.
    migration: f32,
}

fn populations_panel(
    mut ctx: EguiContexts,
    sim: Res<Sim>,
    mut state: ResMut<PopulationsState>,
) {
    use sim_core::agents::population::{
        PopDemographics, PopEconomy, PopIdentity, PopSentiment,
    };

    let mut open = state.open;
    let mut sort = state.sort;
    let mut descending = state.descending;
    let mut filter = state.filter.clone();

    if !open {
        return;
    }

    let rows: Vec<PopRow> = sim
        .store
        .world
        .query::<(&PopIdentity, &PopDemographics, &PopEconomy, &PopSentiment)>()
        .iter()
        .map(|(_e, (id, demo, econ, sent))| PopRow {
            label: id.label.clone(),
            demographic: id.demographic.clone(),
            location: id.facility_location.clone(),
            faction: id.faction_id.clone(),
            count: demo.population_count,
            sentiment: sent.overall_sentiment,
            food: sent.food_satisfaction,
            wealth: econ.total_wealth,
            migration: demo.migration_pressure,
        })
        .collect();

    let filter_lc = filter.to_lowercase();
    let mut filtered: Vec<&PopRow> = rows
        .iter()
        .filter(|r| {
            if filter_lc.is_empty() {
                return true;
            }
            r.label.to_lowercase().contains(&filter_lc)
                || r.location.to_lowercase().contains(&filter_lc)
                || r.faction.to_lowercase().contains(&filter_lc)
                || r.demographic.to_lowercase().contains(&filter_lc)
        })
        .collect();

    filtered.sort_by(|a, b| {
        let cmp = match sort {
            PopSort::Label => a.label.cmp(&b.label),
            PopSort::Location => a.location.cmp(&b.location),
            PopSort::Count => a.count.cmp(&b.count),
            PopSort::Sentiment => a.sentiment.cmp(&b.sentiment),
            PopSort::Food => a.food.cmp(&b.food),
            PopSort::Wealth => a.wealth.cmp(&b.wealth),
            // Bits-based ordering for f32 — safe for non-NaN values which
            // migration_pressure is by construction (clamped >= 0.0).
            PopSort::Migration => a
                .migration
                .partial_cmp(&b.migration)
                .unwrap_or(std::cmp::Ordering::Equal),
        };
        if descending { cmp.reverse() } else { cmp }
    });

    let total = rows.len();
    let shown = filtered.len();

    egui::Window::new(format!("Populations · {shown}/{total}"))
        .default_width(820.0)
        .default_height(460.0)
        .open(&mut open)
        .show(ctx.ctx_mut(), |ui| {
            ui.horizontal(|ui| {
                ui.label("filter:");
                ui.text_edit_singleline(&mut filter);
            });
            ui.separator();

            egui::ScrollArea::vertical().show(ui, |ui| {
                egui::Grid::new("pops_grid")
                    .striped(true)
                    .num_columns(8)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        pop_sort_header(ui, "Label", &mut sort, &mut descending, PopSort::Label);
                        ui.label(egui::RichText::new("Demo").strong());
                        pop_sort_header(ui, "Location", &mut sort, &mut descending, PopSort::Location);
                        pop_sort_header(ui, "Count", &mut sort, &mut descending, PopSort::Count);
                        pop_sort_header(ui, "Sent", &mut sort, &mut descending, PopSort::Sentiment);
                        pop_sort_header(ui, "Food", &mut sort, &mut descending, PopSort::Food);
                        pop_sort_header(ui, "Wealth", &mut sort, &mut descending, PopSort::Wealth);
                        pop_sort_header(ui, "Mig", &mut sort, &mut descending, PopSort::Migration);
                        ui.end_row();

                        for r in &filtered {
                            ui.label(&r.label);
                            ui.label(&r.demographic);
                            ui.label(&r.location);
                            ui.label(format_int(r.count));
                            ui.colored_label(sentiment_color(r.sentiment), format!("{}", r.sentiment));
                            ui.colored_label(food_color(r.food), format!("{}", r.food));
                            ui.label(format_credits(r.wealth));
                            let mig_color = if r.migration >= 1.0 {
                                egui::Color32::from_rgb(240, 100, 90)
                            } else if r.migration >= 0.5 {
                                egui::Color32::from_rgb(230, 200, 90)
                            } else {
                                egui::Color32::from_gray(200)
                            };
                            ui.colored_label(mig_color, format!("{:.2}", r.migration));
                            ui.end_row();
                        }
                    });
            });
        });

    state.open = open;
    state.sort = sort;
    state.descending = descending;
    state.filter = filter;
}

fn pop_sort_header(
    ui: &mut egui::Ui,
    label: &str,
    current: &mut PopSort,
    descending: &mut bool,
    target: PopSort,
) {
    let arrow = if *current == target {
        if *descending { " ▼" } else { " ▲" }
    } else {
        ""
    };
    let text = egui::RichText::new(format!("{label}{arrow}")).strong();
    if ui.button(text).clicked() {
        if *current == target {
            *descending = !*descending;
        } else {
            *current = target;
            // Numeric-y columns default to descending (biggest first),
            // text-y columns default to ascending.
            *descending = !matches!(target, PopSort::Label | PopSort::Location);
        }
    }
}

fn sentiment_color(s: i32) -> egui::Color32 {
    if s >= 50 {
        egui::Color32::from_rgb(120, 220, 120)
    } else if s >= 30 {
        egui::Color32::from_rgb(230, 200, 90)
    } else if s >= 0 {
        egui::Color32::from_rgb(230, 150, 100)
    } else {
        egui::Color32::from_rgb(240, 100, 90)
    }
}

fn food_color(f: i32) -> egui::Color32 {
    // Food sat scale is roughly 0..=100. <30 is the "emergency water"
    // territory; >70 is the comfortable zone.
    if f >= 70 {
        egui::Color32::from_rgb(120, 220, 120)
    } else if f >= 30 {
        egui::Color32::from_rgb(230, 200, 90)
    } else {
        egui::Color32::from_rgb(240, 100, 90)
    }
}

fn format_int(n: i64) -> String {
    // Thousands separator for population counts so "1204000" reads
    // as "1,204,000" at a glance.
    let s = n.abs().to_string();
    let mut out = String::new();
    for (i, c) in s.chars().rev().enumerate() {
        if i > 0 && i % 3 == 0 {
            out.push(',');
        }
        out.push(c);
    }
    let result: String = out.chars().rev().collect();
    if n < 0 {
        format!("-{}", result)
    } else {
        result
    }
}

// =============================================================================
// Ship details panel
// =============================================================================
//
// The "inspector as live debugger" payoff of the embedded arch. Reads
// every ship component directly from hecs — no snapshot marshalling —
// and renders one section per component. Opens when a ship is selected
// in the ship list; closes itself when the user clears the selection.

fn ship_details_panel(
    mut ctx: EguiContexts,
    mut sim: ResMut<Sim>,
    mut selected: ResMut<SelectedShip>,
    mut focus_req: ResMut<CameraFocusRequest>,
) {
    use sim_core::agents::ship::{
        ShipAI, ShipCargo, ShipCrew, ShipCrewSkills, ShipEconomy, ShipFitting, ShipFuel,
        ShipIdentity, ShipLifecycle, ShipPosition, ShipProgression, ShipTransit,
    };

    let Some(ship_id) = selected.0.clone() else {
        return;
    };

    let Some(&entity) = sim.store.ship_by_id.get(&ship_id) else {
        // Ship was deleted / retired — clear selection so the panel
        // doesn't keep trying to render a ghost.
        selected.0 = None;
        return;
    };

    let mut still_open = true;
    // Captured by the egui closure; consulted after the closure ends
    // so we don't try to mutably borrow sim while a read-query is
    // still alive inside.
    let mut grant_xp_requested = false;
    let mut delete_requested = false;
    let title = format!("Ship · {}", ship_id);

    egui::Window::new(title)
        .default_width(520.0)
        .default_height(640.0)
        .open(&mut still_open)
        .show(ctx.ctx_mut(), |ui| {
            let Ok(mut q) = sim.store.world.query_one::<(
                &ShipIdentity,
                &ShipPosition,
                &ShipTransit,
                &ShipCargo,
                &ShipFuel,
                &ShipEconomy,
                &ShipAI,
                &ShipCrew,
                &ShipCrewSkills,
                &ShipProgression,
                &ShipFitting,
                &ShipLifecycle,
            )>(entity) else {
                ui.label("(ship entity missing components)");
                return;
            };
            let Some((id, pos, transit, cargo, fuel, econ, ai, crew, skills, prog, fit, life)) =
                q.get()
            else {
                ui.label("(ship entity missing components)");
                return;
            };

            // Toolbar: camera focus + admin actions. Camera focus
            // writes a separate Resource so it's safe inline. Grant
            // XP / Delete flip local bools that the system processes
            // after the query borrow ends — hecs forbids concurrent
            // read and write on the same world.
            ui.horizontal(|ui| {
                if ui.button("Focus camera").clicked() {
                    let (x, y) = pos.position;
                    focus_req.0 = Some(Vec3::new(x * SCALE_FACTOR, 0.0, y * SCALE_FACTOR));
                }
                ui.separator();
                ui.label(
                    egui::RichText::new("admin:")
                        .small()
                        .color(egui::Color32::from_gray(160)),
                );
                if ui
                    .button(egui::RichText::new("+100 XP").small())
                    .on_hover_text(
                        "Instantly grant 100 XP to this ship (embedded-client \
                         admin: mutates the hecs component in place, no HTTP).",
                    )
                    .clicked()
                {
                    grant_xp_requested = true;
                }
                if ui
                    .button(
                        egui::RichText::new("Delete")
                            .small()
                            .color(egui::Color32::from_rgb(240, 100, 90)),
                    )
                    .on_hover_text(
                        "Destroy this ship. Releases any accepted contracts \
                         back to the board; PickedUp cargo is lost. In-memory \
                         only — a restart reloads the ship from DB.",
                    )
                    .clicked()
                {
                    delete_requested = true;
                }
            });
            ui.separator();

            egui::ScrollArea::vertical().show(ui, |ui| {
                // Identity
                ui.label(egui::RichText::new("Identity").strong().size(14.0));
                egui::Grid::new("details_identity")
                    .num_columns(2)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        ui.label("Name"); ui.label(&id.name); ui.end_row();
                        ui.label("Class"); ui.label(&id.class); ui.end_row();
                        ui.label("Size"); ui.label(format!("{:?}", id.size)); ui.end_row();
                        ui.label("Faction"); ui.label(&id.faction_id); ui.end_row();
                    });
                ui.separator();

                // Position / transit
                ui.label(egui::RichText::new("Position").strong().size(14.0));
                egui::Grid::new("details_pos")
                    .num_columns(2)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        ui.label("System"); ui.label(&pos.system_id); ui.end_row();
                        ui.label("Location");
                        ui.label(pos.location_name.as_deref().unwrap_or("(in transit)"));
                        ui.end_row();
                        ui.label("Docked");
                        ui.label(if pos.docked_at.is_some() { "yes" } else { "no" });
                        ui.end_row();
                        ui.label("XY");
                        ui.label(format!("{:.1}, {:.1}", pos.position.0, pos.position.1));
                        ui.end_row();
                        if let Some(t) = &transit.transit {
                            let progress = if t.distance_total > 0.0 {
                                (t.distance_travelled / t.distance_total).clamp(0.0, 1.0) * 100.0
                            } else {
                                0.0
                            };
                            ui.label("Transit");
                            ui.label(format!(
                                "{} → {} ({:.1}%)",
                                t.from, t.to, progress,
                            ));
                            ui.end_row();
                            ui.label("Arrival tick");
                            ui.label(format!("{}", t.arrival_tick));
                            ui.end_row();
                        }
                    });
                ui.separator();

                // Economy
                ui.label(egui::RichText::new("Economy").strong().size(14.0));
                egui::Grid::new("details_econ")
                    .num_columns(2)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        ui.label("Credits"); ui.label(format_credits(econ.credits)); ui.end_row();
                        ui.label("Efficiency"); ui.label(format!("{:.2}", econ.efficiency)); ui.end_row();
                        ui.label("Active contract");
                        ui.label(econ.active_contract_id.as_deref().unwrap_or("—"));
                        ui.end_row();
                    });
                if !econ.faction_reputation.is_empty() {
                    ui.label(egui::RichText::new("Reputation").italics().small());
                    egui::Grid::new("details_rep")
                        .num_columns(2)
                        .spacing([10.0, 2.0])
                        .show(ui, |ui| {
                            let mut reps: Vec<_> = econ.faction_reputation.iter().collect();
                            reps.sort_by(|a, b| b.1.cmp(a.1));
                            for (faction, rep) in reps {
                                ui.label(faction);
                                ui.label(format!("{}", rep));
                                ui.end_row();
                            }
                        });
                }
                ui.separator();

                // Fuel
                ui.label(egui::RichText::new("Fuel").strong().size(14.0));
                egui::Grid::new("details_fuel")
                    .num_columns(2)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        let frac = fuel.fraction();
                        let frac_color = if frac >= 0.5 {
                            egui::Color32::from_rgb(120, 220, 120)
                        } else if frac >= 0.2 {
                            egui::Color32::from_rgb(230, 200, 90)
                        } else {
                            egui::Color32::from_rgb(240, 100, 90)
                        };
                        ui.label("Fuel");
                        ui.colored_label(
                            frac_color,
                            format!("{:.1} / {:.0} ({:.0}%)", fuel.fuel, fuel.fuel_capacity, frac * 100.0),
                        );
                        ui.end_row();
                        ui.label("Speed mod"); ui.label(format!("{:.2}×", fuel.speed_modifier)); ui.end_row();
                        ui.label("Burn rate"); ui.label(format!("{:.3}", fuel.fuel_consumption_rate)); ui.end_row();
                    });
                ui.separator();

                // Cargo
                ui.label(egui::RichText::new("Cargo").strong().size(14.0));
                let used = cargo.used();
                ui.label(format!("Hold: {} / {} ({:.0}%)",
                    used,
                    cargo.capacity,
                    if cargo.capacity > 0 {
                        used as f32 / cargo.capacity as f32 * 100.0
                    } else {
                        0.0
                    }));
                if !cargo.cargo.is_empty() {
                    egui::Grid::new("details_cargo")
                        .num_columns(2)
                        .spacing([10.0, 2.0])
                        .show(ui, |ui| {
                            let mut items: Vec<_> = cargo.cargo.iter().collect();
                            items.sort_by_key(|(c, _)| c.as_str());
                            for (c, qty) in items {
                                ui.label(c.as_str());
                                ui.label(format!("{}", qty));
                                ui.end_row();
                            }
                        });
                }
                ui.separator();

                // Crew
                ui.label(egui::RichText::new("Crew").strong().size(14.0));
                egui::Grid::new("details_crew")
                    .num_columns(2)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        ui.label("Size"); ui.label(format!("{}", crew.size)); ui.end_row();
                        ui.label("Task"); ui.label(crew.current_task.as_str()); ui.end_row();
                        ui.label("Morale");
                        ui.colored_label(
                            crew_bar_color(crew.morale),
                            format!("{:.0}", crew.morale),
                        );
                        ui.end_row();
                        ui.label("Hunger");
                        ui.colored_label(
                            // Inverse scale — hunger high = bad.
                            crew_bar_color(100.0 - crew.hunger),
                            format!("{:.0}", crew.hunger),
                        );
                        ui.end_row();
                        ui.label("Fatigue");
                        ui.colored_label(
                            crew_bar_color(100.0 - crew.fatigue),
                            format!("{:.0}", crew.fatigue),
                        );
                        ui.end_row();
                        ui.label("Health"); ui.label(format!("{:.0}", crew.health)); ui.end_row();
                        ui.label("Wages owed"); ui.label(format!("{}", crew.wages_credits)); ui.end_row();
                        ui.label("Skills");
                        ui.label(format!(
                            "nav {}  eng {}  trd {}  cmb {}",
                            skills.navigation, skills.engineering, skills.trading, skills.combat,
                        ));
                        ui.end_row();
                    });
                ui.separator();

                // AI
                ui.label(egui::RichText::new("AI").strong().size(14.0));
                egui::Grid::new("details_ai")
                    .num_columns(2)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        ui.label("Goal"); ui.label(&ai.current_goal); ui.end_row();
                        ui.label("Goal score"); ui.label(format!("{:.2}", ai.current_goal_score)); ui.end_row();
                        ui.label("Planned at tick"); ui.label(format!("{}", ai.last_plan_tick)); ui.end_row();
                        ui.label("Personality");
                        ui.label(format!(
                            "profit {:.2}  safety {:.2}  morale {:.2}  explore {:.2}",
                            ai.personality.profit,
                            ai.personality.safety,
                            ai.personality.morale,
                            ai.personality.exploration,
                        ));
                        ui.end_row();
                    });
                ui.separator();

                // Progression
                ui.label(egui::RichText::new("Progression").strong().size(14.0));
                egui::Grid::new("details_prog")
                    .num_columns(2)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        ui.label("Level");
                        ui.label(format!("{} / {}", prog.level, sim_core::agents::ship::SHIP_LEVEL_CAP));
                        ui.end_row();
                        ui.label("XP");
                        ui.label(format!("{} / {}", prog.xp, prog.next_level_threshold()));
                        ui.end_row();
                        ui.label("Retrofit points"); ui.label(format!("{}", prog.retrofit_points)); ui.end_row();
                        ui.label("Idle ticks"); ui.label(format!("{}", life.idle_ticks)); ui.end_row();
                        ui.label("Broke / hoard strikes");
                        ui.label(format!("{} / {}", life.broke_strikes, life.hoard_strikes));
                        ui.end_row();
                    });
                ui.separator();

                // Fitting
                ui.label(egui::RichText::new("Fitting").strong().size(14.0));
                egui::Grid::new("details_fit")
                    .num_columns(2)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        for (slot_idx, slot) in sim_core::modules::SLOTS.iter().enumerate() {
                            ui.label(slot.as_str());
                            ui.label(fit.slots[slot_idx].unwrap_or("—"));
                            ui.end_row();
                        }
                        ui.label("Sensor range");
                        ui.label(format!("{:.1} AU", fit.derived.sensor_range_au));
                        ui.end_row();
                        ui.label("Cargo mult");
                        ui.label(format!("{:.2}×", fit.derived.cargo_capacity_mult));
                        ui.end_row();
                        ui.label("Speed mult");
                        ui.label(format!("{:.2}×", fit.derived.speed_mult));
                        ui.end_row();
                        ui.label("Comms bonus");
                        ui.label(format!("{:+.2}", fit.derived.comms_bonus));
                        ui.end_row();
                    });
            });
        });

    if grant_xp_requested {
        use sim_core::agents::ship::ShipProgression;
        if let Ok(mut prog) = sim.store.world.get::<&mut ShipProgression>(entity) {
            let levels = prog.grant_xp(100);
            info!(
                "client_bevy admin: +100 XP to {} ({}level+{})",
                ship_id,
                if levels > 0 { "leveled up! " } else { "" },
                prog.retrofit_points,
            );
        }
    }

    if delete_requested {
        use sim_core::agents::facility::FacilityStorage;
        // Step 1: yank the ship entity out of any docked list + dock
        // queue. If we skip this the entry wedges behind a despawned
        // entity and blocks live ships behind it. Mirrors the admin
        // cascade in sim_server::engine::admin_remove_ship.
        for (_e, storage) in sim.store.world.query_mut::<&mut FacilityStorage>() {
            storage.docked_ships.retain(|&e| e != entity);
            storage.dock_queue.retain(|&e| e != entity);
        }
        // Step 2: release any contracts tied to this ship. Accepted
        // → Posted (re-postable); PickedUp → Expired (cargo lost with
        // the ship). `drop` is ignored here because the client
        // doesn't broadcast events the way sim_server does.
        let _ = sim.store.contracts.drop_ship_holdings(&ship_id);
        // Step 3: actually despawn + forget the id mapping.
        let _ = sim.store.world.despawn(entity);
        sim.store.ship_by_id.remove(&ship_id);
        info!("client_bevy admin: deleted ship {}", ship_id);
        // Clear selection so the details panel closes cleanly on the
        // next frame (entity lookup will fail either way, but being
        // explicit avoids one wasted frame of "entity missing"
        // render).
        selected.0 = None;
        // Render entities in Bevy still reference the dead sim entity
        // via ShipEntity.sim_id; sync_positions leaves them in place
        // because there's no matching id in ship_state. That means
        // the Bevy ship mesh lingers until restart, which is OK for
        // embedded admin-mode but worth noting — a cleanup system
        // that despawns stale Bevy entities when sim_id isn't found
        // would land cleanly here if it ever becomes distracting.
        return;
    }

    if !still_open {
        selected.0 = None;
    }
}

fn crew_bar_color(v: f32) -> egui::Color32 {
    if v >= 70.0 {
        egui::Color32::from_rgb(120, 220, 120)
    } else if v >= 40.0 {
        egui::Color32::from_rgb(230, 200, 90)
    } else {
        egui::Color32::from_rgb(240, 100, 90)
    }
}

// =============================================================================
// Facility list + details
// =============================================================================
//
// Mirrors ships: a filterable/sortable list; clicking a row sets
// SelectedFacility, opening a details panel with everything on the
// facility entity. Both list and details read hecs directly.

#[derive(Resource, Default)]
struct FacilityListState {
    open: bool,
    sort: FacilitySort,
    descending: bool,
    filter: String,
}

#[derive(Default, PartialEq, Eq, Clone, Copy)]
enum FacilitySort {
    #[default]
    Name,
    Type,
    Faction,
    Location,
    Credits,
    Docked,
    Level,
}

#[derive(Resource, Default)]
pub struct SelectedFacility(pub Option<String>);

struct FacilityRow {
    id: String,
    name: String,
    facility_type: String,
    faction: String,
    location: String,
    credits: i64,
    docked: u32,
    capacity: u32,
    level: u8,
    abandoned: bool,
}

fn facility_list_panel(
    mut ctx: EguiContexts,
    sim: Res<Sim>,
    mut state: ResMut<FacilityListState>,
    mut selected: ResMut<SelectedFacility>,
) {
    use sim_core::agents::facility::{
        FacilityIdentity, FacilityLifecycle, FacilityLocation, FacilityOperations,
        FacilityStorage,
    };

    let mut open = state.open;
    let mut sort = state.sort;
    let mut descending = state.descending;
    let mut filter = state.filter.clone();

    if !open {
        return;
    }

    let rows: Vec<FacilityRow> = sim
        .store
        .world
        .query::<(
            &FacilityIdentity,
            &FacilityLocation,
            &FacilityOperations,
            &FacilityStorage,
            &FacilityLifecycle,
        )>()
        .iter()
        .map(|(_e, (id, loc, ops, stor, life))| FacilityRow {
            id: id.id.clone(),
            name: id.name.clone(),
            facility_type: id.facility_type.clone(),
            faction: id.faction_id.clone(),
            location: loc.location_name.clone(),
            credits: ops.credits,
            docked: stor.docked_ships.len() as u32,
            capacity: ops.docking_capacity,
            level: life.level,
            abandoned: life.abandoned,
        })
        .collect();

    let filter_lc = filter.to_lowercase();
    let mut filtered: Vec<&FacilityRow> = rows
        .iter()
        .filter(|r| {
            if filter_lc.is_empty() {
                return true;
            }
            r.name.to_lowercase().contains(&filter_lc)
                || r.id.to_lowercase().contains(&filter_lc)
                || r.facility_type.to_lowercase().contains(&filter_lc)
                || r.faction.to_lowercase().contains(&filter_lc)
                || r.location.to_lowercase().contains(&filter_lc)
        })
        .collect();

    filtered.sort_by(|a, b| {
        let cmp = match sort {
            FacilitySort::Name => a.name.cmp(&b.name),
            FacilitySort::Type => a.facility_type.cmp(&b.facility_type),
            FacilitySort::Faction => a.faction.cmp(&b.faction),
            FacilitySort::Location => a.location.cmp(&b.location),
            FacilitySort::Credits => a.credits.cmp(&b.credits),
            FacilitySort::Docked => a.docked.cmp(&b.docked),
            FacilitySort::Level => a.level.cmp(&b.level),
        };
        if descending { cmp.reverse() } else { cmp }
    });

    let total = rows.len();
    let shown = filtered.len();

    egui::Window::new(format!("Facilities · {shown}/{total}"))
        .default_width(800.0)
        .default_height(460.0)
        .open(&mut open)
        .show(ctx.ctx_mut(), |ui| {
            ui.horizontal(|ui| {
                ui.label("filter:");
                ui.text_edit_singleline(&mut filter);
            });
            ui.separator();

            egui::ScrollArea::vertical().show(ui, |ui| {
                egui::Grid::new("facility_list_grid")
                    .striped(true)
                    .num_columns(7)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        fac_sort_header(ui, "Name", &mut sort, &mut descending, FacilitySort::Name);
                        fac_sort_header(ui, "Type", &mut sort, &mut descending, FacilitySort::Type);
                        fac_sort_header(ui, "Faction", &mut sort, &mut descending, FacilitySort::Faction);
                        fac_sort_header(ui, "Location", &mut sort, &mut descending, FacilitySort::Location);
                        fac_sort_header(ui, "Credits", &mut sort, &mut descending, FacilitySort::Credits);
                        fac_sort_header(ui, "Dock", &mut sort, &mut descending, FacilitySort::Docked);
                        fac_sort_header(ui, "Lvl", &mut sort, &mut descending, FacilitySort::Level);
                        ui.end_row();

                        for r in &filtered {
                            let is_sel = selected.0.as_deref() == Some(r.id.as_str());
                            let name_text = if r.abandoned {
                                egui::RichText::new(&r.name)
                                    .color(egui::Color32::from_gray(140))
                                    .strikethrough()
                            } else {
                                egui::RichText::new(&r.name)
                            };
                            if ui.selectable_label(is_sel, name_text).clicked() {
                                selected.0 = Some(r.id.clone());
                            }
                            ui.label(&r.facility_type);
                            ui.label(&r.faction);
                            ui.label(&r.location);
                            ui.label(format_credits(r.credits));
                            ui.label(format!("{}/{}", r.docked, r.capacity));
                            ui.label(format!("{}", r.level));
                            ui.end_row();
                        }
                    });
            });
        });

    state.open = open;
    state.sort = sort;
    state.descending = descending;
    state.filter = filter;
}

fn fac_sort_header(
    ui: &mut egui::Ui,
    label: &str,
    current: &mut FacilitySort,
    descending: &mut bool,
    target: FacilitySort,
) {
    let arrow = if *current == target {
        if *descending { " ▼" } else { " ▲" }
    } else {
        ""
    };
    let text = egui::RichText::new(format!("{label}{arrow}")).strong();
    if ui.button(text).clicked() {
        if *current == target {
            *descending = !*descending;
        } else {
            *current = target;
            *descending = matches!(
                target,
                FacilitySort::Credits | FacilitySort::Docked | FacilitySort::Level,
            );
        }
    }
}

fn facility_details_panel(
    mut ctx: EguiContexts,
    sim: Res<Sim>,
    mut selected: ResMut<SelectedFacility>,
    mut focus_req: ResMut<CameraFocusRequest>,
) {
    use sim_core::agents::celestial_body::{BodyIdentity, BodyOrbit};
    use sim_core::agents::facility::{
        FacilityCrew, FacilityFitting, FacilityIdentity, FacilityLifecycle, FacilityLocation,
        FacilityOperations, FacilityStorage,
    };

    let Some(fac_id) = selected.0.clone() else {
        return;
    };
    let Some(&entity) = sim.store.facility_by_id.get(&fac_id) else {
        selected.0 = None;
        return;
    };

    let mut still_open = true;
    let title = format!("Facility · {}", fac_id);

    egui::Window::new(title)
        .default_width(520.0)
        .default_height(640.0)
        .open(&mut still_open)
        .show(ctx.ctx_mut(), |ui| {
            let Ok(mut q) = sim.store.world.query_one::<(
                &FacilityIdentity,
                &FacilityLocation,
                &FacilityOperations,
                &FacilityStorage,
                &FacilityLifecycle,
            )>(entity) else {
                ui.label("(facility entity missing components)");
                return;
            };
            let Some((id, loc, ops, storage, life)) = q.get() else {
                ui.label("(facility entity missing components)");
                return;
            };

            // Optional components — gates don't have fitting/crew, so
            // wrap each in a separate query that degrades gracefully.
            let fitting = sim
                .store
                .world
                .query_one::<&FacilityFitting>(entity)
                .ok()
                .and_then(|mut q| q.get().cloned());
            let crew = sim
                .store
                .world
                .query_one::<&FacilityCrew>(entity)
                .ok()
                .and_then(|mut q| q.get().cloned());

            // Toolbar: focus camera on the facility's owning body. We
            // don't apply the facility's small orbital offset here —
            // body-centre is close enough for "fly the camera there"
            // intent at galactic scale.
            ui.horizontal(|ui| {
                if ui.button("Focus camera").clicked() {
                    let body_pos = sim
                        .store
                        .world
                        .query::<(&BodyIdentity, &BodyOrbit)>()
                        .iter()
                        .find(|(_e, (b, _))| b.body_id == id.body_id)
                        .map(|(_e, (_, o))| o.universe_position());
                    if let Some((x, y)) = body_pos {
                        focus_req.0 = Some(Vec3::new(x * SCALE_FACTOR, 0.0, y * SCALE_FACTOR));
                    }
                }
            });
            ui.separator();

            egui::ScrollArea::vertical().show(ui, |ui| {
                if life.abandoned {
                    ui.colored_label(
                        egui::Color32::from_rgb(240, 100, 90),
                        egui::RichText::new("ABANDONED").strong(),
                    );
                    ui.separator();
                }

                ui.label(egui::RichText::new("Identity").strong().size(14.0));
                egui::Grid::new("fac_details_identity")
                    .num_columns(2)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        ui.label("Name"); ui.label(&id.name); ui.end_row();
                        ui.label("Type"); ui.label(&id.facility_type); ui.end_row();
                        ui.label("Body"); ui.label(&id.body_id); ui.end_row();
                        ui.label("Location"); ui.label(&loc.location_name); ui.end_row();
                        ui.label("Faction"); ui.label(&id.faction_id); ui.end_row();
                    });
                ui.separator();

                ui.label(egui::RichText::new("Operations").strong().size(14.0));
                egui::Grid::new("fac_details_ops")
                    .num_columns(2)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        ui.label("Credits"); ui.label(format_credits(ops.credits)); ui.end_row();
                        ui.label("Condition");
                        let cond_color = if ops.condition >= 0.7 {
                            egui::Color32::from_rgb(120, 220, 120)
                        } else if ops.condition >= 0.3 {
                            egui::Color32::from_rgb(230, 200, 90)
                        } else {
                            egui::Color32::from_rgb(240, 100, 90)
                        };
                        ui.colored_label(cond_color, format!("{:.0}%", ops.condition * 100.0));
                        ui.end_row();
                        ui.label("Docking");
                        ui.label(format!(
                            "{} / {} (+{} queued)",
                            storage.docked_ships.len(),
                            ops.docking_capacity,
                            storage.dock_queue.len(),
                        ));
                        ui.end_row();
                    });
                ui.separator();

                ui.label(egui::RichText::new("Lifecycle").strong().size(14.0));
                egui::Grid::new("fac_details_life")
                    .num_columns(2)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        ui.label("Level");
                        ui.label(format!("{} / {}", life.level, sim_core::agents::facility::FACILITY_LEVEL_CAP));
                        ui.end_row();
                        ui.label("XP");
                        ui.label(format!("{} / {}", life.xp, life.next_level_threshold()));
                        ui.end_row();
                        if life.abandon_counter > 0 {
                            ui.label("Abandon countdown");
                            ui.label(format!("{}", life.abandon_counter));
                            ui.end_row();
                        }
                    });
                ui.separator();

                ui.label(egui::RichText::new("Reserves").strong().size(14.0));
                if storage.reserves.is_empty() {
                    ui.label(
                        egui::RichText::new("(no reserves)")
                            .italics()
                            .color(egui::Color32::from_gray(160)),
                    );
                } else {
                    egui::Grid::new("fac_details_reserves")
                        .striped(true)
                        .num_columns(2)
                        .spacing([10.0, 2.0])
                        .show(ui, |ui| {
                            let mut items: Vec<_> = storage.reserves.iter().collect();
                            items.sort_by_key(|(c, _)| c.as_str());
                            for (c, qty) in items {
                                ui.label(c.as_str());
                                ui.label(format!("{:.0}", qty));
                                ui.end_row();
                            }
                        });
                }
                ui.separator();

                if let Some(fit) = fitting {
                    ui.label(egui::RichText::new("Fitting").strong().size(14.0));
                    egui::Grid::new("fac_details_fit")
                        .num_columns(2)
                        .spacing([12.0, 2.0])
                        .show(ui, |ui| {
                            for slot in sim_core::facility_modules::FACILITY_SLOTS.iter() {
                                ui.label(slot.as_str());
                                ui.label(fit.slots[slot.index()].unwrap_or("—"));
                                ui.end_row();
                            }
                            ui.label("Recipe output mult");
                            ui.label(format!("{:.2}×", fit.derived.recipe_output_mult));
                            ui.end_row();
                            ui.label("Max batches bonus");
                            ui.label(format!("+{}", fit.derived.max_batches_bonus));
                            ui.end_row();
                        });
                    ui.separator();
                }

                if let Some(crew) = crew {
                    ui.label(egui::RichText::new("Crew").strong().size(14.0));
                    egui::Grid::new("fac_details_crew")
                        .num_columns(2)
                        .spacing([12.0, 2.0])
                        .show(ui, |ui| {
                            ui.label("Count"); ui.label(format!("{}", crew.crew_count)); ui.end_row();
                            ui.label("Morale");
                            ui.colored_label(crew_bar_color(crew.morale), format!("{:.0}", crew.morale));
                            ui.end_row();
                            ui.label("Hunger");
                            ui.colored_label(crew_bar_color(100.0 - crew.hunger), format!("{:.0}", crew.hunger));
                            ui.end_row();
                            ui.label("Efficiency");
                            ui.label(format!("{:.2}×", crew.efficiency()));
                            ui.end_row();
                        });
                    ui.separator();
                }

                if !storage.docked_ships.is_empty() || !storage.dock_queue.is_empty() {
                    ui.label(egui::RichText::new("Dock").strong().size(14.0));
                    ui.label(format!("Docked: {} ships", storage.docked_ships.len()));
                    ui.label(format!("Queue: {} waiting", storage.dock_queue.len()));
                    if !storage.pending_deliveries.is_empty() {
                        ui.label(format!(
                            "Pending deliveries: {}",
                            storage.pending_deliveries.len()
                        ));
                    }
                }
            });
        });

    if !still_open {
        selected.0 = None;
    }
}

// =============================================================================
// Retirements panel
// =============================================================================
//
// Historical ship losses, loaded once at startup from the `retired_ships`
// table. Post-mortem view: name, class, faction, final credits + fuel
// + morale, the strike counters that tipped them into auto-retirement,
// the reason string, and the tick they retired at. Filter + sort.

#[derive(Resource, Default)]
struct RetirementsState {
    open: bool,
    sort: RetirementSort,
    descending: bool,
    filter: String,
}

#[derive(Default, PartialEq, Eq, Clone, Copy)]
enum RetirementSort {
    #[default]
    Tick,
    Name,
    Class,
    Faction,
    Credits,
    Reason,
}

fn retirements_panel(
    mut ctx: EguiContexts,
    retirements: Res<Retirements>,
    mut state: ResMut<RetirementsState>,
) {
    let mut open = state.open;
    let mut sort = state.sort;
    let mut descending = state.descending;
    let mut filter = state.filter.clone();

    if !open {
        return;
    }

    let filter_lc = filter.to_lowercase();
    let mut filtered: Vec<&sim_db::persistence::RetirementRow> = retirements
        .0
        .iter()
        .filter(|r| {
            if filter_lc.is_empty() {
                return true;
            }
            r.name.to_lowercase().contains(&filter_lc)
                || r.agent_id.to_lowercase().contains(&filter_lc)
                || r.class.to_lowercase().contains(&filter_lc)
                || r.faction_id.to_lowercase().contains(&filter_lc)
                || r.final_location.to_lowercase().contains(&filter_lc)
                || r.reason.to_lowercase().contains(&filter_lc)
        })
        .collect();

    filtered.sort_by(|a, b| {
        let cmp = match sort {
            RetirementSort::Tick => a.retired_at_tick.cmp(&b.retired_at_tick),
            RetirementSort::Name => a.name.cmp(&b.name),
            RetirementSort::Class => a.class.cmp(&b.class),
            RetirementSort::Faction => a.faction_id.cmp(&b.faction_id),
            RetirementSort::Credits => a.final_credits.cmp(&b.final_credits),
            RetirementSort::Reason => a.reason.cmp(&b.reason),
        };
        if descending { cmp.reverse() } else { cmp }
    });

    let total = retirements.0.len();
    let shown = filtered.len();

    egui::Window::new(format!("Retired · {shown}/{total}"))
        .default_width(860.0)
        .default_height(480.0)
        .open(&mut open)
        .show(ctx.ctx_mut(), |ui| {
            ui.horizontal(|ui| {
                ui.label("filter:");
                ui.text_edit_singleline(&mut filter);
            });
            ui.label(
                egui::RichText::new(
                    "Snapshot of past decommissions. Newest-first by default. \
                     Loaded once at startup — new retirements during play \
                     will appear after a restart (apply_ship_commands wiring \
                     is deferred to Bundle 2b.4).",
                )
                .small()
                .color(egui::Color32::from_gray(150)),
            );
            ui.separator();

            if total == 0 {
                ui.label(
                    egui::RichText::new("(no retirements yet — fresh DB or no decommissions)")
                        .italics()
                        .color(egui::Color32::from_gray(160)),
                );
                return;
            }

            egui::ScrollArea::vertical().show(ui, |ui| {
                egui::Grid::new("retirements_grid")
                    .striped(true)
                    .num_columns(8)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        ret_sort_header(ui, "Tick", &mut sort, &mut descending, RetirementSort::Tick);
                        ret_sort_header(ui, "Name", &mut sort, &mut descending, RetirementSort::Name);
                        ret_sort_header(ui, "Class", &mut sort, &mut descending, RetirementSort::Class);
                        ret_sort_header(ui, "Faction", &mut sort, &mut descending, RetirementSort::Faction);
                        ui.label(egui::RichText::new("Location").strong());
                        ret_sort_header(ui, "Credits", &mut sort, &mut descending, RetirementSort::Credits);
                        ui.label(egui::RichText::new("Morale / Fuel").strong());
                        ret_sort_header(ui, "Reason", &mut sort, &mut descending, RetirementSort::Reason);
                        ui.end_row();

                        for r in &filtered {
                            ui.label(format!("{}", r.retired_at_tick));
                            ui.label(&r.name);
                            ui.label(&r.class);
                            ui.label(&r.faction_id);
                            ui.label(&r.final_location);
                            ui.label(format_credits(r.final_credits));
                            ui.label(format!("{} / {}", r.final_crew_morale, r.final_fuel_pct));
                            let color = reason_color(&r.reason);
                            ui.colored_label(color, &r.reason);
                            ui.end_row();
                        }
                    });
            });
        });

    state.open = open;
    state.filter = filter;
    state.sort = sort;
    state.descending = descending;
}

fn ret_sort_header(
    ui: &mut egui::Ui,
    label: &str,
    current: &mut RetirementSort,
    descending: &mut bool,
    target: RetirementSort,
) {
    let arrow = if *current == target {
        if *descending { " ▼" } else { " ▲" }
    } else {
        ""
    };
    let text = egui::RichText::new(format!("{label}{arrow}")).strong();
    if ui.button(text).clicked() {
        if *current == target {
            *descending = !*descending;
        } else {
            *current = target;
            // Tick + credits default descending (newest / richest
            // first); text columns ascending.
            *descending = matches!(
                target,
                RetirementSort::Tick | RetirementSort::Credits,
            );
        }
    }
}

fn reason_color(reason: &str) -> egui::Color32 {
    // Rough colouring against the known strike kinds. Anything else
    // (admin deletes, future causes) renders neutral.
    let lc = reason.to_lowercase();
    if lc.contains("broke") {
        egui::Color32::from_rgb(240, 100, 90)
    } else if lc.contains("hoard") {
        egui::Color32::from_rgb(230, 200, 90)
    } else if lc.contains("admin") {
        egui::Color32::from_rgb(160, 160, 230)
    } else {
        egui::Color32::from_gray(210)
    }
}

// =============================================================================
// Construction sites panel
// =============================================================================
//
// Phase 19c sites — one row per pending build, with a progress bar
// for delivered / required cargo. "Focus" button jumps the camera to
// the site's universe position (same coordinate space as the body/
// facility render). Lists the commodity each delivery consumes and
// the faction sponsoring the build.

#[derive(Resource, Default)]
struct ConstructionState {
    open: bool,
}

fn construction_panel(
    mut ctx: EguiContexts,
    sim: Res<Sim>,
    mut state: ResMut<ConstructionState>,
    mut focus_req: ResMut<CameraFocusRequest>,
) {
    use sim_core::agents::construction::ConstructionSite;

    let mut open = state.open;
    if !open {
        return;
    }

    struct Row {
        id: String,
        name: String,
        facility_type: String,
        faction: String,
        location: String,
        body: String,
        commodity: String,
        progress: f32,
        delivered: u32,
        required: u32,
        remaining: u32,
        spawned_at: u64,
        position: (f32, f32),
    }

    let mut rows: Vec<Row> = sim
        .store
        .world
        .query::<&ConstructionSite>()
        .iter()
        .map(|(_e, s)| Row {
            id: s.id.clone(),
            name: s.name.clone(),
            facility_type: s.facility_type.clone(),
            faction: s.faction_id.clone(),
            location: s.location_name.clone(),
            body: s.body_id.clone(),
            commodity: s.commodity.as_str().to_string(),
            progress: s.progress(),
            delivered: s.progress_delivered,
            required: s.progress_required,
            remaining: s.remaining(),
            spawned_at: s.spawned_at_tick,
            position: s.position,
        })
        .collect();

    // Sort by progress descending — closest-to-done jumps to the top,
    // the "almost-there" builds are the most interesting.
    rows.sort_by(|a, b| {
        b.progress
            .partial_cmp(&a.progress)
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    let total = rows.len();

    egui::Window::new(format!("Construction · {total}"))
        .default_width(860.0)
        .default_height(420.0)
        .open(&mut open)
        .show(ctx.ctx_mut(), |ui| {
            ui.label(
                egui::RichText::new(
                    "Pending construction sites. Ships delivering their commodity \
                     to the target location accrue progress; at 100% the site \
                     materialises into a real facility.",
                )
                .small()
                .color(egui::Color32::from_gray(150)),
            );
            ui.separator();

            if total == 0 {
                ui.label(
                    egui::RichText::new("(no construction sites)")
                        .italics()
                        .color(egui::Color32::from_gray(160)),
                );
                return;
            }

            egui::ScrollArea::vertical().show(ui, |ui| {
                for r in &rows {
                    ui.group(|ui| {
                        ui.horizontal(|ui| {
                            ui.label(egui::RichText::new(&r.name).strong());
                            ui.separator();
                            ui.label(
                                egui::RichText::new(format!("({})", r.facility_type))
                                    .italics()
                                    .color(egui::Color32::from_gray(170)),
                            );
                            if ui.button("Focus").clicked() {
                                let (x, y) = r.position;
                                focus_req.0 = Some(Vec3::new(
                                    x * SCALE_FACTOR,
                                    0.0,
                                    y * SCALE_FACTOR,
                                ));
                            }
                        });
                        egui::Grid::new(format!("site_grid_{}", r.id))
                            .num_columns(2)
                            .spacing([12.0, 2.0])
                            .show(ui, |ui| {
                                ui.label("Faction");
                                ui.label(&r.faction);
                                ui.end_row();
                                ui.label("Body / location");
                                ui.label(format!("{} · {}", r.body, r.location));
                                ui.end_row();
                                ui.label("Commodity");
                                ui.label(&r.commodity);
                                ui.end_row();
                                ui.label("Spawned at tick");
                                ui.label(format!("{}", r.spawned_at));
                                ui.end_row();
                            });
                        ui.add(
                            egui::ProgressBar::new(r.progress)
                                .text(format!(
                                    "{} / {} ({}% — {} left)",
                                    r.delivered,
                                    r.required,
                                    (r.progress * 100.0) as u32,
                                    r.remaining,
                                ))
                                .desired_width(f32::INFINITY),
                        );
                    });
                }
            });
        });

    state.open = open;
}

// =============================================================================
// Minimap
// =============================================================================
//
// Top-down overview of the galaxy: bodies as medium dots, ships as
// tiny dots, a crosshair at the camera focus. Bounds auto-fit to the
// body cluster each frame with a 10% margin so systems at the edge
// aren't clipped. Click anywhere on the minimap to recenter the
// orbit camera on that universe position — cheap navigation.

#[derive(Resource, Default)]
struct MinimapState {
    open: bool,
}

fn minimap_panel(
    mut ctx: EguiContexts,
    sim: Res<Sim>,
    mut state: ResMut<MinimapState>,
    camera_q: Query<&OrbitCamera>,
    mut focus_req: ResMut<CameraFocusRequest>,
) {
    use sim_core::agents::celestial_body::{BodyIdentity, BodyOrbit};
    use sim_core::agents::ship::{ShipIdentity, ShipPosition};

    let mut open = state.open;
    if !open {
        return;
    }

    // Fit to body extents; bodies are the stable anchors. Ships can
    // drift off-map (distant explorers) but the minimap is about the
    // galactic structure, not ship tracking.
    let world = &sim.store.world;
    let body_positions: Vec<(String, (f32, f32))> = world
        .query::<(&BodyIdentity, &BodyOrbit)>()
        .iter()
        .map(|(_e, (id, orbit))| (id.body_id.clone(), orbit.universe_position()))
        .collect();

    if body_positions.is_empty() {
        state.open = open;
        return;
    }

    let (mut min_x, mut max_x, mut min_y, mut max_y) = (f32::INFINITY, f32::NEG_INFINITY, f32::INFINITY, f32::NEG_INFINITY);
    for (_, (x, y)) in &body_positions {
        min_x = min_x.min(*x);
        max_x = max_x.max(*x);
        min_y = min_y.min(*y);
        max_y = max_y.max(*y);
    }
    // 10% margin so dots at the extrema don't render on the frame.
    let span_x = (max_x - min_x).max(1.0);
    let span_y = (max_y - min_y).max(1.0);
    let pad_x = span_x * 0.1;
    let pad_y = span_y * 0.1;
    min_x -= pad_x;
    max_x += pad_x;
    min_y -= pad_y;
    max_y += pad_y;

    egui::Window::new("Map")
        .anchor(egui::Align2::RIGHT_BOTTOM, egui::vec2(-12.0, -12.0))
        .default_width(260.0)
        .default_height(260.0)
        .open(&mut open)
        .show(ctx.ctx_mut(), |ui| {
            // Reserve a square plotting area; painter draws into the
            // allocated rect. 220×220 leaves room for the title bar.
            let (rect, response) = ui.allocate_exact_size(
                egui::vec2(220.0, 220.0),
                egui::Sense::click(),
            );
            let painter = ui.painter_at(rect);
            // Background panel so the minimap reads as its own surface.
            painter.rect_filled(rect, 2.0, egui::Color32::from_rgba_unmultiplied(10, 14, 22, 220));

            let to_screen = |ux: f32, uy: f32| -> egui::Pos2 {
                let nx = (ux - min_x) / (max_x - min_x);
                let ny = (uy - min_y) / (max_y - min_y);
                egui::pos2(
                    rect.left() + nx * rect.width(),
                    rect.top() + ny * rect.height(),
                )
            };

            // Ships first so bodies overlay them.
            for (_e, (_, pos)) in world.query::<(&ShipIdentity, &ShipPosition)>().iter() {
                let (x, y) = pos.position;
                if x < min_x || x > max_x || y < min_y || y > max_y {
                    continue;
                }
                painter.circle_filled(
                    to_screen(x, y),
                    1.0,
                    egui::Color32::from_rgba_unmultiplied(180, 190, 210, 180),
                );
            }

            // Bodies: bigger dots, coloured by faction-less default.
            for (_, (x, y)) in &body_positions {
                painter.circle_filled(
                    to_screen(*x, *y),
                    3.0,
                    egui::Color32::from_rgb(130, 180, 220),
                );
            }

            // Camera focus crosshair — convert world-space back to
            // universe coords by dividing out SCALE_FACTOR.
            if let Ok(orbit) = camera_q.get_single() {
                let ux = orbit.focus.x / SCALE_FACTOR;
                let uy = orbit.focus.z / SCALE_FACTOR;
                if ux >= min_x && ux <= max_x && uy >= min_y && uy <= max_y {
                    let p = to_screen(ux, uy);
                    let color = egui::Color32::from_rgb(240, 220, 120);
                    painter.line_segment(
                        [egui::pos2(p.x - 6.0, p.y), egui::pos2(p.x + 6.0, p.y)],
                        egui::Stroke::new(1.5, color),
                    );
                    painter.line_segment(
                        [egui::pos2(p.x, p.y - 6.0), egui::pos2(p.x, p.y + 6.0)],
                        egui::Stroke::new(1.5, color),
                    );
                }
            }

            // Click-to-recenter. Convert the clicked point back to
            // universe coords, then into world coords for the focus
            // request. Y-flip not needed — the map is top-down with
            // universe y mapped to screen y.
            if response.clicked() {
                if let Some(click) = response.interact_pointer_pos() {
                    let nx = ((click.x - rect.left()) / rect.width()).clamp(0.0, 1.0);
                    let ny = ((click.y - rect.top()) / rect.height()).clamp(0.0, 1.0);
                    let ux = min_x + nx * (max_x - min_x);
                    let uy = min_y + ny * (max_y - min_y);
                    focus_req.0 = Some(Vec3::new(
                        ux * SCALE_FACTOR,
                        0.0,
                        uy * SCALE_FACTOR,
                    ));
                }
            }

            ui.label(
                egui::RichText::new(
                    "click to recenter · dots: ships · larger: bodies · cross: camera",
                )
                .small()
                .color(egui::Color32::from_gray(150)),
            );
        });

    state.open = open;
}

// =============================================================================
// Body labels overlay
// =============================================================================
//
// Projects each body's world position to screen space and draws its
// name as an egui label. Helps with orientation at zoomed-out scales
// where the body meshes are just dots. Toggleable from the top bar
// so users who'd rather see a clean scene can hide them.

#[derive(Resource)]
struct BodyLabelsState {
    show: bool,
}

impl Default for BodyLabelsState {
    // Labels ON by default — first-time users benefit more from
    // orientation hints than they lose to the small visual clutter.
    fn default() -> Self {
        Self { show: true }
    }
}

fn body_labels_panel(
    mut ctx: EguiContexts,
    state: Res<BodyLabelsState>,
    sim: Res<Sim>,
    camera_q: Query<(&Camera, &GlobalTransform), With<Camera3d>>,
) {
    use sim_core::agents::celestial_body::{BodyIdentity, BodyOrbit};

    if !state.show {
        return;
    }

    let Ok((camera, cam_xf)) = camera_q.get_single() else { return };

    let world = &sim.store.world;
    let entries: Vec<(String, Vec3)> = world
        .query::<(&BodyIdentity, &BodyOrbit)>()
        .iter()
        .map(|(_e, (id, orbit))| {
            let (x, y) = orbit.universe_position();
            (
                id.name.clone(),
                Vec3::new(x * SCALE_FACTOR, 0.0, y * SCALE_FACTOR),
            )
        })
        .collect();

    // Use a transparent, non-interactive overlay area so labels
    // paint on top without eating clicks or blocking egui's
    // tooltip logic.
    let ctx = ctx.ctx_mut();
    egui::Area::new(egui::Id::new("body_labels_area"))
        .movable(false)
        .interactable(false)
        .anchor(egui::Align2::LEFT_TOP, egui::vec2(0.0, 0.0))
        .show(ctx, |ui| {
            let painter = ui.painter();
            for (name, pos) in entries {
                // Skip bodies behind the camera. viewport_to_world's
                // dual `world_to_viewport` returns None for off-screen
                // or behind-camera — treat that as "don't draw".
                let Some(screen) = camera.world_to_viewport(cam_xf, pos) else {
                    continue;
                };
                // Offset label a bit above the body so it doesn't
                // occlude the sphere.
                let anchor = egui::pos2(screen.x, screen.y - 12.0);
                painter.text(
                    anchor,
                    egui::Align2::CENTER_BOTTOM,
                    &name,
                    egui::FontId::proportional(11.0),
                    egui::Color32::from_rgba_unmultiplied(230, 235, 245, 200),
                );
            }
        });
}
