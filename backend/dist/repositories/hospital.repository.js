"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.HospitalRepository = void 0;
const pg_1 = require("pg");
// Basic hospital repository for admin operations
class HospitalRepository {
    static getPool() {
        return new pg_1.Pool({
            connectionString: process.env.DATABASE_URL,
            ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
        });
    }
    static async findAll() {
        const pool = this.getPool();
        const client = await pool.connect();
        try {
            const query = 'SELECT * FROM hospitals ORDER BY name';
            const result = await client.query(query);
            return result.rows;
        }
        finally {
            client.release();
        }
    }
    static async findById(hospitalId) {
        const pool = this.getPool();
        const client = await pool.connect();
        try {
            const query = 'SELECT * FROM hospitals WHERE id = $1';
            const result = await client.query(query, [hospitalId]);
            return result.rows[0];
        }
        finally {
            client.release();
        }
    }
    static async updateAvailability(hospitalId, isAvailable) {
        const pool = this.getPool();
        const client = await pool.connect();
        try {
            const query = 'UPDATE hospitals SET is_available = $1, updated_at = NOW() WHERE id = $2';
            await client.query(query, [isAvailable, hospitalId]);
        }
        finally {
            client.release();
        }
    }
}
exports.HospitalRepository = HospitalRepository;
