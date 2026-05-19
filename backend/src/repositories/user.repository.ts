import db from '../config/database';

export class UserRepository {
  /** Fetch a user by ID (no password_hash). */
  static findById(userId: string): any {
    return db.prepare(
      'SELECT id, name, phone, email, role, status, created_at, updated_at FROM users WHERE id = ?'
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
    let sql = `SELECT id, name, phone, email, role, status, created_at, updated_at
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
}
