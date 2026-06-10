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
    availability TEXT NOT NULL DEFAULT 'offline'
                 CHECK (availability IN ('available','busy','offline','on_break','in_transit')),
    last_latitude REAL,
    last_longitude REAL,
    last_location_updated_at TEXT,
    max_active_assignments INTEGER NOT NULL DEFAULT 2,
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
    severity     TEXT NOT NULL DEFAULT 'urgent'
           CHECK (severity IN ('critical','urgent','non_urgent')),
    latitude     REAL NOT NULL,
    longitude    REAL NOT NULL,
    address      TEXT,
    status       TEXT NOT NULL DEFAULT 'pending'
                 CHECK (status IN ('pending','accepted','in_progress','completed','cancelled')),
    responder_id TEXT REFERENCES users(id),
    responder_phone TEXT,
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

  CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user
    ON refresh_tokens(user_id);

  CREATE INDEX IF NOT EXISTS idx_hospitals_location
    ON hospitals(latitude, longitude);
`);

const emergencyColumns = db.prepare("PRAGMA table_info(emergency_requests)").all() as Array<{ name: string }>;
if (!emergencyColumns.some((column) => column.name === 'responder_phone')) {
  db.exec('ALTER TABLE emergency_requests ADD COLUMN responder_phone TEXT');
}
if (!emergencyColumns.some((column) => column.name === 'severity')) {
  db.exec("ALTER TABLE emergency_requests ADD COLUMN severity TEXT NOT NULL DEFAULT 'urgent'");
}

const userColumns = db.prepare("PRAGMA table_info(users)").all() as Array<{ name: string }>;
if (!userColumns.some((column) => column.name === 'availability')) {
  db.exec("ALTER TABLE users ADD COLUMN availability TEXT NOT NULL DEFAULT 'offline'");
}
if (!userColumns.some((column) => column.name === 'last_latitude')) {
  db.exec('ALTER TABLE users ADD COLUMN last_latitude REAL');
}
if (!userColumns.some((column) => column.name === 'last_longitude')) {
  db.exec('ALTER TABLE users ADD COLUMN last_longitude REAL');
}
if (!userColumns.some((column) => column.name === 'last_location_updated_at')) {
  db.exec('ALTER TABLE users ADD COLUMN last_location_updated_at TEXT');
}
if (!userColumns.some((column) => column.name === 'max_active_assignments')) {
  db.exec('ALTER TABLE users ADD COLUMN max_active_assignments INTEGER NOT NULL DEFAULT 2');
}

console.log(`[DB] SQLite database ready at: ${dbPath}`);

export default db;
