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

use crate::sim::Sim;

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
                )
                    .chain(),
            );
    }
}

/// Single top-bar system. Reads counts from the sim, hands out
/// open/close toggles to each panel's state Resource. Runs first
/// in the UI chain so the panels below see up-to-date `open`
/// flags the same frame the user clicks.
fn top_bar(
    mut ctx: EguiContexts,
    sim: Res<Sim>,
    mut ships: ResMut<ShipListState>,
    mut contracts: ResMut<ContractsState>,
    mut factions: ResMut<FactionsState>,
    mut markets: ResMut<MarketsState>,
    mut pops: ResMut<PopulationsState>,
) {
    egui::TopBottomPanel::top("top_bar").show(ctx.ctx_mut(), |ui| {
        ui.horizontal(|ui| {
            ui.label(egui::RichText::new("spaceproject").strong());
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

fn ship_list(
    mut ctx: EguiContexts,
    sim: Res<Sim>,
    mut state: ResMut<ShipListState>,
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
                            ui.label(&row.name);
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
