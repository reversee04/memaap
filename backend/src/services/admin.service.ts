import { Pool, PoolClient } from 'pg';
import { v4 as uuidv4 } from 'uuid';
import * as winston from 'winston';
import { UserRepository } from '../repositories/user.repository';
import { HospitalRepository } from '../repositories/hospital.repository';
import { EmergencyRequestRepository } from '../repositories/emergency-request.repository';
import { ReportGenerator } from './report-generator.service';
import { 
  HospitalDTO, 
  UserFilters, 
  SystemStats, 
  ReportOptions, 
  AuditLog, 
  AdminActionContext 
} from '../dto/admin.dto';

// Custom error classes
export class AdminError extends Error {
  constructor(message: string, public statusCode?: number) {
    super(message);
    this.name = 'AdminError';
  }
}

export class InsufficientPermissionsError extends AdminError {
  constructor(message: string) {
    super(message, 403);
    this.name = 'InsufficientPermissionsError';
  }
}

/**
 * Service class for system-admin operations
 * 
 * Provides user management, hospital registration, request monitoring,
 * and system reporting with full audit logging for Mobile Emergency Medical Assistance App.
 */
export class AdminService {
  private static readonly logger = winston.createLogger({
    level: 'info',
    format: winston.format.combine(
      winston.format.timestamp(),
      winston.format.json()
    ),
  });

  /**
   * Gets all users with optional filtering
   * 
   * @param filters - Optional filters for role, status, search, pagination
   * @param adminContext - Admin action context for audit logging
   * 
   * @returns Promise resolving to array of users
   */
  static async getAllUsers(
    filters?: UserFilters,
    adminContext?: AdminActionContext
  ): Promise<any[]> {
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
      const queryParams: any[] = [];
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
      
    } catch (error: any) {
      this.logger.error('Failed to retrieve users:', error);
      throw new AdminError(`Failed to retrieve users: ${error.message}`);
    } finally {
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
  static async banUser(
    userId: string,
    reason: string,
    adminContext: AdminActionContext
  ): Promise<void> {
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
      
    } catch (error: any) {
      this.logger.error('Failed to ban user:', error);
      throw new AdminError(`Failed to ban user: ${error.message}`);
    } finally {
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
  static async registerHospital(
    data: HospitalDTO,
    adminContext: AdminActionContext
  ): Promise<any> {
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
        uuidv4(),
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
      
    } catch (error: any) {
      this.logger.error('Failed to register hospital:', error);
      throw new AdminError(`Failed to register hospital: ${error.message}`);
    } finally {
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
  static async updateHospitalAvailability(
    hospitalId: string,
    isAvailable: boolean,
    adminContext: AdminActionContext
  ): Promise<void> {
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
      
    } catch (error: any) {
      this.logger.error('Failed to update hospital availability:', error);
      throw new AdminError(`Failed to update hospital availability: ${error.message}`);
    } finally {
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
  static async getSystemStats(adminContext?: AdminActionContext): Promise<SystemStats> {
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
      const requestsByType: Record<string, number> = {};
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

      const stats: SystemStats = {
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
      
    } catch (error: any) {
      this.logger.error('Failed to get system stats:', error);
      throw new AdminError(`Failed to get system stats: ${error.message}`);
    } finally {
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
  static async generateReport(
    from: Date,
    to: Date,
    format: 'pdf' | 'csv',
    adminContext?: AdminActionContext
  ): Promise<Buffer> {
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
      const reportBuffer = await ReportGenerator.createReport({
        from,
        to,
        format,
        includeCharts: true,
        includeDetails: true,
      });

      this.logger.info(`Report generated: ${format} from ${from.toISOString()} to ${to.toISOString()}`);
      
      return reportBuffer;
      
    } catch (error: any) {
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
  private static async logAdminAction(
    context: AdminActionContext,
    transactionClient?: PoolClient
  ): Promise<void> {
    const isLocalClient = !transactionClient;
    const client = transactionClient || await this.getPool().connect();
    try {
      const query = `
        INSERT INTO audit_logs (
          id, user_id, action, resource, timestamp, ip_address, user_agent, details
        ) VALUES ($1, $2, $3, $4, NOW(), $5, $6, $7)
      `;

      await client.query(query, [
        uuidv4(),
        context.adminId,
        context.action,
        context.resource,
        context.details ? JSON.stringify(context.details) : null,
        context.adminId, // Using adminId as IP address placeholder for now
        'Admin Dashboard', // User agent placeholder
      ]);

    } catch (error: any) {
      this.logger.error('Failed to log admin action:', error);
    } finally {
      if (isLocalClient) client.release();
    }
  }

  /**
   * Gets database pool instance
   */
  private static getPool(): Pool {
    return new Pool({
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
  private static async checkAdminPermissions(
    userId: string,
    client: PoolClient
  ): Promise<boolean> {
    try {
      const query = `
        SELECT role FROM users WHERE id = $1 AND status = 'active'
      `;
      const result = await client.query(query, [userId]);
      
      return result.rows.length > 0 && result.rows[0].role === 'admin';
    } catch (error: any) {
      this.logger.error('Failed to check admin permissions:', error);
      return false;
    }
  }
}
