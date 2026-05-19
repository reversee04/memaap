/**
 * users.routes.ts
 *
 * GET  /api/users/profile  — fetch the logged-in user's profile
 * PUT  /api/users/profile  — update name / email
 *
 * All routes require a valid Bearer JWT (requireAuth middleware).
 */

import { Router, Request, Response, NextFunction } from 'express';
import db from '../config/database';
import { AuthService, AuthError } from '../services/auth.service';

const router = Router();

// ── JWT guard ────────────────────────────────────────────────────────────────

async function requireAuth(req: Request, res: Response, next: NextFunction) {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    return res.status(401).json({ message: 'Authorization token required' });
  }
  try {
    const payload = await AuthService.verifyToken(header.split(' ')[1]);
    res.locals.user = payload;
    return next();
  } catch {
    return res.status(401).json({ message: 'Invalid or expired token' });
  }
}

// ── GET /api/users/profile ───────────────────────────────────────────────────

router.get('/profile', requireAuth, (req: Request, res: Response) => {
  const { userId } = res.locals.user;

  const user = db.prepare(
    `SELECT id, name, phone, email, role, status, created_at, updated_at
     FROM users WHERE id = ? AND status != 'banned'`
  ).get(userId) as any;

  if (!user) return res.status(404).json({ message: 'User not found' });

  return res.json({ user });
});

// ── PUT /api/users/profile ───────────────────────────────────────────────────

router.put('/profile', requireAuth, (req: Request, res: Response) => {
  const { userId } = res.locals.user;
  const { name, email } = req.body;

  if (!name && !email) {
    return res.status(400).json({ message: 'Provide at least name or email' });
  }

  const sets: string[] = ["updated_at = datetime('now')"];
  const vals: any[] = [];

  if (name)  { sets.push('name = ?');  vals.push(name.trim());  }
  if (email) { sets.push('email = ?'); vals.push(email.trim()); }
  vals.push(userId);

  db.prepare(`UPDATE users SET ${sets.join(', ')} WHERE id = ?`).run(...vals);

  const user = db.prepare(
    'SELECT id, name, phone, email, role, status, created_at, updated_at FROM users WHERE id = ?'
  ).get(userId);

  return res.json({ user });
});

export default router;
