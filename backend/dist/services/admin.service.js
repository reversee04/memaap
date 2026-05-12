"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.AdminService = exports.InsufficientPermissionsError = exports.AdminError = void 0;
const pg_1 = require("pg");
const uuid_1 = require("uuid");
const winston = __importStar(require("winston"));
const report_generator_service_1 = require("./report-generator.service");
// Custom error classes
class AdminError extends Error {
    statusCode;
    constructor(message, statusCode) {
        super(message);
        this.statusCode = statusCode;
        this.name = 'AdminError';
    }
}
exports.AdminError = AdminError;
class InsufficientPermissionsError extends AdminError {
    constructor(message) {
        super(message, 403);
        this.name = 'InsufficientPermissionsError';
    }
}
exports.InsufficientPermissionsError = InsufficientPermissionsError;
/**
 * Service class for system-admin operations
 *
 * Provides user management, hospital registration, request monitoring,
 * and system reporting with full audit logging for Mobile Emergency Medical Assistance App.
 */
class AdminService {
    static logger = winston.createLogger({
        level: 'info',
        format: winston.format.combine(winston.format.timestamp(), winston.format.json()),
    });
    /**
     * Gets all users with optional filtering
     *
     * @param filters - Optional filters for role, status, search, pagination
     * @param adminContext - Admin action context for audit logging
     *
     * @returns Promise resolving to array of users
     */
    static async getAllUsers(filters, adminContext) {
        const pool = this.getPool();
        const client = await pool.connect();
        try {
            // Log admin action
            await this.logAdminAction({
                adminId: adminContext?.adminId || 'unknown',
                action: 'VIEW_USERS',
                resource: 'users',
                details: { filters },
            }, client);
            // Build query with filters
            let query = `
        SELECT id, name, email, phone, role, status, created_at, updated_at
        FROM users
        WHERE 1=1
      `;
            const queryParams = [];
            let paramIndex = 1;
            if (filters?.role) {
                query += ` AND role = $${paramIndex++}`;
                queryParams.push(filters.role);
            }
            if (filters?.status) {
                query += ` AND status = $${paramIndex++}`;
                queryParams.push(filters.status);
            }
            if (filters?.search) {
                query += ` AND (name ILIKE $${paramIndex++} OR email ILIKE $${paramIndex++} OR phone ILIKE $${paramIndex++})`;
                queryParams.push(`%${filters.search}%`, `%${filters.search}%`, `%${filters.search}%`);
            }
            // Add ordering and pagination
            query += ` ORDER BY created_at DESC`;
            if (filters?.limit) {
                query += ` LIMIT $${paramIndex++}`;
                queryParams.push(filters.limit);
            }
            if (filters?.offset) {
                query += ` OFFSET $${paramIndex++}`;
                queryParams.push(filters.offset);
            }
            const result = await client.query(query, queryParams);
            this.logger.info(`Retrieved ${result.rows.length} users with filters:`, { filters });
            return result.rows;
        }
        catch (error) {
            this.logger.error('Failed to retrieve users:', error);
            throw new AdminError(`Failed to retrieve users: ${error.message}`);
        }
        finally {
            client.release();
        }
    }
    /**
     * Bans a user with audit logging
     *
     * @param userId - User ID to ban
     * @param reason - Reason for banning
     * @param adminContext - Admin action context
     *
     * @returns Promise resolving when ban is complete
     */
    static async banUser(userId, reason, adminContext) {
        const pool = this.getPool();
        const client = await pool.connect();
        try {
            // Log admin action
            await this.logAdminAction({
                adminId: adminContext.adminId,
                action: 'BAN_USER',
                resource: 'user',
                details: { userId, reason },
            }, client);
            // Update user status to banned
            const query = `
        UPDATE users 
        SET status = 'banned', updated_at = NOW()
        WHERE id = $1
      `;
            await client.query(query, [userId]);
            this.logger.info(`User ${userId} banned by admin ${adminContext.adminId}`, { reason });
        }
        catch (error) {
            this.logger.error('Failed to ban user:', error);
            throw new AdminError(`Failed to ban user: ${error.message}`);
        }
        finally {
            client.release();
        }
    }
    /**
     * Registers a new hospital
     *
     * @param data - Hospital registration data
     * @param adminContext - Admin action context
     *
     * @returns Promise resolving to created hospital
     */
    static async registerHospital(data, adminContext) {
        const pool = this.getPool();
        const client = await pool.connect();
        try {
            // Validate required fields
            if (!data.name || !data.address || !data.latitude || !data.longitude || !data.phone) {
                throw new AdminError('Missing required hospital fields');
            }
            // Log admin action
            await this.logAdminAction({
                adminId: adminContext.adminId,
                action: 'REGISTER_HOSPITAL',
                resource: 'hospital',
                details: { hospitalData: data },
            }, client);
            const query = `
        INSERT INTO hospitals (
          id, name, address, latitude, longitude, phone, email, website,
          emergency_services, is_available, created_at, updated_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, NOW(), NOW())
        RETURNING *
      `;
            const result = await client.query(query, [
                (0, uuid_1.v4)(),
                data.name,
                data.address,
                data.latitude,
                data.longitude,
                data.phone,
                data.email || null,
                data.website || null,
                JSON.stringify(data.emergencyServices || []),
                data.isAvailable || true,
            ]);
            this.logger.info(`Hospital "${data.name}" registered by admin ${adminContext.adminId}`);
            return result.rows[0];
        }
        catch (error) {
            this.logger.error('Failed to register hospital:', error);
            throw new AdminError(`Failed to register hospital: ${error.message}`);
        }
        finally {
            client.release();
        }
    }
    /**
     * Updates hospital availability status
     *
     * @param hospitalId - Hospital ID to update
     * @param isAvailable - New availability status
     * @param adminContext - Admin action context
     *
     * @returns Promise resolving when update is complete
     */
    static async updateHospitalAvailability(hospitalId, isAvailable, adminContext) {
        const pool = this.getPool();
        const client = await pool.connect();
        try {
            // Log admin action
            await this.logAdminAction({
                adminId: adminContext.adminId,
                action: 'UPDATE_HOSPITAL_AVAILABILITY',
                resource: 'hospital',
                details: { hospitalId, isAvailable },
            }, client);
            const query = `
        UPDATE hospitals 
        SET is_available = $1, updated_at = NOW()
        WHERE id = $2
      `;
            await client.query(query, [isAvailable, hospitalId]);
            this.logger.info(`Hospital ${hospitalId} availability updated to ${isAvailable} by admin ${adminContext.adminId}`);
        }
        catch (error) {
            this.logger.error('Failed to update hospital availability:', error);
            throw new AdminError(`Failed to update hospital availability: ${error.message}`);
        }
        finally {
            client.release();
        }
    }
    /**
     * Gets comprehensive system statistics
     *
     * @param adminContext - Admin action context
     *
     * @returns Promise resolving to system statistics
     */
    static async getSystemStats(adminContext) {
        const pool = this.getPool();
        const client = await pool.connect();
        try {
            // Log admin action
            if (adminContext) {
                await this.logAdminAction({
                    adminId: adminContext.adminId,
                    action: 'VIEW_SYSTEM_STATS',
                    resource: 'system',
                }, client);
            }
            // Get total requests
            const totalRequestsQuery = `
        SELECT COUNT(*) as count
        FROM emergency_requests
        WHERE created_at >= NOW() - INTERVAL '30 days'
      `;
            const totalRequestsResult = await client.query(totalRequestsQuery);
            const totalRequests = parseInt(totalRequestsResult.rows[0].count);
            // Get average response time
            const avgResponseTimeQuery = `
        SELECT AVG(EXTRACT(EPOCH FROM (accepted_at - created_at))) / 60 as avg_minutes
        FROM emergency_requests
        WHERE accepted_at IS NOT NULL 
        AND created_at >= NOW() - INTERVAL '30 days'
      `;
            const avgResponseTimeResult = await client.query(avgResponseTimeQuery);
            const averageResponseTime = avgResponseTimeResult.rows[0].avg_minutes || 0;
            // Get resolution rate
            const resolutionRateQuery = `
        SELECT 
          COUNT(CASE WHEN status = 'completed' THEN 1 END) * 100.0 / COUNT(*) as rate
        FROM emergency_requests
        WHERE created_at >= NOW() - INTERVAL '30 days'
      `;
            const resolutionRateResult = await client.query(resolutionRateQuery);
            const resolutionRate = resolutionRateResult.rows[0].rate || 0;
            // Get requests by type
            const requestsByTypeQuery = `
        SELECT type, COUNT(*) as count
        FROM emergency_requests
        WHERE created_at >= NOW() - INTERVAL '30 days'
        GROUP BY type
      `;
            const requestsByTypeResult = await client.query(requestsByTypeQuery);
            const requestsByType = {};
            requestsByTypeResult.rows.forEach(row => {
                requestsByType[row.type] = parseInt(row.count);
            });
            // Get active responders
            const activeRespondersQuery = `
        SELECT COUNT(*) as count
        FROM users
        WHERE role = 'responder' AND status = 'active'
      `;
            const activeRespondersResult = await client.query(activeRespondersQuery);
            const activeResponders = parseInt(activeRespondersResult.rows[0].count);
            // Get registered hospitals
            const registeredHospitalsQuery = `
        SELECT COUNT(*) as count
        FROM hospitals
        WHERE is_available = true
      `;
            const registeredHospitalsResult = await client.query(registeredHospitalsQuery);
            const registeredHospitals = parseInt(registeredHospitalsResult.rows[0].count);
            // Get monthly trend
            const monthlyTrendQuery = `
        SELECT 
          TO_CHAR(created_at, 'YYYY-MM') as month,
          COUNT(*) as requests
        FROM emergency_requests
        WHERE created_at >= NOW() - INTERVAL '12 months'
        GROUP BY TO_CHAR(created_at, 'YYYY-MM')
        ORDER BY month DESC
        LIMIT 12
      `;
            const monthlyTrendResult = await client.query(monthlyTrendQuery);
            const stats = {
                totalRequests,
                averageResponseTime,
                resolutionRate,
                requestsByType,
                activeResponders,
                registeredHospitals,
                monthlyTrend: monthlyTrendResult.rows,
            };
            this.logger.info('System statistics retrieved', stats);
            return stats;
        }
        catch (error) {
            this.logger.error('Failed to get system stats:', error);
            throw new AdminError(`Failed to get system stats: ${error.message}`);
        }
        finally {
            client.release();
        }
    }
    /**
     * Generates a comprehensive system report
     *
     * @param from - Start date for report
     * @param to - End date for report
     * @param format - Report format ('pdf' or 'csv')
     * @param adminContext - Admin action context
     *
     * @returns Promise resolving to report buffer
     */
    static async generateReport(from, to, format, adminContext) {
        try {
            // Log admin action
            if (adminContext) {
                await this.logAdminAction({
                    adminId: adminContext.adminId,
                    action: 'GENERATE_REPORT',
                    resource: 'report',
                    details: { from, to, format },
                });
            }
            // Generate report using ReportGenerator
            const reportBuffer = await report_generator_service_1.ReportGenerator.createReport({
                from,
                to,
                format,
                includeCharts: true,
                includeDetails: true,
            });
            this.logger.info(`Report generated: ${format} from ${from.toISOString()} to ${to.toISOString()}`);
            return reportBuffer;
        }
        catch (error) {
            this.logger.error('Failed to generate report:', error);
            throw new AdminError(`Failed to generate report: ${error.message}`);
        }
    }
    /**
     * Logs admin action for audit trail
     *
     * @param context - Admin action context
     * @param client - Database client for transaction
     *
     * @returns Promise resolving when log is recorded
     */
    static async logAdminAction(context, transactionClient) {
        const isLocalClient = !transactionClient;
        const client = transactionClient || await this.getPool().connect();
        try {
            const query = `
        INSERT INTO audit_logs (
          id, user_id, action, resource, timestamp, ip_address, user_agent, details
        ) VALUES ($1, $2, $3, $4, NOW(), $5, $6, $7)
      `;
            await client.query(query, [
                (0, uuid_1.v4)(),
                context.adminId,
                context.action,
                context.resource,
                context.details ? JSON.stringify(context.details) : null,
                context.adminId, // Using adminId as IP address placeholder for now
                'Admin Dashboard', // User agent placeholder
            ]);
        }
        catch (error) {
            this.logger.error('Failed to log admin action:', error);
        }
        finally {
            if (isLocalClient)
                client.release();
        }
    }
    /**
     * Gets database pool instance
     */
    static getPool() {
        return new pg_1.Pool({
            connectionString: process.env.DATABASE_URL,
            ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
            max: 20,
            idleTimeoutMillis: 30000,
            connectionTimeoutMillis: 2000,
        });
    }
    /**
     * Checks if user has admin permissions
     *
     * @param userId - User ID to check
     * @param client - Database client
     *
     * @returns Promise resolving to boolean
     */
    static async checkAdminPermissions(userId, client) {
        try {
            const query = `
        SELECT role FROM users WHERE id = $1 AND status = 'active'
      `;
            const result = await client.query(query, [userId]);
            return result.rows.length > 0 && result.rows[0].role === 'admin';
        }
        catch (error) {
            this.logger.error('Failed to check admin permissions:', error);
            return false;
        }
    }
}
exports.AdminService = AdminService;
