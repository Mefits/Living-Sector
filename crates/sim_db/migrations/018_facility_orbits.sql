-- Physical station-orbit phase. NULL uses the stable, location-keyed initial angle.
-- Shared-location modules all move together; updates persist their own phase.
ALTER TABLE facilities ADD COLUMN orbit_angle REAL DEFAULT NULL;
