"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.UserRepository = void 0;
const pg_1 = require("pg");
// Basic user repository for admin operations
class UserRepository {
    static getPool() {
        return new pg_1.Pool({
            connectionString: process.env.DATABASE_URL,
            ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
        });
    }
    static async findById(userId) {
        const pool = this.getPool();
        const client = await pool.connect();
        try {
            const query = 'SELECT * FROM users WHERE id = $1';
            const result = await client.query(query, [userId]);
            return result.rows[0];
        }
        finally {
            client.release();
        }
    }
    static async updateStatus(userId, status) {
        const pool = this.getPool();
        const client = await pool.connect();
        try {
            const query = 'UPDATE users SET status = $1, updated_at = NOW() WHERE id = $2';
            await client.query(query, [status, userId]);
        }
        finally {
            client.release();
        }
    }
}
exports.UserRepository = UserRepository;
