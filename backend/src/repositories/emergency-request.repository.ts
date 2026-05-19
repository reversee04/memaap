import db from '../config/database';
import { v4 as uuidv4 } from 'uuid';

export class EmergencyRequestRepository {
  /** Create a new emergency request. */
  static create(data: {
    userId: string; type: string; description?: string;
    latitude: number; longitude: number; address?: string;
  }): any {
    const id = uuidv4();
    db.prepare(`
      INSERT INTO emergency_requests
        (id, user_id, type, description, latitude, longitude, address,
         status, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', datetime('now'), datetime('now'))
    `).run(
      id, data.userId, data.type,
      data.description || null,
      data.latitude, data.longitude,
      data.address || null,
    );
    return this.findById(id);
  }

  /** Get a single request by ID. */
  static findById(id: string): any {
    return db.prepare('SELECT * FROM emergency_requests WHERE id = ?').get(id);
  }

  /** Get all requests for a patient (optionally filter by status). */
  static findByUser(userId: string, status?: string): any[] {
    if (status) {
      return db.prepare(
        'SELECT * FROM emergency_requests WHERE user_id = ? AND status = ? ORDER BY created_at DESC'
      ).all(userId, status);
    }
    return db.prepare(
      'SELECT * FROM emergency_requests WHERE user_id = ? ORDER BY created_at DESC'
    ).all(userId);
  }

  /** Get all pending requests — used by the responder dashboard. */
  static findPending(): any[] {
    return db.prepare(
      "SELECT er.*, u.name as patient_name, u.phone as patient_phone " +
      "FROM emergency_requests er " +
      "JOIN users u ON er.user_id = u.id " +
      "WHERE er.status = 'pending' " +
      "ORDER BY er.created_at ASC"
    ).all();
  }

  /** Get all requests assigned to a specific responder. */
  static findByResponder(responderId: string): any[] {
    return db.prepare(
      "SELECT er.*, u.name as patient_name, u.phone as patient_phone " +
      "FROM emergency_requests er " +
      "JOIN users u ON er.user_id = u.id " +
      "WHERE er.responder_id = ? " +
      "ORDER BY er.created_at DESC"
    ).all(responderId);
  }

  /** Update the status of a request. */
  static updateStatus(id: string, status: string): any {
    db.prepare(
      "UPDATE emergency_requests SET status = ?, updated_at = datetime('now') WHERE id = ?"
    ).run(status, id);

    if (status === 'accepted') {
      db.prepare(
        "UPDATE emergency_requests SET accepted_at = datetime('now') WHERE id = ?"
      ).run(id);
    }
    if (status === 'completed') {
      db.prepare(
        "UPDATE emergency_requests SET completed_at = datetime('now') WHERE id = ?"
      ).run(id);
    }

    return this.findById(id);
  }

  /** Assign a responder to a request (accept it). */
  static assignResponder(requestId: string, responderId: string): any {
    db.prepare(`
      UPDATE emergency_requests
      SET responder_id = ?, status = 'accepted', accepted_at = datetime('now'),
          updated_at = datetime('now')
      WHERE id = ? AND status = 'pending'
    `).run(responderId, requestId);
    return this.findById(requestId);
  }

  /** Get requests within a date range. */
  static findByDateRange(from: Date, to: Date): any[] {
    return db.prepare(
      'SELECT * FROM emergency_requests WHERE created_at >= ? AND created_at <= ? ORDER BY created_at DESC'
    ).all(from.toISOString(), to.toISOString());
  }
}
