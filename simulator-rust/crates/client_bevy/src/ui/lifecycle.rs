//! AppState lifecycle UI — main menu + new-universe modal + save list.
//!
//! All three render only when `AppState::MainMenu` is active. They
//! share file-system helpers (find the binary directory, sanitise
//! universe names, scan `*.db` snapshots) and a credits/version
//! footer reused by the pause menu, so co-location keeps the chain
//! visible in one file.
//!
//! ## [`main_menu_panel`]
//!
//! Title screen rendered in front of the live 3D backdrop. Foreground
//! Area ordering keeps buttons above the starfield + nebulae;
//! suppressed when any child modal is open so button text doesn't
//! bleed through. Buttons:
//!   * **Start** — opens [`new_universe_dialog`] to pick a fresh
//!     universe name, then transitions to InGame.
//!   * **Load Game** — opens [`save_list_panel`] for the saves
//!     browser.
//!   * **Options** — same OptionsState window the pause menu uses.
//!   * **Quit** — `AppExit::Success`.
//!
//! ## [`new_universe_dialog`]
//!
//! After Start the user types a universe name. Sanitised to
//! `[A-Za-z0-9_-]{0,48}` ([`sanitize_universe_name`]); empty input
//! falls back to `sim`. If a `<name>.db` already exists the resolver
//! picks `<name>-2`, `<name>-3`, … so Start always means "fresh
//! world" — never silently overwrite or resume an existing save.
//! Resume goes through Load Game.
//!
//! Sets `crate::sim::SelectedSavePath` so `OnEnter(InGame)` opens the
//! right DB. Esc and Cancel back out of the dialog.
//!
//! ## [`save_list_panel`]
//!
//! Lists every `*.db` next to the binary (or in cwd in dev). The
//! active `sim.db` pins to the top with a "Current session" badge.
//! Both Load and Delete are enabled for any save — deleting `sim.db`
//! from the menu is safe because no pool is held in MainMenu state;
//! the next Start re-seeds. Sidecar WAL/SHM/journal files get
//! cleaned up alongside the main DB on delete.
//!
//! Date display is computed via a tiny [`days_to_ymd`] helper
//! (proleptic Gregorian, naive UTC) instead of pulling in chrono for
//! one footer line.
//!
//! Extracted from `ui/mod.rs` in the Phase-21 god-module split.

use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};

use super::menus::OptionsState;
use super::theme;
use crate::sim::Sim;

#[derive(Resource)]
pub(super) struct NewUniverseDialogState {
    pub open: bool,
    name: String,
    /// One-shot flag set when the dialog opens so we can grab the
    /// text-field focus on the first frame it renders. Cleared after
    /// the focus call lands.
    focus_pending: bool,
}

impl Default for NewUniverseDialogState {
    fn default() -> Self {
        Self {
            open: false,
            name: "sim".to_string(),
            focus_pending: false,
        }
    }
}

#[derive(Resource, Default)]
pub(super) struct SaveListState {
    pub open: bool,
    saves: Vec<SaveEntry>,
    /// `None` forces a re-scan on next render; otherwise we cache
    /// the listing so opening the panel doesn't hit the FS every
    /// frame. Refresh button bumps this back to None.
    last_scan: Option<std::time::Instant>,
}

#[derive(Clone)]
struct SaveEntry {
    path: std::path::PathBuf,
    name: String,
    modified_iso: String,
    size_kb: u64,
    /// True for the active `sim.db`. Renders with a "Current
    /// session" badge and disables the Delete button.
    is_active: bool,
}

