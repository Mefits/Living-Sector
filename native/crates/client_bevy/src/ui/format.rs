//! Cross-panel string formatters.
//!
//! Tiny shared helpers that several panels reach for. Add new
//! formatters here when more than one panel needs them; one-off
//! formatters belong in the panel that uses them.
//!
//! Extracted from `ui/mod.rs` in the Phase-21 god-module split.

/// Humanise an i64 credit count for table display.
///
///   * `≥ 1_000_000` → `1.23M`
///   * `≥ 10_000`    → `12.3k`
///   * `< 10_000`    → raw integer (precision matters at the bottom
///     of the range — that's where ship-broke / hoard thresholds live).
///
/// Used by the ship list, contract board, faction ledger, pop
/// browser, ship details, facility list + details, retirements.
pub(super) fn format_credits(n: i64) -> String {
    if n.abs() >= 1_000_000 {
        format!("{:.2}M", n as f64 / 1_000_000.0)
    } else if n.abs() >= 10_000 {
        format!("{:.1}k", n as f64 / 1_000.0)
    } else {
        format!("{}", n)
    }
}
