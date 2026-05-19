/**
 * auth.service.ts
 *
 * Handles registration, login, JWT issuance, token refresh, and logout.
 *
 * CHANGES FROM PostgreSQL VERSION:
 *  - All `pool.connect()` / `client.query()` replaced with synchronous
 *    better-sqlite3 `db.prepare().run()` / `.get()` / `.all()`
 *  - RSA key files removed; uses HMAC-SHA256 with JWT_SECRET env variable
 *  - No more PoolClient to release — SQLite is connection-free
 */

import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import { v4 as uuidv4 } from 'uuid';
import db from '../config/database';

// ── Custom errors ────────────────────────────────────────────────────────────

export class AuthError extends Error {
  constructor(message: string, public statusCode: number = 401) {
    super(message);
    this.name = 'AuthError';
  }
}

export class ValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ValidationError';
  }
}

// ── Interfaces ───────────────────────────────────────────────────────────────

export interface User {
  id: string;
  name: string;
  phone: string;
  email?: string | null;
  role: 'patient' | 'responder' | 'admin';
  status: string;
  created_at: string;
  updated_at: string;
}

export interface AuthResponse {
  user: User;
  token: string;
  refreshToken: string;
}

// ── JWT configuration ────────────────────────────────────────────────────────

const JWT_SECRET = process.env.JWT_SECRET || 'memaap-dev-secret-change-in-production';
const ACCESS_TOKEN_EXPIRY = '15m';
const REFRESH_TOKEN_EXPIRY = '7d';
const REFRESH_TOKEN_DAYS = 7;

// ── AuthService ──────────────────────────────────────────────────────────────

export class AuthService {

  /**
   * Registers a new user (patient or responder).
   * Returns the created user plus fresh JWT tokens.
   */
  static async register(
    name: string,
    phone: string,
    email: string | undefined,
    password: string,
    role: 'patient' | 'responder',
  ): Promise<AuthResponse> {
    // Validate fields
    this._validateInput(name, phone, email, password, role);

    // Check phone uniqueness
    const existing = db.prepare('SELECT id FROM users WHERE phone = ?').get(phone);
    if (existing) {
      throw new AuthError('Phone number already registered', 409);
    }

    // Hash password (cost factor 12)
    const passwordHash = await bcrypt.hash(password, 12);
    const userId = uuidv4();

    // Insert user
    db.prepare(`
      INSERT INTO users (id, name, phone, email, password_hash, role, status, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, 'active', datetime('now'), datetime('now'))
    `).run(userId, name.trim(), phone.trim(), email?.trim() || null, passwordHash, role);

    // Fetch the newly created user (avoids returning password_hash)
    const user = db.prepare(
      'SELECT id, name, phone, email, role, status, created_at, updated_at FROM users WHERE id = ?'
    ).get(userId) as User;

    const { token, refreshToken } = this._generateTokens(user);
    this._storeRefreshToken(user.id, refreshToken);

    return { user, token, refreshToken };
  }

  /**
   * Authenticates a user with phone + password.
   * Returns the user profile and fresh JWT tokens.
   */
  static async login(phone: string, password: string): Promise<AuthResponse> {
    if (!phone || !password) {
      throw new ValidationError('Phone and password are required');
    }

    // Fetch user (includes password_hash for comparison)
    const row = db.prepare('SELECT * FROM users WHERE phone = ?').get(phone) as any;
    if (!row) {
      throw new AuthError('Invalid credentials');
    }

    if (row.status === 'banned') {
      throw new AuthError('Account has been suspended', 403);
    }

    // Verify password
    const valid = await bcrypt.compare(password, row.password_hash);
    if (!valid) {
      throw new AuthError('Invalid credentials');
    }

    // Strip password_hash before returning
    const { password_hash, ...user } = row;

    const { token, refreshToken } = this._generateTokens(user as User);
    this._storeRefreshToken(user.id, refreshToken);

    return { user: user as User, token, refreshToken };
  }

  /**
   * Verifies an access token is valid and not revoked.
   * Returns the decoded JWT payload.
   */
  static async verifyToken(token: string): Promise<any> {
    // Check revocation list first
    const revoked = db.prepare('SELECT id FROM revoked_tokens WHERE token = ?').get(token);
    if (revoked) {
      throw new AuthError('Token has been revoked');
    }

    try {
      return jwt.verify(token, JWT_SECRET);
    } catch {
      throw new AuthError('Invalid or expired token');
    }
  }

  /**
   * Exchanges a valid refresh token for a new access token + new refresh token.
   * Old refresh token is deleted (token rotation).
   */
  static async refreshToken(oldRefreshToken: string): Promise<AuthResponse> {
    let decoded: any;
    try {
      decoded = jwt.verify(oldRefreshToken, JWT_SECRET);
    } catch {
      throw new AuthError('Invalid refresh token');
    }

    // Check DB: token must exist and not be expired
    const stored = db.prepare(
      "SELECT * FROM refresh_tokens WHERE token = ? AND expires_at > datetime('now')"
    ).get(oldRefreshToken) as any;

    if (!stored) {
      throw new AuthError('Refresh token expired or not found');
    }

    // Load user
    const user = db.prepare(
      'SELECT id, name, phone, email, role, status, created_at, updated_at FROM users WHERE id = ?'
    ).get(decoded.userId) as User | undefined;

    if (!user) {
      throw new AuthError('User not found');
    }

    // Rotate tokens
    db.prepare('DELETE FROM refresh_tokens WHERE token = ?').run(oldRefreshToken);
    const { token, refreshToken } = this._generateTokens(user);
    this._storeRefreshToken(user.id, refreshToken);

    return { user, token, refreshToken };
  }

  /**
   * Logs out a user: revokes their access token and deletes all their refresh tokens.
   */
  static async logout(userId: string, token: string): Promise<void> {
    db.prepare(
      "INSERT OR IGNORE INTO revoked_tokens (token, revoked_at) VALUES (?, datetime('now'))"
    ).run(token);
    db.prepare('DELETE FROM refresh_tokens WHERE user_id = ?').run(userId);
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  private static _generateTokens(user: User): { token: string; refreshToken: string } {
    const base = { userId: user.id, phone: user.phone, role: user.role };

    const token = jwt.sign(
      { ...base, type: 'access' },
      JWT_SECRET,
      { expiresIn: ACCESS_TOKEN_EXPIRY }
    );

    const refreshToken = jwt.sign(
      { userId: user.id, type: 'refresh' },
      JWT_SECRET,
      { expiresIn: REFRESH_TOKEN_EXPIRY }
    );

    return { token, refreshToken };
  }

  private static _storeRefreshToken(userId: string, refreshToken: string): void {
    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + REFRESH_TOKEN_DAYS);

    db.prepare(
      'INSERT INTO refresh_tokens (user_id, token, expires_at) VALUES (?, ?, ?)'
    ).run(userId, refreshToken, expiresAt.toISOString());
  }

  private static _validateInput(
    name: string, phone: string, email: string | undefined,
    password: string, role: string
  ): void {
    if (!name || name.trim().length < 2)
      throw new ValidationError('Name must be at least 2 characters');
    if (!phone || !/^\+?[1-9]\d{1,14}$/.test(phone.trim()))
      throw new ValidationError('Invalid phone number format');
    if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim()))
      throw new ValidationError('Invalid email format');
    if (!password || password.length < 8)
      throw new ValidationError('Password must be at least 8 characters');
    if (!['patient', 'responder'].includes(role))
      throw new ValidationError('Role must be "patient" or "responder"');
  }
}