pub(super) fn main_menu_panel(
    mut ctx: EguiContexts,
    mut new_universe: ResMut<NewUniverseDialogState>,
    mut options: ResMut<OptionsState>,
    mut saves: ResMut<SaveListState>,
    mut exit: MessageWriter<AppExit>,
) {
    // Suppress the menu while any modal is up. Menu used Foreground
    // ordering so its buttons stayed visible above the 3D backdrop
    // — but Foreground also paints OVER egui Windows, which made
    // the button text bleed through Saves / Options / new-universe
    // modals. Cleanest fix: just don't draw the menu while a modal
    // is open.
    if new_universe.open || options.open || saves.open {
        return;
    }
    egui::Area::new(egui::Id::new("main_menu"))
        .anchor(egui::Align2::CENTER_CENTER, egui::vec2(0.0, 0.0))
        .order(egui::Order::Foreground)
        .show(ctx.ctx_mut().unwrap(), |ui| {
            ui.vertical_centered(|ui| {
                ui.add_space(8.0);
                ui.label(
                    egui::RichText::new("The Space Project")
                        .size(32.0)
                        .strong()
                        .color(theme::PRIMARY),
                );
                ui.add_space(28.0);

                let btn_size = egui::vec2(260.0, 40.0);
                if ui
                    .add_sized(
                        btn_size,
                        egui::Button::new(
                            egui::RichText::new("Start")
                                .size(16.0)
                                .color(theme::PRIMARY),
                        ),
                    )
                    .clicked()
                {
                    new_universe.open = true;
                    new_universe.name = "sim".to_string();
                    new_universe.focus_pending = true;
                }
                ui.add_space(4.0);
                if ui
                    .add_sized(btn_size, egui::Button::new("Load Game"))
                    .on_hover_text("Browse the saves stored next to the binary.")
                    .clicked()
                {
                    saves.open = true;
                    saves.last_scan = None; // force refresh on open
                }
                ui.add_space(4.0);
                if ui
                    .add_sized(btn_size, egui::Button::new("Options"))
                    .clicked()
                {
                    options.open = true;
                }
                ui.add_space(4.0);
                if ui
                    .add_sized(
                        btn_size,
                        egui::Button::new(egui::RichText::new("Quit").color(theme::DANGER)),
                    )
                    .clicked()
                {
                    exit.write(AppExit::Success);
                }
                ui.add_space(20.0);
                credits_block(ui);
                ui.add_space(8.0);
            });
        });
}

/// Shared credit + version footer rendered on both the main menu
/// and the pause menu. CARGO_PKG_VERSION is the workspace version
/// from `Cargo.toml`; the Makefile reads the same field so packaged
/// builds (Info.plist, butler --userversion, archive names) line
/// up with what's shown in-game.
pub(super) fn credits_block(ui: &mut egui::Ui) {
    ui.label(
        egui::RichText::new(format!("v{}", env!("CARGO_PKG_VERSION")))
            .small()
            .monospace()
            .color(theme::TEXT_DIM),
    );
    ui.add_space(2.0);
    ui.label(
        egui::RichText::new("By Kalcode & Claude")
            .small()
            .color(theme::TEXT_DIM),
    );
    ui.label(
        egui::RichText::new("Made with ❤️ in Illinois")
            .small()
            .color(theme::TEXT_DIM),
    );
}

/// Strip everything that isn't `[A-Za-z0-9_-]` and clamp length so
/// the resulting `.db` path can't break out of its parent directory
/// or trip filesystem rules. Empty input → "sim" as the fallback.
fn sanitize_universe_name(raw: &str) -> String {
    let cleaned: String = raw
        .trim()
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || *c == '_' || *c == '-')
        .take(48)
        .collect();
    if cleaned.is_empty() {
        "sim".to_string()
    } else {
        cleaned
    }
}

/// Directory where save DBs live (next to the running binary —
/// matches `scan_saves()` / `process_save_as()`). Falls back to the
/// current working directory if `current_exe` can't resolve, which
/// is the same fallback `resolve_db_path` uses for the default DB.
fn save_dir() -> std::path::PathBuf {
    std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|d| d.to_path_buf()))
        .unwrap_or_else(|| std::path::PathBuf::from("."))
}

