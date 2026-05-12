import { Pool, PoolClient } from 'pg';

// Basic hospital repository for admin operations
export class HospitalRepository {
  private static getPool(): Pool {
    return new Pool({
      connectionString: process.env.DATABASE_URL,
      ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
    });
  }

  static async findAll(): Promise<any[]> {
    const pool = this.getPool();
    const client = await pool.connect();
    
    try {
      const query = 'SELECT * FROM hospitals ORDER BY name';
      const result = await client.query(query);
      return result.rows;
    } finally {
      client.release();
    }
  }

  static async findById(hospitalId: string): Promise<any> {
    const pool = this.getPool();
    const client = await pool.connect();
    
    try {
      const query = 'SELECT * FROM hospitals WHERE id = $1';
      const result = await client.query(query, [hospitalId]);
      return result.rows[0];
    } finally {
      client.release();
    }
  }

  static async updateAvailability(hospitalId: string, isAvailable: boolean): Promise<void> {
    const pool = this.getPool();
    const client = await pool.connect();
    
    try {
      const query = 'UPDATE hospitals SET is_available = $1, updated_at = NOW() WHERE id = $2';
      await client.query(query, [isAvailable, hospitalId]);
    } finally {
      client.release();
    }
  }
}
