import { v4 as uuidv4 } from 'uuid';
import db from '../config/database';

const ACTIVE_CALL_STATUSES = ['ringing', 'active'] as const;

export type CallEndReason = 'hangup' | 'timeout' | 'network_error' | 'rejected';

export class CallSessionRepository {
  static findById(id: string): any {
    return db.prepare('SELECT * FROM call_sessions WHERE id = ?').get(id);
  }

  static findLatestByEmergencyId(emergencyId: string): any {
    return db.prepare(
      'SELECT * FROM call_sessions WHERE emergency_id = ? ORDER BY started_at DESC LIMIT 1'
    ).get(emergencyId);
  }

  static findActiveByEmergencyId(emergencyId: string): any {
    return db.prepare(
      "SELECT * FROM call_sessions WHERE emergency_id = ? AND status IN ('ringing', 'active') ORDER BY started_at DESC LIMIT 1"
    ).get(emergencyId);
  }

  static getEmergencyParticipants(emergencyId: string): any {
    return db.prepare(
      'SELECT id, user_id, responder_id, status FROM emergency_requests WHERE id = ?'
    ).get(emergencyId);
  }

  static canUserParticipateInEmergency(emergencyId: string, userId: string): boolean {
    const emergency = this.getEmergencyParticipants(emergencyId);
    if (!emergency) return false;

    if (!['accepted', 'in_progress'].includes(emergency.status)) {
      return false;
    }

    return emergency.user_id === userId || emergency.responder_id === userId;
  }

  static resolveCalleeForEmergency(emergencyId: string, callerUserId: string): string | null {
    const emergency = this.getEmergencyParticipants(emergencyId);
    if (!emergency) return null;

    if (!['accepted', 'in_progress'].includes(emergency.status)) {
      return null;
    }

    if (emergency.user_id === callerUserId && emergency.responder_id) {
      return emergency.responder_id;
    }

    if (emergency.responder_id === callerUserId && emergency.user_id) {
      return emergency.user_id;
    }

    return null;
  }

  static createSession(emergencyId: string, callerUserId: string, calleeUserId: string): any {
    const id = uuidv4();

    db.prepare(`
      INSERT INTO call_sessions
        (id, emergency_id, caller_user_id, callee_user_id, status, started_at)
      VALUES (?, ?, ?, ?, 'ringing', datetime('now'))
    `).run(id, emergencyId, callerUserId, calleeUserId);

    this.logEvent(id, 'call_started', { emergencyId, callerUserId, calleeUserId });
    return this.findById(id);
  }

  static markAccepted(callSessionId: string): any {
    db.prepare(`
      UPDATE call_sessions
      SET status = 'active', answered_at = datetime('now')
      WHERE id = ? AND status = 'ringing'
    `).run(callSessionId);

    this.logEvent(callSessionId, 'call_accepted');
    return this.findById(callSessionId);
  }

  static markRejected(callSessionId: string): any {
    db.prepare(`
      UPDATE call_sessions
      SET status = 'rejected', ended_at = datetime('now'), end_reason = 'rejected'
      WHERE id = ? AND status IN ('ringing', 'active')
    `).run(callSessionId);

    this.logEvent(callSessionId, 'call_rejected');
    return this.findById(callSessionId);
  }

  static markEnded(callSessionId: string, reason: CallEndReason = 'hangup'): any {
    db.prepare(
      "UPDATE call_sessions SET status = 'ended', ended_at = datetime('now'), end_reason = ? WHERE id = ? AND status IN ('ringing', 'active')"
    ).run(reason, callSessionId);

    this.logEvent(callSessionId, 'call_ended', { reason });
    return this.findById(callSessionId);
  }

  static isUserInCallSession(callSessionId: string, userId: string): boolean {
    const row = db.prepare(
      'SELECT id FROM call_sessions WHERE id = ? AND (caller_user_id = ? OR callee_user_id = ?)'
    ).get(callSessionId, userId, userId);

    return !!row;
  }

  static getCounterpartyUserId(callSessionId: string, userId: string): string | null {
    const row = this.findById(callSessionId);
    if (!row) return null;

    if (row.caller_user_id === userId) return row.callee_user_id;
    if (row.callee_user_id === userId) return row.caller_user_id;
    return null;
  }

  static hasActiveCallForEmergency(emergencyId: string): boolean {
    const row = db.prepare(
      "SELECT id FROM call_sessions WHERE emergency_id = ? AND status IN ('ringing', 'active') LIMIT 1"
    ).get(emergencyId);

    return !!row;
  }

  static markMissed(callSessionId: string): any {
    db.prepare(
      "UPDATE call_sessions SET status = 'missed', ended_at = datetime('now'), end_reason = 'timeout' WHERE id = ? AND status = 'ringing'"
    ).run(callSessionId);

    this.logEvent(callSessionId, 'call_missed');
    return this.findById(callSessionId);
  }

  private static logEvent(callSessionId: string, eventType: string, payload?: Record<string, any>): void {
    const id = uuidv4();

    db.prepare(
      'INSERT INTO call_events (id, call_session_id, event_type, event_payload, created_at) VALUES (?, ?, ?, ?, datetime(\'now\'))'
    ).run(id, callSessionId, eventType, payload ? JSON.stringify(payload) : null);
  }
}