/// Pick a free filename for a fresh universe — avoids clobbering
/// existing saves when the user hits Start with a name that already
/// has a `.db` on disk. Returns `(final_stem, path)`. If the base
/// name is free, returns it as-is. Otherwise appends `-2`, `-3`, …
/// up to a sanity cap.
fn unique_universe_path(stem: &str) -> (String, std::path::PathBuf) {
    let dir = save_dir();
    let base_path = dir.join(format!("{stem}.db"));
    if !base_path.exists() {
        return (stem.to_string(), base_path);
    }
    for n in 2..=999 {
        let candidate_stem = format!("{stem}-{n}");
        let candidate = dir.join(format!("{candidate_stem}.db"));
        if !candidate.exists() {
            return (candidate_stem, candidate);
        }
    }
    // Pathological case — 999 worlds with the same base name. Fall
    // back to a wall-clock suffix so we still produce a unique
    // path instead of clobbering.
    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let suffix_stem = format!("{stem}-{ts}");
    let path = dir.join(format!("{suffix_stem}.db"));
    (suffix_stem, path)
}

pub(super) fn new_universe_dialog(
    mut ctx: EguiContexts,
    mut state: ResMut<NewUniverseDialogState>,
    mut next_state: ResMut<NextState<crate::AppState>>,
    mut sim: ResMut<Sim>,
    mut selected_save: ResMut<crate::sim::SelectedSavePath>,
) {
    if !state.open {
        return;
    }

    let mut want_start = false;
    let mut want_cancel = false;

    egui::Window::new("Name your universe")
        .id(egui::Id::new("new_universe_dialog"))
        .anchor(egui::Align2::CENTER_CENTER, egui::vec2(0.0, 0.0))
        .collapsible(false)
        .resizable(false)
        .default_width(380.0)
        .show(ctx.ctx_mut().unwrap(), |ui| {
            ui.add_space(4.0);
            ui.label(
                egui::RichText::new(
                    "Pick a name for this universe. The simulation \
                     persists to a SQLite file with this name. Letters, \
                     digits, dashes and underscores only.",
                )
                .small()
                .color(theme::TEXT_DIM),
            );
            ui.add_space(8.0);

            let resp = ui.add(
                egui::TextEdit::singleline(&mut state.name)
                    .hint_text("sim")
                    .desired_width(f32::INFINITY),
            );
            if state.focus_pending {
                resp.request_focus();
                state.focus_pending = false;
            }
            // Enter inside the text field commits.
            if resp.lost_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter)) {
                want_start = true;
            }

            let sanitized = sanitize_universe_name(&state.name);
            let (resolved_stem, _) = unique_universe_path(&sanitized);
            let collided = resolved_stem != sanitized;
            ui.add_space(2.0);
            ui.horizontal(|ui| {
                ui.label(egui::RichText::new("File:").small().color(theme::TEXT_DIM));
                ui.label(
                    egui::RichText::new(format!("{resolved_stem}.db"))
                        .small()
                        .monospace()
                        .color(theme::PRIMARY),
                );
            });
            if collided {
                // Existing save with the picked stem — explain why
                // we're appending a suffix so the user isn't
                // surprised that the filename doesn't match what
                // they typed. They can either accept the new name
                // or hit Cancel and use Load Game on the existing
                // save instead.
                ui.label(
                    egui::RichText::new(format!(
                        "⚠ '{sanitized}.db' already exists — \
                         starting as '{resolved_stem}.db'. Use Load \
                         Game to resume the existing save."
                    ))
                    .small()
                    .color(theme::WARN),
                );
            }

            ui.add_space(10.0);
            ui.horizontal(|ui| {
                if ui
                    .add(egui::Button::new(
                        egui::RichText::new("Start").color(theme::PRIMARY),
                    ))
                    .clicked()
                {
                    want_start = true;
                }
                if ui.button("Cancel").clicked() {
                    want_cancel = true;
                }
            });
            // Esc cancels.
            if ui.input(|i| i.key_pressed(egui::Key::Escape)) {
                want_cancel = true;
            }
        });

    if want_cancel {
        state.open = false;
        return;
    }

    if want_start {
        let sanitized = sanitize_universe_name(&state.name);
        // Resolve to a non-colliding path so Start always means
        // "fresh world" — never silently overwrite or resume an
        // existing save. Resume goes through Load Game instead.
        let (final_stem, path) = unique_universe_path(&sanitized);
        info!(
            "client_bevy: starting universe '{}' → {}",
            final_stem,
            path.display(),
        );
        selected_save.0 = Some(path);
        sim.running = true;
        next_state.set(crate::AppState::InGame);
        state.open = false;
    }
}

