import db from '../config/database';

export type ResponderAvailability =
  | 'available'
  | 'busy'
  | 'offline'
  | 'on_break'
  | 'in_transit';

export class UserRepository {
  /** Fetch a user by ID (no password_hash). */
  static findById(userId: string): any {
    return db.prepare(
      'SELECT id, name, phone, email, role, status, availability, last_latitude, last_longitude, last_location_updated_at, max_active_assignments, created_at, updated_at FROM users WHERE id = ?'
    ).get(userId);
  }

  /** Set a user's status (active | inactive | banned). */
  static updateStatus(userId: string, status: string): void {
    db.prepare(
      "UPDATE users SET status = ?, updated_at = datetime('now') WHERE id = ?"
    ).run(status, userId);
  }

  /** Fetch paginated users with optional filters. */
  static findAll(opts: {
    role?: string;
    status?: string;
    search?: string;
    limit?: number;
    offset?: number;
  } = {}): any[] {
    let sql = `SELECT id, name, phone, email, role, status, availability, last_latitude, last_longitude, last_location_updated_at, max_active_assignments, created_at, updated_at
               FROM users WHERE 1=1`;
    const params: any[] = [];

    if (opts.role)   { sql += ' AND role = ?';   params.push(opts.role);   }
    if (opts.status) { sql += ' AND status = ?'; params.push(opts.status); }
    if (opts.search) {
      sql += ' AND (name LIKE ? OR phone LIKE ? OR email LIKE ?)';
      const like = `%${opts.search}%`;
      params.push(like, like, like);
    }

    sql += ' ORDER BY created_at DESC';
    if (opts.limit)  { sql += ' LIMIT ?';  params.push(opts.limit);  }
    if (opts.offset) { sql += ' OFFSET ?'; params.push(opts.offset); }

    return db.prepare(sql).all(...params);
  }

  /** Update responder availability and optionally last known location. */
  static updateResponderAvailability(
    userId: string,
    availability: ResponderAvailability,
    latitude?: number,
    longitude?: number,
  ): any {
    if (latitude != null && longitude != null) {
      db.prepare(
        "UPDATE users SET availability = ?, last_latitude = ?, last_longitude = ?, last_location_updated_at = datetime('now'), updated_at = datetime('now') WHERE id = ? AND role = 'responder'"
      ).run(availability, latitude, longitude, userId);
    } else {
      db.prepare(
        "UPDATE users SET availability = ?, updated_at = datetime('now') WHERE id = ? AND role = 'responder'"
      ).run(availability, userId);
    }

    return this.findById(userId);
  }

  /** Get responders who can currently receive a new assignment. */
  static findAssignableResponders(excludedResponderIds: string[] = []): any[] {
    const placeholders = excludedResponderIds.map(() => '?').join(', ');
    const exclusionSql = excludedResponderIds.length > 0
      ? ` AND u.id NOT IN (${placeholders})`
      : '';

    const sql = `
      SELECT
        u.id,
        u.name,
        u.phone,
        u.availability,
        u.last_latitude,
        u.last_longitude,
        COALESCE(u.max_active_assignments, 2) AS max_active_assignments,
        COALESCE(active_assignments.active_count, 0) AS active_assignments
      FROM users u
      LEFT JOIN (
        SELECT responder_id, COUNT(*) AS active_count
        FROM emergency_requests
        WHERE responder_id IS NOT NULL
          AND status IN ('accepted', 'in_progress')
        GROUP BY responder_id
      ) active_assignments ON active_assignments.responder_id = u.id
      WHERE u.role = 'responder'
        AND u.status = 'active'
        AND u.availability = 'available'
        AND u.last_latitude IS NOT NULL
        AND u.last_longitude IS NOT NULL
        ${exclusionSql}
      ORDER BY u.updated_at DESC
    `;

    const responders = db.prepare(sql).all(...excludedResponderIds) as any[];
    return responders.filter((responder) => {
      const active = Number(responder.active_assignments ?? 0);
      const maxActive = Number(responder.max_active_assignments ?? 2);
      return active < maxActive;
    });
  }
}
