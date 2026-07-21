-- Per-system spectral class so the renderer can vary sun colour and
-- size instead of painting every star yellow. NULL = unknown =
-- fallback to "G" (yellow main-sequence) at load time.
--
-- Recognised values match standard Morgan-Keenan classes; renderer
-- maps each to a colour + radius multiplier. Adding new classes is
-- additive — unknown strings fall back to the default.
ALTER TABLE star_systems ADD COLUMN star_type TEXT;
