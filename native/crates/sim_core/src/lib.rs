//! Core simulation logic — pure Rust, no async.
//!
//! This crate holds every component definition, every tick function, every
//! pure helper (BT engine, utility scorer, price engine, order book, recipes).
//! It depends on hecs for entity storage and serde for JSON but never on
//! tokio, axum, or sqlx — those belong to `sim_server`.
//!
//! The design goal is that a reviewer can understand the simulation's
//! semantics by reading this crate in isolation. See `CLAUDE.md` in the
//! project root for the full architectural context.
//!
//! ## Module layout
//!
//! - [`agents`]: component bundles per agent type + tick functions (ship, market, facility, population, celestial_body, faction)
//! - [`ai`]: behavior tree engine, utility scoring, considerations, personality archetypes
//! - [`economy`]: commodities enum, order matching, price engine (coverage model), production recipes
//! - [`simulation`]: [`simulation::config::TickConfig`], [`simulation::commands::SimCommand`] for cross-phase effects, [`simulation::spawner::AgentStore`]
//! - [`spatial`]: position helpers (quadtree + chunk LOD — skeletons, unused until 10k+ agents)
//! - [`world`]: static world registry (locations, routes, factions), travel time math

pub mod agents;
pub mod ai;
pub mod economy;
pub mod facility_modules;
pub mod modules;
pub mod simulation;
pub mod spatial;
pub mod world;

pub mod strategy;
