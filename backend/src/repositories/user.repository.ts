import { Pool, PoolClient } from 'pg';

// Basic user repository for admin operations
export class UserRepository {
  private static getPool(): Pool {
    return new Pool({
      connectionString: process.env.DATABASE_URL,
      ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
    });
  }

  static async findById(userId: string): Promise<any> {
    const pool = this.getPool();
    const client = await pool.connect();
    
    try {
      const query = 'SELECT * FROM users WHERE id = $1';
      const result = await client.query(query, [userId]);
      return result.rows[0];
    } finally {
      client.release();
    }
  }

  static async updateStatus(userId: string, status: string): Promise<void> {
    const pool = this.getPool();
    const client = await pool.connect();
    
    try {
      const query = 'UPDATE users SET status = $1, updated_at = NOW() WHERE id = $2';
      await client.query(query, [status, userId]);
    } finally {
      client.release();
    }
  }
}
