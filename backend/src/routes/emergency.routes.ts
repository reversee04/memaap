/**
 * emergency.routes.ts
 *
 * Endpoints used by Flutter's EmergencyRepository:
 *
 *  POST   /api/emergency/create          — patient creates request
 *  GET    /api/emergency/pending         — responder sees all pending requests
 *  GET    /api/emergency/:id             — get single request
 *  GET    /api/emergency/user/:userId    — patient's own requests
 *  GET    /api/emergency/responder/:id   — responder's assigned requests
 *  PUT    /api/emergency/:id/status      — update status
 *  PUT    /api/emergency/:id/accept      — responder accepts (assigns themselves)
 *  DELETE /api/emergency/:id             — cancel request
 */

import { Router, Request, Response, NextFunction } from 'express';
import { AuthService } from '../services/auth.service';
import { EmergencyRequestRepository } from '../repositories/emergency-request.repository';

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

// ── POST /api/emergency/create ───────────────────────────────────────────────

router.post('/create', requireAuth, (req: Request, res: Response) => {
  try {
    const { type, description, latitude, longitude, address } = req.body;
    const { userId } = res.locals.user;

    if (!type || latitude === undefined || longitude === undefined) {
      return res.status(400).json({ message: 'type, latitude and longitude are required' });
    }

    const emergency = EmergencyRequestRepository.create({
      userId, type, description, latitude, longitude, address,
    });

    return res.status(201).json({ emergency });
  } catch (err: any) {
    console.error('Create emergency error:', err);
    return res.status(500).json({ message: 'Failed to create emergency request' });
  }
});

// ── GET /api/emergency/pending ───────────────────────────────────────────────
// Responder-facing: all requests waiting for someone to accept

router.get('/pending', requireAuth, (req: Request, res: Response) => {
  try {
    const emergencies = EmergencyRequestRepository.findPending();
    return res.json({ emergencies });
  } catch (err: any) {
    console.error('Get pending error:', err);
    return res.status(500).json({ message: 'Failed to fetch pending requests' });
  }
});

// ── GET /api/emergency/user/:userId ─────────────────────────────────────────

router.get('/user/:userId', requireAuth, (req: Request, res: Response) => {
  try {
    const { status } = req.query as { status?: string };
    const emergencies = EmergencyRequestRepository.findByUser(req.params.userId, status);
    return res.json({ emergencies });
  } catch (err: any) {
    console.error('Get user emergencies error:', err);
    return res.status(500).json({ message: 'Failed to fetch user requests' });
  }
});

// ── GET /api/emergency/responder/:responderId ────────────────────────────────

router.get('/responder/:responderId', requireAuth, (req: Request, res: Response) => {
  try {
    const emergencies = EmergencyRequestRepository.findByResponder(req.params.responderId);
    return res.json({ emergencies });
  } catch (err: any) {
    console.error('Get responder emergencies error:', err);
    return res.status(500).json({ message: 'Failed to fetch responder requests' });
  }
});

// ── GET /api/emergency/:id ───────────────────────────────────────────────────

router.get('/:id', requireAuth, (req: Request, res: Response) => {
  try {
    const emergency = EmergencyRequestRepository.findById(req.params.id);
    if (!emergency) return res.status(404).json({ message: 'Emergency request not found' });
    return res.json({ emergency });
  } catch (err: any) {
    console.error('Get emergency error:', err);
    return res.status(500).json({ message: 'Failed to fetch emergency request' });
  }
});

// ── PUT /api/emergency/:id/accept ────────────────────────────────────────────
// Responder accepts a pending request (assigns themselves)

router.put('/:id/accept', requireAuth, (req: Request, res: Response) => {
  try {
    const { userId, role } = res.locals.user;

    if (role !== 'responder' && role !== 'admin') {
      return res.status(403).json({ message: 'Only responders can accept requests' });
    }

    const emergency = EmergencyRequestRepository.assignResponder(req.params.id, userId);
    if (!emergency) return res.status(404).json({ message: 'Emergency not found or already accepted' });

    return res.json({ emergency });
  } catch (err: any) {
    console.error('Accept emergency error:', err);
    return res.status(500).json({ message: 'Failed to accept emergency request' });
  }
});

// ── PUT /api/emergency/:id/status ────────────────────────────────────────────

router.put('/:id/status', requireAuth, (req: Request, res: Response) => {
  try {
    const { status } = req.body;
    const validStatuses = ['pending', 'accepted', 'in_progress', 'completed', 'cancelled'];

    if (!status || !validStatuses.includes(status)) {
      return res.status(400).json({ message: `status must be one of: ${validStatuses.join(', ')}` });
    }

    const emergency = EmergencyRequestRepository.updateStatus(req.params.id, status);
    if (!emergency) return res.status(404).json({ message: 'Emergency request not found' });

    return res.json({ emergency });
  } catch (err: any) {
    console.error('Update status error:', err);
    return res.status(500).json({ message: 'Failed to update status' });
  }
});

// ── DELETE /api/emergency/:id ────────────────────────────────────────────────

router.delete('/:id', requireAuth, (req: Request, res: Response) => {
  try {
    const emergency = EmergencyRequestRepository.updateStatus(req.params.id, 'cancelled');
    if (!emergency) return res.status(404).json({ message: 'Emergency request not found' });
    return res.json({ emergency });
  } catch (err: any) {
    console.error('Cancel emergency error:', err);
    return res.status(500).json({ message: 'Failed to cancel emergency request' });
  }
});

export default router;
