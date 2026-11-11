//! Contracts panel — full board across all 6 kinds × 6 statuses.
//!
//! Reads `sim.store.contracts` (the `ContractBoard`) once per frame,
//! filters by kind / status / show-expired toggle, paginates at 400
//! rows, renders a grid. Faction tag + min-reputation gate columns
//! make rep-gating visible — important since the planner's
//! `posted_for_ship` filter hinges on it.
//!
//! State: [`ContractsState`] — open flag, kind filter, status filter,
//! show-expired toggle. Auto-open via `CLIENT_BEVY_OPEN_PANELS=
//! contracts|all`.
//!
//! Headers split Source / Dest into separate columns instead of using
//! "Source → Dest"; the egui default font has no glyph for "→" and
//! it renders as a tofu box.
//!
//! Status column maps onto the theme palette:
//!   * posted → PRIMARY (info)
//!   * accepted / picked_up → WARN (in-flight)
//!   * delivered / paid → SUCCESS
//!   * expired → DANGER
//!
//! Extracted from `ui/mod.rs` in the Phase-21 god-module split.

use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};

use super::{format::format_credits, theme};
use crate::sim::Sim;

#[derive(Resource)]
pub(super) struct ContractsState {
    pub open: bool,
    kind_filter: ContractKindFilter,
    status_filter: ContractStatusFilter,
    show_expired: bool,
}

impl Default for ContractsState {
    fn default() -> Self {
        let auto_open = std::env::var("CLIENT_BEVY_OPEN_PANELS")
            .map(|s| s.contains("contracts") || s == "all")
            .unwrap_or(false);
        Self {
            open: auto_open,
            kind_filter: ContractKindFilter::default(),
            status_filter: ContractStatusFilter::default(),
            show_expired: false,
        }
    }
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

pub(super) fn contracts_panel(
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
        .id(egui::Id::new("contracts_window"))
        .default_width(820.0)
        .default_height(440.0)
        .open(&mut open)
        .show(ctx.ctx_mut().unwrap(), |ui| {
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
                    .num_columns(10)
                    .spacing([10.0, 3.0])
                    .show(ui, |ui| {
                        // Headers — Source / Dest are separate columns
                        // so the egui default font's missing "→" glyph
                        // (rendered as a tofu box) doesn't show up.
                        for header in [
                            "Kind", "Status", "Item", "Qty", "Source", "Dest", "Pay", "Faction",
                            "Rep", "ID",
                        ] {
                            ui.label(egui::RichText::new(header).strong().color(theme::TEXT_DIM));
                        }
                        ui.end_row();

                        for r in &page_rows {
                            ui.label(r.kind);
                            ui.colored_label(contract_status_color(r.status), r.status);
                            ui.label(egui::RichText::new(&r.commodity).color(theme::TEXT_DIM));
                            ui.label(egui::RichText::new(format!("{}", r.quantity)).monospace());
                            // Source dimmed; destination is what the
                            // eye usually wants on this row.
                            ui.label(egui::RichText::new(&r.source).color(theme::TEXT_DIM));
                            ui.label(&r.dest);
                            // Pay in monospace, abbreviated (1.2k / 3.4M)
                            ui.label(egui::RichText::new(format_credits(r.payment)).monospace());
                            ui.label(egui::RichText::new(&r.faction).color(theme::TEXT_DIM));
                            // Rep gate: PRIMARY when set, dim em-dash
                            // when unrestricted (public board).
                            if r.min_rep > 0 {
                                ui.colored_label(theme::PRIMARY, format!("{}", r.min_rep));
                            } else {
                                ui.label(egui::RichText::new("-").color(theme::TEXT_DIM));
                            }
                            ui.label(
                                egui::RichText::new(&r.id)
                                    .small()
                                    .monospace()
                                    .color(theme::TEXT_DIM),
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
                    .color(theme::TEXT_DIM),
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

/// Map a contract status string to a theme palette colour. Posted
/// = PRIMARY (info), in-flight (accepted/picked_up) = WARN, terminal
/// success (delivered/paid) = SUCCESS, terminal failure (expired) =
/// DANGER. Renamed from `status_color` to avoid colliding with
/// `theme::status_color`, which is the threshold-based helper.
fn contract_status_color(s: &'static str) -> egui::Color32 {
    match s {
        "posted" => theme::PRIMARY,
        "accepted" | "picked_up" => theme::WARN,
        "delivered" | "paid" => theme::SUCCESS,
        "expired" => theme::DANGER,
        _ => theme::TEXT,
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
