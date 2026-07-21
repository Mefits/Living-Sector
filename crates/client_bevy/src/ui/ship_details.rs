//! Ship details panel — full-component inspector for the selected ship.
//!
//! The "inspector as live debugger" payoff of the embedded arch.
//! Reads every ship component directly out of hecs (no snapshot
//! marshalling) and renders one section per component: identity,
//! position, economy, fuel, cargo, crew, AI, progression, fitting.
//! Opens when [`SelectedShip`] becomes Some; closes itself when the
//! user clears selection (X button → `selected.0 = None`).
//!
//! Admin toolbar at the top:
//!   * **Focus camera** — writes [`CameraFocusRequest`] so the orbit
//!     cam re-centres on this ship's universe position.
//!   * **+100 XP** — direct hecs `&mut` write into `ShipProgression`,
//!     bypasses `SimCommand`. Demonstrates the embedded-arch admin
//!     pattern: no HTTP, no JSON, just mutate the component.
//!   * **Heal** — refills fuel, resets crew morale/health to 100,
//!     clears hunger/fatigue, floors credits at 10k. Unsticks broke
//!     spiralling ships.
//!   * **Delete** — destroys the ship: removes from every facility's
//!     docked + queue lists, releases held contracts, despawns the
//!     hecs entity, drops the id mapping. Mirrors the admin cascade
//!     in `sim_server::engine::admin_remove_ship`.
//!
//! Refit combos: each fitting slot is a `ComboBox` of compatible
//! module slugs. Selecting a different slug fires
//! `sim_server::engine::admin_refit_ship` with `via_shipyard=false`
//! (admin override — no cost, no shipyard stock decrement). Derived
//! stats refresh same frame because the apply mutates the component
//! before the next render pass.
//!
//! Borrow rules: every admin action flips a local bool inside the
//! egui closure (read-only world borrow), then the system runs the
//! mutating apply *after* the closure ends. hecs forbids concurrent
//! read + write on the same world.
//!
//! Extracted from `ui/mod.rs` in the Phase-21 god-module split.

use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};

use super::ship_list::SelectedShip;
use super::{format::format_credits, theme};
use crate::camera::CameraFocusRequest;
use crate::render::SCALE_FACTOR;
use crate::sim::Sim;

