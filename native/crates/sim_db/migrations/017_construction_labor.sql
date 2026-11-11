-- Additive: old incomplete sites require paid work; completed facilities are unchanged.
ALTER TABLE construction_sites ADD COLUMN labor_state TEXT NOT NULL DEFAULT '{}';
