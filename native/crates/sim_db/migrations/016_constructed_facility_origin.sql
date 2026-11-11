ALTER TABLE facilities ADD COLUMN construction_site_id TEXT;
CREATE UNIQUE INDEX idx_facilities_construction_site ON facilities(construction_site_id) WHERE construction_site_id IS NOT NULL;
