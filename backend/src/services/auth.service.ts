import { Pool, PoolClient } from 'pg';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import fs from 'fs';
import path from 'path';

// Custom error classes
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

// User interface
export interface User {
  id: string;
  name: string;
  phone: string;
  email?: string;
  role: 'patient' | 'responder';
  created_at: Date;
  updated_at: Date;
}

// Auth response interface
export interface AuthResponse {
  user: User;
  token: string;
  refreshToken: string;
}

// Database connection
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
});

// JWT keys
const privateKey = fs.readFileSync(path.join(__dirname, '../../keys/private.key'), 'utf8');
const publicKey = fs.readFileSync(path.join(__dirname, '../../keys/public.key'), 'utf8');

/**
 * AuthService class that handles authentication, authorization, and token management
 * for the Mobile Emergency Medical Assistance App backend.
 * 
 * Provides registration, login, JWT issuance, token refresh, and logout functionality
 * with PostgreSQL token blacklisting via revoked_tokens table.
 */
export class AuthService {
  /**
   * Registers a new user with the provided credentials
   * 
   * @param name - User's full name
   * @param phone - User's phone number (must be unique)
   * @param email - User's email address (optional)
   * @param password - User's password (will be hashed)
   * @param role - User role ('patient' or 'responder')
   * @returns Promise resolving to {user, token, refreshToken}
   * @throws ValidationError if validation fails
   * @throws AuthError if phone already exists
   */
  static async register(
    name: string,
    phone: string,
    email: string | undefined,
    password: string,
    role: 'patient' | 'responder'
  ): Promise<AuthResponse> {
    const client = await pool.connect();
    
    try {
      // Validate input
      this.validateRegistrationInput(name, phone, email, password, role);

      // Check if phone already exists
      const existingUser = await client.query(
        'SELECT id FROM users WHERE phone = $1',
        [phone]
      );

      if (existingUser.rows.length > 0) {
        throw new AuthError('Phone number already registered', 409);
      }

      // Hash password
      const saltRounds = 12;
      const hashedPassword = await bcrypt.hash(password, saltRounds);

      // Insert user
      const result = await client.query(
        `INSERT INTO users (name, phone, email, password_hash, role, created_at, updated_at) 
         VALUES ($1, $2, $3, $4, $5, NOW(), NOW()) 
         RETURNING id, name, phone, email, role, created_at, updated_at`,
        [name, phone, email, hashedPassword, role]
      );

      const user = result.rows[0] as User;

      // Generate tokens
      const { token, refreshToken } = await this.generateTokens(user);

      // Store refresh token
      await this.storeRefreshToken(client, user.id, refreshToken);

      await client.query('COMMIT');
      
      return { user, token, refreshToken };
    } catch (error: any) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Authenticates a user with phone and password
   * 
   * @param phone - User's phone number
   * @param password - User's password
   * @returns Promise resolving to {user, token, refreshToken}
   * @throws AuthError if credentials are invalid
   */
  static async login(phone: string, password: string): Promise<AuthResponse> {
    const client = await pool.connect();
    
    try {
      // Validate input
      if (!phone || !password) {
        throw new ValidationError('Phone and password are required');
      }

      // Find user by phone
      const result = await client.query(
        `SELECT id, name, phone, email, password_hash, role, created_at, updated_at 
         FROM users WHERE phone = $1`,
        [phone]
      );

      if (result.rows.length === 0) {
        throw new AuthError('Invalid credentials');
      }

      const user = result.rows[0];

      // Verify password
      const isValidPassword = await bcrypt.compare(password, user.password_hash);
      
      if (!isValidPassword) {
        throw new AuthError('Invalid credentials');
      }

      // Remove password hash from user object
      const { password_hash, ...userWithoutPassword } = user;

      // Generate tokens
      const { token, refreshToken } = await this.generateTokens(userWithoutPassword as User);

      // Store refresh token
      await this.storeRefreshToken(client, user.id, refreshToken);

      await client.query('COMMIT');
      
      return { user: userWithoutPassword as User, token, refreshToken };
    } catch (error: any) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Verifies a JWT token and checks if it's not revoked
   * 
   * @param token - JWT token to verify
   * @returns Promise resolving to the decoded token payload
   * @throws AuthError if token is invalid or revoked
   */
  static async verifyToken(token: string): Promise<any> {
    try {
      // Check if token is revoked
      const isRevoked = await this.isTokenRevoked(token);
      if (isRevoked) {
        throw new AuthError('Token has been revoked');
      }

      // Verify token with public key
      const decoded = jwt.verify(token, publicKey, { algorithms: ['RS256'] });
      return decoded;
    } catch (error: any) {
      if (error instanceof jwt.JsonWebTokenError) {
        throw new AuthError('Invalid token');
      }
      throw error;
    }
  }

  /**
   * Refreshes an access token using a valid refresh token
   * 
   * @param oldToken - Current access token
   * @returns Promise resolving to {user, token, refreshToken}
   * @throws AuthError if refresh token is invalid
   */
  static async refreshToken(oldToken: string): Promise<AuthResponse> {
    const client = await pool.connect();
    
    try {
      // Decode old token to get user info (without verification for refresh)
      const decoded = jwt.decode(oldToken) as any;
      
      if (!decoded || !decoded.userId) {
        throw new AuthError('Invalid token for refresh');
      }

      // Find valid refresh token for this user
      const refreshTokenResult = await client.query(
        `SELECT token, expires_at FROM refresh_tokens 
         WHERE user_id = $1 AND expires_at > NOW() LIMIT 1`,
        [decoded.userId]
      );

      if (refreshTokenResult.rows.length === 0) {
        throw new AuthError('No valid refresh token found');
      }

      // Get user data
      const userResult = await client.query(
        `SELECT id, name, phone, email, role, created_at, updated_at 
         FROM users WHERE id = $1`,
        [decoded.userId]
      );

      if (userResult.rows.length === 0) {
        throw new AuthError('User not found');
      }

      const user = userResult.rows[0] as User;

      // Generate new tokens
      const { token, refreshToken } = await this.generateTokens(user);

      // Store new refresh token and invalidate old one
      await client.query('DELETE FROM refresh_tokens WHERE token = $1', [refreshTokenResult.rows[0].token]);
      await this.storeRefreshToken(client, user.id, refreshToken);

      await client.query('COMMIT');
      
      return { user, token, refreshToken };
    } catch (error: any) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Logs out a user by revoking their access token
   * 
   * @param userId - User ID
   * @param token - Access token to revoke
   * @returns Promise resolving when logout is complete
   */
  static async logout(userId: string, token: string): Promise<void> {
    const client = await pool.connect();
    
    try {
      // Add token to revoked_tokens table
      await client.query(
        'INSERT INTO revoked_tokens (token, revoked_at) VALUES ($1, NOW())',
        [token]
      );

      // Remove user's refresh tokens
      await client.query(
        'DELETE FROM refresh_tokens WHERE user_id = $1',
        [userId]
      );

      await client.query('COMMIT');
    } catch (error: any) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Checks if a token is revoked
   * 
   * @param token - Token to check
   * @returns Promise resolving to true if token is revoked, false otherwise
   */
  private static async isTokenRevoked(token: string): Promise<boolean> {
    const result = await pool.query(
      'SELECT token FROM revoked_tokens WHERE token = $1 LIMIT 1',
      [token]
    );
    
    return result.rows.length > 0;
  }

  /**
   * Generates JWT access and refresh tokens for a user
   * 
   * @param user - User object
   * @returns Promise resolving to {token, refreshToken}
   */
  private static async generateTokens(user: User): Promise<{token: string, refreshToken: string}> {
    // Access token (short-lived)
    const tokenPayload = {
      userId: user.id,
      phone: user.phone,
      role: user.role,
      type: 'access'
    };

    const token = jwt.sign(tokenPayload, privateKey, {
      algorithm: 'RS256',
      expiresIn: '15m',
      issuer: 'memaap-backend',
      audience: 'memaap-mobile'
    });

    // Refresh token (long-lived)
    const refreshTokenPayload = {
      userId: user.id,
      type: 'refresh'
    };

    const refreshToken = jwt.sign(refreshTokenPayload, privateKey, {
      algorithm: 'RS256',
      expiresIn: '7d',
      issuer: 'memaap-backend',
      audience: 'memaap-mobile'
    });

    return { token, refreshToken };
  }

  /**
   * Stores a refresh token in the database
   * 
   * @param client - Database client
   * @param userId - User ID
   * @param refreshToken - Refresh token to store
   */
  private static async storeRefreshToken(client: PoolClient, userId: string, refreshToken: string): Promise<void> {
    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + 7); // 7 days from now

    await client.query(
      'INSERT INTO refresh_tokens (user_id, token, expires_at) VALUES ($1, $2, $3)',
      [userId, refreshToken, expiresAt]
    );
  }

  /**
   * Validates registration input data
   * 
   * @param name - User name
   * @param phone - User phone
   * @param email - User email
   * @param password - User password
   * @param role - User role
   * @throws ValidationError if validation fails
   */
  private static validateRegistrationInput(
    name: string,
    phone: string,
    email: string | undefined,
    password: string,
    role: string
  ): void {
    if (!name || name.trim().length < 2) {
      throw new ValidationError('Name must be at least 2 characters long');
    }

    if (!phone || !/^\+?[1-9]\d{1,14}$/.test(phone)) {
      throw new ValidationError('Invalid phone number format');
    }

    if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      throw new ValidationError('Invalid email format');
    }

    if (!password || password.length < 8) {
      throw new ValidationError('Password must be at least 8 characters long');
    }

    if (!['patient', 'responder'].includes(role)) {
      throw new ValidationError('Role must be either "patient" or "responder"');
    }
  }
}
