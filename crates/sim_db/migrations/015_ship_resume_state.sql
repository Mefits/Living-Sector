-- NULL keeps legacy navigation loading; new snapshots carry complete flight progress.
ALTER TABLE ships ADD COLUMN resume_json TEXT;
