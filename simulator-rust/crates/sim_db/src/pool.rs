use anyhow::Result;
use sqlx::{
    sqlite::{SqliteConnectOptions, SqliteJournalMode, SqlitePoolOptions, SqliteSynchronous},
    SqlitePool,
};
use std::str::FromStr;

pub async fn create_pool(db_path: &str) -> Result<SqlitePool> {
    let opts = SqliteConnectOptions::from_str(db_path)?
        .create_if_missing(true)
        .journal_mode(SqliteJournalMode::Wal)
        .synchronous(SqliteSynchronous::Normal)
        .pragma("cache_size", "10000")
        .pragma("foreign_keys", "ON");

    let pool = SqlitePoolOptions::new()
        .max_connections(1) // single writer; WAL allows concurrent reads
        .connect_with(opts)
        .await?;

    Ok(pool)
}

pub async fn run_migrations(pool: &SqlitePool) -> Result<()> {
    // Path is relative to CARGO_MANIFEST_DIR (crates/sim_server/)
    sqlx::migrate!().run(pool).await?;
    Ok(())
}
