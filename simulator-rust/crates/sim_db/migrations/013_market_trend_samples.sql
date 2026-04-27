-- Phase 20d: persistent ring of `MarketHistory.trend_samples`.
--
-- One row per (market, tick, commodity); the engine emits a batch
-- every `MARKET_TREND_SAMPLE_INTERVAL_BASE` (16) base ticks, one
-- entry per commodity active at that market. Loader on startup
-- rehydrates the in-memory ring (`MARKET_TREND_KEEP` = 200 newest
-- samples per market) so charts pre-populate instead of starting
-- empty after a restart.
--
-- Pruning policy: deferred. ~200k rows per ten thousand sim ticks
-- with the current 39-market, 6-commodity seed → ~8 MB on disk per
-- 10k ticks. Easy to outrun with a long-running sim, but for the
-- MVP we keep everything so users can sweep the full history with
-- ad-hoc SQL. Add a retention sweep when storage actually pinches.
--
-- ON DELETE CASCADE on the FK so an admin-removed market also
-- drops its trend rows (otherwise they orphan and clutter the
-- table).
CREATE TABLE IF NOT EXISTS market_trend_samples (
    market_id   INTEGER NOT NULL,
    tick        INTEGER NOT NULL,
    commodity   TEXT    NOT NULL,
    price       REAL    NOT NULL,
    supply      REAL    NOT NULL,
    PRIMARY KEY (market_id, tick, commodity),
    FOREIGN KEY (market_id) REFERENCES markets(id) ON DELETE CASCADE
);

-- Loader's primary access pattern: latest-N-samples per market
-- ordered desc. Index on (market_id, tick DESC) lets the query
-- terminate after K rows without a full scan.
CREATE INDEX IF NOT EXISTS idx_market_trend_samples_market_tick
    ON market_trend_samples (market_id, tick DESC);