#[allow(clippy::too_many_arguments)]
#[allow(clippy::type_complexity)]
pub(super) fn ship_details_panel(
    mut ctx: EguiContexts,
    mut sim: ResMut<Sim>,
    mut selected: ResMut<SelectedShip>,
    mut focus_req: ResMut<CameraFocusRequest>,
    // Bevy 0.18 schedule rejects systems whose params hold both `&T`
    // and `&mut T` for the same component (Query<&Foo> + Query<&mut Foo>
    // even on different entities). Workaround: every component this
    // panel mutates lives only in its `*_mut_q` Query; we read it back
    // via that Query's `.get(entity)` (which yields `&T`). Components
    // we never mutate stay in the read-only base_q / extra_q tuples.
    base_q: Query<(
        &sim_core::agents::ship::ShipIdentity,
        &sim_core::agents::ship::ShipPosition,
        &sim_core::agents::ship::ShipTransit,
        &sim_core::agents::ship::ShipCargo,
        &sim_core::agents::ship::ShipAI,
    )>,
    extra_q: Query<(
        &sim_core::agents::ship::ShipCrewSkills,
        &sim_core::agents::ship::ShipFitting,
        &sim_core::agents::ship::ShipLifecycle,
    )>,
    mut prog_mut_q: Query<&mut sim_core::agents::ship::ShipProgression>,
    mut fuel_mut_q: Query<&mut sim_core::agents::ship::ShipFuel>,
    mut crew_mut_q: Query<&mut sim_core::agents::ship::ShipCrew>,
    mut econ_mut_q: Query<&mut sim_core::agents::ship::ShipEconomy>,
    mut storage_mut_q: Query<&mut sim_core::agents::facility::FacilityStorage>,
    mut commands: Commands,
) {
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
    let mut heal_requested = false;
    // Refit request: (slot, slug) pair captured from the Fitting
    // dropdowns. None=keep current, Some((slot, slug)) = swap.
    let mut refit_request: Option<(sim_core::modules::Slot, &'static str)> = None;
    let title = format!("Ship · {}", ship_id);

    egui::Window::new(title)
        .default_width(520.0)
        .default_height(640.0)
        .open(&mut still_open)
        .show(ctx.ctx_mut().unwrap(), |ui| {
            let Ok((id, pos, transit, cargo, ai)) = base_q.get(entity) else {
                ui.label("(ship entity missing components)");
                return;
            };
            let Ok((skills, fit, life)) = extra_q.get(entity) else {
                ui.label("(ship entity missing components)");
                return;
            };
            // Read the conflicted components through their mut query.
            // Query<&mut T>::get yields `&T` so this is a borrow-safe
            // read; only later admin handlers reach for `.get_mut`.
            let Ok(fuel) = fuel_mut_q.get(entity) else {
                ui.label("(ship entity missing components)");
                return;
            };
            let Ok(econ) = econ_mut_q.get(entity) else {
                ui.label("(ship entity missing components)");
                return;
            };
            let Ok(crew) = crew_mut_q.get(entity) else {
                ui.label("(ship entity missing components)");
                return;
            };
            let Ok(prog) = prog_mut_q.get(entity) else {
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
                ui.label(egui::RichText::new("admin:").small().color(theme::TEXT_DIM));
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
                    .button(egui::RichText::new("Heal").small().color(theme::SUCCESS))
                    .on_hover_text(
                        "Refill fuel to capacity, reset crew morale+health to \
                         100, clear hunger + fatigue, and floor credits at 10k \
                         so the ship can afford docks. Unsticks broke / \
                         spiralling ships for debugging.",
                    )
                    .clicked()
                {
                    heal_requested = true;
                }
                if ui
                    .button(egui::RichText::new("Delete").small().color(theme::DANGER))
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
                ui.label(theme::section_header("Identity"));
                egui::Grid::new("details_identity")
                    .num_columns(2)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        ui.label("Name");
                        ui.label(&id.name);
                        ui.end_row();
                        ui.label("Class");
                        ui.label(&id.class);
                        ui.end_row();
                        ui.label("Size");
                        ui.label(format!("{:?}", id.size));
                        ui.end_row();
                        ui.label("Faction");
                        ui.label(&id.faction_id);
                        ui.end_row();
                    });
                ui.separator();

                // Position / transit
                ui.label(theme::section_header("Position"));
                egui::Grid::new("details_pos")
                    .num_columns(2)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        ui.label("System");
                        ui.label(&pos.system_id);
                        ui.end_row();
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
                            ui.label(format!("{} → {} ({:.1}%)", t.from, t.to, progress,));
                            ui.end_row();
                            ui.label("Arrival tick");
                            ui.label(format!("{}", t.arrival_tick));
                            ui.end_row();
                        }
                    });
                ui.separator();

                // Economy
                ui.label(theme::section_header("Economy"));
                egui::Grid::new("details_econ")
                    .num_columns(2)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        ui.label("Credits");
                        ui.label(format_credits(econ.credits));
                        ui.end_row();
                        ui.label("Efficiency");
                        ui.label(format!("{:.2}", econ.efficiency));
                        ui.end_row();
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
                ui.label(theme::section_header("Fuel"));
                egui::Grid::new("details_fuel")
                    .num_columns(2)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        let frac = fuel.fraction();
                        let frac_color = theme::status_color(frac, (0.5, 0.2));
                        ui.label(theme::caption("Fuel"));
                        ui.colored_label(
                            frac_color,
                            egui::RichText::new(format!(
                                "{:.1} / {:.0} ({:.0}%)",
                                fuel.fuel,
                                fuel.fuel_capacity,
                                frac * 100.0
                            ))
                            .monospace(),
                        );
                        ui.end_row();
                        ui.label(theme::caption("Speed mod"));
                        ui.label(
                            egui::RichText::new(format!("{:.2}×", fuel.speed_modifier)).monospace(),
                        );
                        ui.end_row();
                        ui.label(theme::caption("Burn rate"));
                        ui.label(
                            egui::RichText::new(format!("{:.3}", fuel.fuel_consumption_rate))
                                .monospace(),
                        );
                        ui.end_row();
                    });
                ui.separator();

                // Cargo
                ui.label(theme::section_header("Cargo"));
                let used = cargo.used();
                ui.label(format!(
                    "Hold: {} / {} ({:.0}%)",
                    used,
                    cargo.capacity,
                    if cargo.capacity > 0 {
                        used as f32 / cargo.capacity as f32 * 100.0
                    } else {
                        0.0
                    }
                ));
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
                ui.label(theme::section_header("Crew"));
                egui::Grid::new("details_crew")
                    .num_columns(2)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        ui.label("Size");
                        ui.label(format!("{}", crew.size));
                        ui.end_row();
                        ui.label("Task");
                        ui.label(crew.current_task.as_str());
                        ui.end_row();
                        ui.label("Morale");
                        ui.colored_label(
                            theme::crew_bar_color(crew.morale),
                            format!("{:.0}", crew.morale),
                        );
                        ui.end_row();
                        ui.label("Hunger");
                        ui.colored_label(
                            // Inverse scale — hunger high = bad.
                            theme::crew_bar_color(100.0 - crew.hunger),
                            format!("{:.0}", crew.hunger),
                        );
                        ui.end_row();
                        ui.label("Fatigue");
                        ui.colored_label(
                            theme::crew_bar_color(100.0 - crew.fatigue),
                            format!("{:.0}", crew.fatigue),
                        );
                        ui.end_row();
                        ui.label("Health");
                        ui.label(format!("{:.0}", crew.health));
                        ui.end_row();
                        ui.label("Wages owed");
                        ui.label(format!("{}", crew.wages_credits));
                        ui.end_row();
                        ui.label("Skills");
                        ui.label(format!(
                            "nav {}  eng {}  trd {}  cmb {}",
                            skills.navigation, skills.engineering, skills.trading, skills.combat,
                        ));
                        ui.end_row();
                    });
                ui.separator();

                // AI
                ui.label(theme::section_header("AI"));
                egui::Grid::new("details_ai")
                    .num_columns(2)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        ui.label("Goal");
                        ui.label(&ai.current_goal);
                        ui.end_row();
                        ui.label("Goal score");
                        ui.label(format!("{:.2}", ai.current_goal_score));
                        ui.end_row();
                        ui.label("Planned at tick");
                        ui.label(format!("{}", ai.last_plan_tick));
                        ui.end_row();
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
                ui.label(theme::section_header("Progression"));
                egui::Grid::new("details_prog")
                    .num_columns(2)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        ui.label("Level");
                        ui.label(format!(
                            "{} / {}",
                            prog.level,
                            sim_core::agents::ship::SHIP_LEVEL_CAP
                        ));
                        ui.end_row();
                        ui.label("XP");
                        ui.label(format!("{} / {}", prog.xp, prog.next_level_threshold()));
                        ui.end_row();
                        ui.label("Retrofit points");
                        ui.label(format!("{}", prog.retrofit_points));
                        ui.end_row();
                        ui.label("Idle ticks");
                        ui.label(format!("{}", life.idle_ticks));
                        ui.end_row();
                        ui.label("Broke / hoard strikes");
                        ui.label(format!("{} / {}", life.broke_strikes, life.hoard_strikes));
                        ui.end_row();
                    });
                ui.separator();

                // Fitting — interactive: each slot row is a combo
                // of compatible module slugs. Selecting a different
                // slug fires an admin-override refit (no cost / no
                // shipyard stock check) via sim_server::engine::
                // admin_refit_ship after the read-query drops. Empty
                // slot still shows "—" but we don't expose unset as
                // a choice to reduce footguns.
                ui.label(theme::section_header("Fitting"));
                egui::Grid::new("details_fit")
                    .num_columns(2)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        for (slot_idx, slot) in sim_core::modules::SLOTS.iter().enumerate() {
                            ui.label(slot.as_str());
                            let current = fit.slots[slot_idx];
                            let current_label = current.unwrap_or("—");
                            egui::ComboBox::from_id_salt(format!("refit_combo_{}", slot.as_str()))
                                .selected_text(current_label)
                                .show_ui(ui, |ui| {
                                    for module in sim_core::modules::modules_for_slot(*slot) {
                                        let label = format!("{} (T{})", module.slug, module.tier);
                                        if ui
                                            .selectable_label(current == Some(module.slug), label)
                                            .clicked()
                                            && current != Some(module.slug)
                                        {
                                            refit_request = Some((*slot, module.slug));
                                        }
                                    }
                                });
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
        if let Ok(mut prog) = prog_mut_q.get_mut(entity) {
            let levels = prog.grant_xp(100);
            info!(
                "client_bevy admin: +100 XP to {} ({}level+{})",
                ship_id,
                if levels > 0 { "leveled up! " } else { "" },
                prog.retrofit_points,
            );
        }
    }

    if let Some((slot, slug)) = refit_request {
        // via_shipyard=false → admin override path: no cost, no
        // shipyard stock decrement. Matches the HTTP admin/refit
        // endpoint behaviour for the no-cost form.
        //
        // Phase B: admin_refit_ship now takes (&mut World, &mut
        // AgentStore, ...). The Bevy app World holds the sim
        // entities; we can't access it through Res<Sim> + Query
        // params, so the refit path is queued through Commands as
        // a deferred World mutation that the next stage of the
        // schedule applies.
        let ship_id_for_cmd = ship_id.clone();
        commands.queue(move |world: &mut World| {
            if let Some(mut sim) = world.remove_resource::<Sim>() {
                let mut events: Vec<serde_json::Value> = Vec::new();
                sim_server::engine::admin_refit_ship(
                    world,
                    &mut sim.store,
                    &ship_id_for_cmd,
                    slot,
                    Some(slug),
                    false,
                    &mut events,
                );
                world.insert_resource(sim);
                info!(
                    "client_bevy admin: refit (deferred) {} → {}",
                    slot.as_str(),
                    slug,
                );
            }
        });
    }

    if heal_requested {
        // Drop borrows one at a time — Bevy queries enforce one
        // mutable borrow per component per scope. Each `if let`
        // block ends the borrow on its component before the next
        // begins.
        if let Ok(mut fuel) = fuel_mut_q.get_mut(entity) {
            fuel.fuel = fuel.fuel_capacity;
        }
        if let Ok(mut crew) = crew_mut_q.get_mut(entity) {
            crew.morale = 100.0;
            crew.health = 100.0;
            crew.hunger = 0.0;
            crew.fatigue = 0.0;
        }
        if let Ok(mut econ) = econ_mut_q.get_mut(entity) {
            // Floor — don't zap a millionaire ship back to 10k. Just
            // make sure a stranded ship has dock money.
            if econ.credits < 10_000 {
                econ.credits = 10_000;
            }
        }
        info!("client_bevy admin: healed {}", ship_id);
    }

    if delete_requested {
        // Step 1: yank the ship entity out of any docked list + dock
        // queue. If we skip this the entry wedges behind a despawned
        // entity and blocks live ships behind it. Mirrors the admin
        // cascade in sim_server::engine::admin_remove_ship.
        for mut storage in storage_mut_q.iter_mut() {
            storage.docked_ships.retain(|&e| e != entity);
            storage.dock_queue.retain(|&e| e != entity);
        }
        // Step 2: release any contracts tied to this ship. Accepted
        // → Posted (re-postable); PickedUp → Expired (cargo lost with
        // the ship). `drop` is ignored here because the client
        // doesn't broadcast events the way sim_server does.
        let _ = sim.store.contracts.drop_ship_holdings(&ship_id);
        // Step 3: actually despawn + forget the id mapping. We use
        // Commands to defer the despawn since Bevy's borrow rules
        // forbid grabbing &mut World while query params are live.
        sim.store.ship_by_id.remove(&ship_id);
        commands.entity(entity).despawn();
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
