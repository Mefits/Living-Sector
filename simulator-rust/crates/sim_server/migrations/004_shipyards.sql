-- Phase 18c: shipyards + module inventory.
--
-- Shipyards are `facilities` rows with `facility_type = 'shipyard'`. They
-- carry a parallel inventory of installable subsystem modules,
-- orthogonal to the commodity `reserves` column. Stored as a JSON
-- object mapping module slug (from `sim_core::modules::CATALOG`) →
-- integer unit count. Existing facilities default to `'{}'`; only
-- shipyards grow non-empty entries.

ALTER TABLE facilities
    ADD COLUMN module_stock TEXT NOT NULL DEFAULT '{}';
