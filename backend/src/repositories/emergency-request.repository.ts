import { Pool, PoolClient } from 'pg';

// Basic emergency request repository for admin operations
export class EmergencyRequestRepository {
  private static getPool(): Pool {
    return new Pool({
      connectionString: process.env.DATABASE_URL,
      ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
    });
  }

  static async findByDateRange(from: Date, to: Date): Promise<any[]> {
    const pool = this.getPool();
    const client = await pool.connect();
    
    try {
      const query = `
        SELECT * FROM emergency_requests
        WHERE created_at >= $1 AND created_at <= $2
        ORDER BY created_at DESC
      `;
      
      const result = await client.query(query, [from, to]);
      return result.rows;
    } finally {
      client.release();
    }
  }

  static async findById(requestId: string): Promise<any> {
    const pool = this.getPool();
    const client = await pool.connect();
    
    try {
      const query = 'SELECT * FROM emergency_requests WHERE id = $1';
      const result = await client.query(query, [requestId]);
      return result.rows[0];
    } finally {
      client.release();
    }
  }

  static async updateStatus(requestId: string, status: string): Promise<void> {
    const pool = this.getPool();
    const client = await pool.connect();
    
    try {
      const query = 'UPDATE emergency_requests SET status = $1, updated_at = NOW() WHERE id = $2';
      await client.query(query, [status, requestId]);
    } finally {
      client.release();
    }
  }

  static async assignResponder(requestId: string, responderId: string): Promise<void> {
    const pool = this.getPool();
    const client = await pool.connect();
    
    try {
      const query = 'UPDATE emergency_requests SET responder_id = $1, updated_at = NOW() WHERE id = $2';
      await client.query(query, [responderId, requestId]);
    } finally {
      client.release();
    }
  }
}