fn scan_saves() -> Vec<SaveEntry> {
    let dir = save_dir();
    let mut out: Vec<SaveEntry> = Vec::new();
    let Ok(rd) = std::fs::read_dir(&dir) else {
        return out;
    };
    for entry in rd.flatten() {
        let path = entry.path();
        let name = match path.file_name().and_then(|n| n.to_str()) {
            Some(n) => n.to_string(),
            None => continue,
        };
        if !name.ends_with(".db") {
            continue;
        }
        let is_active = name == "sim.db";
        let meta = match entry.metadata() {
            Ok(m) => m,
            Err(_) => continue,
        };
        let size_kb = meta.len() / 1024;
        let modified_iso = meta
            .modified()
            .ok()
            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
            .map(|d| {
                let secs = d.as_secs() as i64;
                // Compact YYYY-MM-DD HH:MM via chrono-free math.
                let days = secs / 86_400;
                let h = (secs % 86_400) / 3600;
                let m = (secs % 3600) / 60;
                // Naive UTC; plenty for a filesystem timestamp display.
                let (y, mo, d) = days_to_ymd(days);
                format!("{y:04}-{mo:02}-{d:02} {h:02}:{m:02}")
            })
            .unwrap_or_else(|| "?".to_string());
        out.push(SaveEntry {
            path,
            name,
            modified_iso,
            size_kb,
            is_active,
        });
    }
    // Active session always pinned to the top, then snapshots
    // newest-first.
    out.sort_by(|a, b| {
        b.is_active
            .cmp(&a.is_active)
            .then_with(|| b.modified_iso.cmp(&a.modified_iso))
    });
    out
}

/// Convert days-since-1970-01-01 to (year, month, day). Naive
/// proleptic Gregorian — the chrono crate would be cleaner but
/// adding a dep for one display string is overkill.
fn days_to_ymd(mut days: i64) -> (i32, u32, u32) {
    let mut y: i32 = 1970;
    loop {
        let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
        let yd: i64 = if leap { 366 } else { 365 };
        if days < yd {
            break;
        }
        days -= yd;
        y += 1;
    }
    let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
    let mdays: [i64; 12] = [
        31,
        if leap { 29 } else { 28 },
        31,
        30,
        31,
        30,
        31,
        31,
        30,
        31,
        30,
        31,
    ];
    let mut m: usize = 0;
    while m < 12 && days >= mdays[m] {
        days -= mdays[m];
        m += 1;
    }
    (y, (m + 1) as u32, (days + 1) as u32)
}

