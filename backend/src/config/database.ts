/**
 * database.ts — Single SQLite database for the entire MEMA backend.
 *
 * Opens (or creates) a single file: backend/data/memaap.db
 * Creates all tables with IF NOT EXISTS so it is safe to call on every startup.
 * Exports the `db` singleton — every service/route imports from here.
 *
 * WHY better-sqlite3:
 *  - Synchronous API = simpler code, no pool management
 *  - Works out of the box, no server to install or configure
 *  - Same SQLite file format the Flutter app uses on-device
 *  - WAL journal mode makes concurrent reads fast
 */

import Database from 'better-sqlite3';
import path from 'path';
import fs from 'fs';

// Ensure the data directory exists next to the src folder
const dataDir = path.join(__dirname, '../../data');
if (!fs.existsSync(dataDir)) {
  fs.mkdirSync(dataDir, { recursive: true });
}

const dbPath = process.env.SQLITE_PATH || path.join(dataDir, 'memaap.db');

const db = new Database(dbPath);

// Performance & integrity settings
db.pragma('journal_mode = WAL');   // concurrent readers
db.pragma('foreign_keys = ON');    // enforce referential integrity
db.pragma('synchronous = NORMAL'); // safe + fast for WAL mode

// ─────────────────────────── Table definitions ───────────────────────────────

db.exec(`
  -- Users: both patients and responders share this table, differentiated by role
  CREATE TABLE IF NOT EXISTS users (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    phone       TEXT NOT NULL UNIQUE,
    email       TEXT UNIQUE,
    password_hash TEXT NOT NULL,
    role        TEXT NOT NULL DEFAULT 'patient'
                CHECK (role IN ('patient','responder','admin')),
    status      TEXT NOT NULL DEFAULT 'active'
                CHECK (status IN ('active','inactive','banned')),
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
  );

  -- Hospitals: seeded by admins; queried by patients to find nearby help
  CREATE TABLE IF NOT EXISTS hospitals (
    id                 TEXT PRIMARY KEY,
    name               TEXT NOT NULL,
    address            TEXT NOT NULL,
    latitude           REAL NOT NULL,
    longitude          REAL NOT NULL,
    phone              TEXT NOT NULL,
    email              TEXT,
    website            TEXT,
    emergency_services TEXT,         -- JSON array stored as text
    is_available       INTEGER NOT NULL DEFAULT 1,
    created_at         TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at         TEXT NOT NULL DEFAULT (datetime('now'))
  );

  -- Emergency requests: created by patients, accepted by responders
  CREATE TABLE IF NOT EXISTS emergency_requests (
    id           TEXT PRIMARY KEY,
    user_id      TEXT NOT NULL REFERENCES users(id),
    type         TEXT NOT NULL,
    description  TEXT,
    latitude     REAL NOT NULL,
    longitude    REAL NOT NULL,
    address      TEXT,
    status       TEXT NOT NULL DEFAULT 'pending'
                 CHECK (status IN ('pending','accepted','in_progress','completed','cancelled')),
    responder_id TEXT REFERENCES users(id),
    hospital_id  TEXT REFERENCES hospitals(id),
    created_at   TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at   TEXT NOT NULL DEFAULT (datetime('now')),
    accepted_at  TEXT,
    completed_at TEXT
  );

  -- Notifications: stored for offline users, cleared on delivery
  CREATE TABLE IF NOT EXISTS notifications (
    id         TEXT PRIMARY KEY,
    user_id    TEXT NOT NULL REFERENCES users(id),
    title      TEXT NOT NULL,
    body       TEXT NOT NULL,
    data       TEXT,                 -- JSON payload as text
    is_read    INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );

  -- Call sessions: one emergency caller <-> responder session at a time (MVP)
  CREATE TABLE IF NOT EXISTS call_sessions (
    id             TEXT PRIMARY KEY,
    emergency_id   TEXT NOT NULL REFERENCES emergency_requests(id),
    caller_user_id TEXT NOT NULL REFERENCES users(id),
    callee_user_id TEXT NOT NULL REFERENCES users(id),
    status         TEXT NOT NULL DEFAULT 'ringing'
                   CHECK (status IN ('ringing','active','ended','missed','rejected','failed')),
    started_at     TEXT NOT NULL DEFAULT (datetime('now')),
    answered_at    TEXT,
    ended_at       TEXT,
    end_reason     TEXT
                   CHECK (end_reason IN ('hangup','timeout','network_error','rejected') OR end_reason IS NULL)
  );

  -- Call events: optional event timeline for debugging and auditability
  CREATE TABLE IF NOT EXISTS call_events (
    id              TEXT PRIMARY KEY,
    call_session_id TEXT NOT NULL REFERENCES call_sessions(id) ON DELETE CASCADE,
    event_type      TEXT NOT NULL,
    event_payload   TEXT,
    created_at      TEXT NOT NULL DEFAULT (datetime('now'))
  );

  -- Refresh tokens: long-lived tokens for silent re-auth
  CREATE TABLE IF NOT EXISTS refresh_tokens (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id    TEXT NOT NULL REFERENCES users(id),
    token      TEXT NOT NULL UNIQUE,
    expires_at TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );

  -- Revoked access tokens: checked on every request to handle logout
  CREATE TABLE IF NOT EXISTS revoked_tokens (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    token      TEXT NOT NULL UNIQUE,
    revoked_at TEXT NOT NULL DEFAULT (datetime('now'))
  );

  -- Audit log: track admin actions
  CREATE TABLE IF NOT EXISTS audit_logs (
    id         TEXT PRIMARY KEY,
    user_id    TEXT NOT NULL,
    action     TEXT NOT NULL,
    resource   TEXT NOT NULL,
    timestamp  TEXT NOT NULL DEFAULT (datetime('now')),
    details    TEXT
  );

  -- ── Indexes for hot query paths ──────────────────────────────────────────

  CREATE INDEX IF NOT EXISTS idx_emergency_user
    ON emergency_requests(user_id);

  CREATE INDEX IF NOT EXISTS idx_emergency_status
    ON emergency_requests(status);

  CREATE INDEX IF NOT EXISTS idx_emergency_responder
    ON emergency_requests(responder_id);

  CREATE INDEX IF NOT EXISTS idx_notifications_user
    ON notifications(user_id, is_read);

  CREATE INDEX IF NOT EXISTS idx_call_sessions_emergency
    ON call_sessions(emergency_id, started_at DESC);

  CREATE INDEX IF NOT EXISTS idx_call_sessions_status
    ON call_sessions(status);

  CREATE INDEX IF NOT EXISTS idx_call_events_session
    ON call_events(call_session_id, created_at DESC);

  CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user
    ON refresh_tokens(user_id);

  CREATE INDEX IF NOT EXISTS idx_hospitals_location
    ON hospitals(latitude, longitude);
`);

console.log(`[DB] SQLite database ready at: ${dbPath}`);

export default db;
