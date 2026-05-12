/// Data Transfer Objects for admin operations
/// 
/// Used for data validation and transfer in Mobile Emergency Medical Assistance App backend.

/// Hospital registration DTO
export interface HospitalDTO {
  name: string;
  address: string;
  latitude: number;
  longitude: number;
  phone: string;
  email?: string;
  website?: string;
  emergencyServices: string[];
  isAvailable: boolean;
}

/// User filters for admin operations
export interface UserFilters {
  role?: 'patient' | 'responder' | 'admin';
  status?: 'active' | 'inactive' | 'banned';
  search?: string;
  limit?: number;
  offset?: number;
}

/// System statistics interface
export interface SystemStats {
  totalRequests: number;
  averageResponseTime: number; // in minutes
  resolutionRate: number; // percentage
  requestsByType: Record<string, number>;
  activeResponders: number;
  registeredHospitals: number;
  monthlyTrend: Array<{
    month: string;
    requests: number;
  }>;
}

/// Report generation options
export interface ReportOptions {
  from: Date;
  to: Date;
  format: 'pdf' | 'csv';
  includeCharts?: boolean;
  includeDetails?: boolean;
}

/// Audit log entry
export interface AuditLog {
  id: string;
  userId: string;
  action: string;
  resource: string;
  timestamp: Date;
  ipAddress?: string;
  userAgent?: string;
  details?: Record<string, any>;
}

/// Admin action context for audit logging
export interface AdminActionContext {
  adminId: string;
  action: string;
  resource: string;
  details?: Record<string, any>;
}
