-- AI Drop hosted free tier — D1 schema.
-- Apply with: wrangler d1 execute aidrop --remote --file=./schema.sql

-- One row per device (anonymous, identified by a client-generated UUID).
-- trial_used counts lifetime trial interactions consumed (capped at TRIAL_TOTAL).
-- pro = 1 marks a verified subscriber (grants the higher MAX_CONTENT_CHARS_PRO cap).
CREATE TABLE IF NOT EXISTS accounts (
  device_id   TEXT PRIMARY KEY,
  trial_used  INTEGER NOT NULL DEFAULT 0,
  pro         INTEGER NOT NULL DEFAULT 0,
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- EXISTING databases only: CREATE above is skipped if `accounts` already exists, so
-- add the column ONCE (D1 has no ADD COLUMN IF NOT EXISTS — run exactly one time):
--   wrangler d1 execute aidrop --remote --command "ALTER TABLE accounts ADD COLUMN pro INTEGER NOT NULL DEFAULT 0"
-- Grant Pro to a device (to test the higher cap, or until Paddle is wired):
--   wrangler d1 execute aidrop --remote --command "UPDATE accounts SET pro=1 WHERE device_id='<device-id>'"

-- Per-device, per-UTC-day usage (used once the trial is exhausted).
--   count  = interactions that day (kept for instrumentation / the global breaker)
--   tokens = actual Gemini tokens debited that day (input + output) — the value the
--            daily quota is metered on. Captures images too (unlike a char count).
CREATE TABLE IF NOT EXISTS usage (
  device_id  TEXT NOT NULL,
  day        TEXT NOT NULL,          -- 'YYYY-MM-DD' in UTC
  count      INTEGER NOT NULL DEFAULT 0,
  tokens     INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (device_id, day)
);

-- EXISTING databases only: the CREATE above is skipped if `usage` already exists, so
-- add the tokens column ONCE (D1 has no ADD COLUMN IF NOT EXISTS — run exactly once):
--   wrangler d1 execute aidrop --remote --command "ALTER TABLE usage ADD COLUMN tokens INTEGER NOT NULL DEFAULT 0"

-- Global per-UTC-day total — the budget circuit-breaker.
CREATE TABLE IF NOT EXISTS global_usage (
  day    TEXT PRIMARY KEY,           -- 'YYYY-MM-DD' in UTC
  count  INTEGER NOT NULL DEFAULT 0
);

-- Spend instrumentation — per UTC-day × model billed × requested-tier roll-up. Lets the
-- operator watch the real Gemini bill and tune routing on data. Written best-effort after
-- each successful call; read via GET /v1/stats (admin-token guarded). in/out tokens are
-- split so cost can be estimated. Safe to (re)run on a live DB — IF NOT EXISTS:
--   wrangler d1 execute aidrop --remote --file=./schema.sql
CREATE TABLE IF NOT EXISTS spend (
  day               TEXT NOT NULL,   -- 'YYYY-MM-DD' in UTC
  model             TEXT NOT NULL,   -- the model actually billed (incl. fallback)
  tier              TEXT NOT NULL,   -- requested tier hint: fast | strong | extra | other
  calls             INTEGER NOT NULL DEFAULT 0,
  prompt_tokens     INTEGER NOT NULL DEFAULT 0,
  completion_tokens INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, model, tier)
);
