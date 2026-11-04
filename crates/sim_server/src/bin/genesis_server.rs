//! Lightweight executable for Living Sector Genesis.
//!
//! Runs the *same* sim_core + sim_db + sim_server runtime as the original
//! 3D client in --headless mode. The browser Observer is a separate UI,
//! not a second simulation. No Bevy renderer, assets or duplicated economy.

use tracing_subscriber::{EnvFilter, fmt};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| {
        EnvFilter::new("sim_core=info,sim_db=info,sim_server=info,tower_http=warn")
    });
    fmt()
        .with_env_filter(filter)
        .with_writer(std::io::stderr)
        .with_target(true)
        .try_init()?;
    sim_server::runtime::run().await
}