pub(super) fn save_list_panel(
    mut ctx: EguiContexts,
    mut state: ResMut<SaveListState>,
    mut selected_save: ResMut<crate::sim::SelectedSavePath>,
    mut next_state: ResMut<NextState<crate::AppState>>,
    mut sim: ResMut<Sim>,
) {
    if !state.open {
        return;
    }

    // Scan once per open (or after Refresh). FS dirs change rarely
    // during play so caching is fine; the user can hit Refresh to
    // re-scan after a Save-As.
    if state.last_scan.is_none() {
        state.saves = scan_saves();
        state.last_scan = Some(std::time::Instant::now());
    }

    let mut open = state.open;
    let mut want_refresh = false;
    let mut want_delete: Option<std::path::PathBuf> = None;
    let mut want_load: Option<std::path::PathBuf> = None;

    egui::Window::new("Saves")
        .id(egui::Id::new("save_list_window"))
        .anchor(egui::Align2::CENTER_CENTER, egui::vec2(0.0, 0.0))
        .collapsible(false)
        .resizable(false)
        .default_width(540.0)
        .open(&mut open)
        .show(ctx.ctx_mut().unwrap(), |ui| {
            ui.horizontal(|ui| {
                ui.label(theme::section_header("Save snapshots"));
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    if ui.small_button("Refresh").clicked() {
                        want_refresh = true;
                    }
                });
            });
            ui.separator();
            if state.saves.is_empty() {
                ui.label(
                    egui::RichText::new(
                        "No save files found next to the binary. \
                         Start a new game to create one, or use Save As… \
                         from the pause menu to take a snapshot.",
                    )
                    .italics()
                    .color(theme::TEXT_DIM),
                );
                return;
            }
            egui::ScrollArea::vertical()
                .max_height(400.0)
                .show(ui, |ui| {
                    egui::Grid::new("save_list_grid")
                        .num_columns(4)
                        .striped(true)
                        .spacing([12.0, 4.0])
                        .show(ui, |ui| {
                            ui.label(theme::caption("Name"));
                            ui.label(theme::caption("Modified"));
                            ui.label(theme::caption("Size"));
                            ui.label("");
                            ui.end_row();
                            for save in &state.saves {
                                if save.is_active {
                                    ui.horizontal(|ui| {
                                        ui.label(&save.name);
                                        ui.label(
                                            egui::RichText::new("· Current session")
                                                .small()
                                                .color(theme::PRIMARY),
                                        );
                                    });
                                } else {
                                    ui.label(&save.name);
                                }
                                ui.label(
                                    egui::RichText::new(&save.modified_iso)
                                        .small()
                                        .monospace()
                                        .color(theme::TEXT_DIM),
                                );
                                ui.label(
                                    egui::RichText::new(format!("{} KB", save.size_kb))
                                        .small()
                                        .monospace(),
                                );
                                ui.horizontal(|ui| {
                                    if ui
                                        .small_button("Load")
                                        .on_hover_text(if save.is_active {
                                            "Load the active session DB."
                                        } else {
                                            "Load this Save-As snapshot."
                                        })
                                        .clicked()
                                    {
                                        want_load = Some(save.path.clone());
                                    }
                                    // sim.db is safe to delete from the
                                    // main menu — load_world only opens
                                    // a pool on OnEnter(InGame), so no
                                    // file handle is held here. Next
                                    // Start will recreate + seed a
                                    // fresh world.
                                    let delete_hover = if save.is_active {
                                        "Permanently delete the active save. \
                                         The next Start will create a fresh \
                                         seeded world."
                                    } else {
                                        "Permanently delete this snapshot \
                                         from disk. No confirmation."
                                    };
                                    if ui
                                        .small_button(
                                            egui::RichText::new("Delete").color(theme::DANGER),
                                        )
                                        .on_hover_text(delete_hover)
                                        .clicked()
                                    {
                                        want_delete = Some(save.path.clone());
                                    }
                                });
                                ui.end_row();
                            }
                        });
                });
        });

    if want_refresh {
        state.last_scan = None;
    }
    if let Some(p) = want_delete {
        match std::fs::remove_file(&p) {
            Ok(()) => {
                info!("client_bevy: deleted save {}", p.display());
                // Sidecar WAL/SHM files would otherwise resurrect
                // partial state on next open. Best-effort cleanup —
                // missing sidecars (the common case for a clean DB)
                // are silently ignored.
                if let Some(name) = p.file_name().and_then(|n| n.to_str()) {
                    if let Some(parent) = p.parent() {
                        for suffix in ["-wal", "-shm", "-journal"] {
                            let side = parent.join(format!("{name}{suffix}"));
                            let _ = std::fs::remove_file(&side);
                        }
                    }
                }
                state.last_scan = None;
            }
            Err(e) => {
                error!("client_bevy: failed to delete {}: {}", p.display(), e);
            }
        }
    }
    if let Some(p) = want_load {
        info!("client_bevy: loading save {}", p.display());
        // Plumb through to the sim's OnEnter(InGame) load — set the
        // path, transition state, then close the panel. The early
        // return below skips the `state.open = open` writeback that
        // would otherwise restore the open flag from egui's
        // close-button binding (which is still `true` at this point
        // because the user clicked Load, not X).
        selected_save.0 = Some(p);
        sim.running = true;
        next_state.set(crate::AppState::InGame);
        state.open = false;
        return;
    }
    state.open = open;
}
