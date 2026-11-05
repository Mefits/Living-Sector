-- NULL distinguishes pre-existing/unverified funding from explicit new escrow.
-- Do not infer or mint balances for contracts saved by older versions.
ALTER TABLE contracts ADD COLUMN funding_json TEXT;
ALTER TABLE contracts ADD COLUMN renewal_count INTEGER NOT NULL DEFAULT 0;
