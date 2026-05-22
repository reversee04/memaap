/**
 * emergency.routes.ts
 */

import { Router, Request, Response, NextFunction } from 'express';
import { AuthService } from '../services/auth.service';
import { EmergencyRequestRepository } from '../repositories/emergency-request.repository';

const router = Router();

// Extend Express Locals typing
interface AuthenticatedUser {
  userId: string;
  role?: string;
}

// ── JWT guard ────────────────────────────────────────────────────────────────
async function requireAuth(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const header = req.headers.authorization;

  if (!header || !header.startsWith('Bearer ')) {
    res.status(401).json({
      message: 'Authorization token required',
    });
    return;
  }

  try {
    const token = header.split(' ')[1];

    if (!token) {
      res.status(401).json({
        message: 'Invalid authorization token',
      });
      return;
    }

    const payload = await AuthService.verifyToken(token);

    res.locals.user = payload as AuthenticatedUser;

    next();
  } catch (error) {
    console.error('Auth error:', error);

    res.status(401).json({
      message: 'Invalid or expired token',
    });
  }
}

// ── POST /api/emergency/create ───────────────────────────────────────────────
router.post('/create', requireAuth, (req: Request, res: Response): void => {
  try {
    const { type, description, latitude, longitude, address } = req.body;

    const { userId } = res.locals.user as AuthenticatedUser;

    if (!type || latitude == null || longitude == null) {
      res.status(400).json({
        message: 'type, latitude and longitude are required',
      });
      return;
    }

    const emergency = EmergencyRequestRepository.create({
      userId,
      type,
      description,
      latitude,
      longitude,
      address,
    });

    res.status(201).json({ emergency });
  } catch (error) {
    console.error('Create emergency error:', error);

    res.status(500).json({
      message: 'Failed to create emergency request',
    });
  }
});

// ── GET /api/emergency/pending ───────────────────────────────────────────────
router.get('/pending', requireAuth, (_req: Request, res: Response): void => {
  try {
    const emergencies = EmergencyRequestRepository.findPending();

    res.json({ emergencies });
  } catch (error) {
    console.error('Get pending error:', error);

    res.status(500).json({
      message: 'Failed to fetch pending requests',
    });
  }
});

// ── GET /api/emergency/user/:userId ─────────────────────────────────────────
router.get<{ userId: string }>('/user/:userId', requireAuth, (req: Request<{ userId: string }>, res: Response): void => {
    try {
      const { status } = req.query as { status?: string };

      const emergencies =
        EmergencyRequestRepository.findByUser(
          req.params.userId,
          status
        );

      res.json({ emergencies });
    } catch (error) {
      console.error('Get user emergencies error:', error);

      res.status(500).json({
        message: 'Failed to fetch user requests',
      });
    }
  }
);

// ── GET /api/emergency/responder/:responderId ────────────────────────────────
router.get<{ responderId: string }>('/responder/:responderId', requireAuth, (req: Request<{ responderId: string }>, res: Response): void => {
    try {
      const emergencies =
        EmergencyRequestRepository.findByResponder(
          req.params.responderId
        );

      res.json({ emergencies });
    } catch (error) {
      console.error('Get responder emergencies error:', error);

      res.status(500).json({
        message: 'Failed to fetch responder requests',
      });
    }
  }
);

// ── GET /api/emergency/:id ───────────────────────────────────────────────────
router.get<{ id: string }>('/:id', requireAuth, (req: Request<{ id: string }>, res: Response): void => {
  try {
    const emergency =
      EmergencyRequestRepository.findById(req.params.id);

    if (!emergency) {
      res.status(404).json({
        message: 'Emergency request not found',
      });
      return;
    }

    res.json({ emergency });
  } catch (error) {
    console.error('Get emergency error:', error);

    res.status(500).json({
      message: 'Failed to fetch emergency request',
    });
  }
});

// ── PUT /api/emergency/:id/accept ────────────────────────────────────────────
router.put<{ id: string }>('/:id/accept', requireAuth, async (req: Request<{ id: string }>, res: Response): Promise<void> => {
  try {
    const { userId, role } =
      res.locals.user as AuthenticatedUser;

    if (!role || (role !== 'responder' && role !== 'admin')) {
      res.status(403).json({
        message: 'Only responders can accept requests',
      });
      return;
    }

    const emergency =
      EmergencyRequestRepository.assignResponder(
        req.params.id,
        userId
      );

    if (!emergency) {
      res.status(404).json({
        message: 'Emergency not found or already accepted',
      });
      return;
    }

    res.json({ emergency });
  } catch (error) {
    console.error('Accept emergency error:', error);

    res.status(500).json({
      message: 'Failed to accept emergency request',
    });
  }
});

// ── PUT /api/emergency/:id/status ────────────────────────────────────────────
router.put<{ id: string }>('/:id/status', requireAuth, (req: Request<{ id: string }>, res: Response): void => {
  try {
    const { status } = req.body;

    const validStatuses = [
      'pending',
      'accepted',
      'in_progress',
      'completed',
      'cancelled',
    ];

    if (!status || !validStatuses.includes(status)) {
      res.status(400).json({
        message: `status must be one of: ${validStatuses.join(', ')}`,
      });
      return;
    }

    const emergency =
      EmergencyRequestRepository.updateStatus(
        req.params.id,
        status
      );

    if (!emergency) {
      res.status(404).json({
        message: 'Emergency request not found',
      });
      return;
    }

    res.json({ emergency });
  } catch (error) {
    console.error('Update status error:', error);

    res.status(500).json({
      message: 'Failed to update status',
    });
  }
});

// ── DELETE /api/emergency/:id ────────────────────────────────────────────────
router.delete<{ id: string }>('/:id', requireAuth, (req: Request<{ id: string }>, res: Response): void => {
  try {
    const emergency =
      EmergencyRequestRepository.updateStatus(
        req.params.id,
        'cancelled'
      );

    if (!emergency) {
      res.status(404).json({
        message: 'Emergency request not found',
      });
      return;
    }

    res.json({ emergency });
  } catch (error) {
    console.error('Cancel emergency error:', error);

    res.status(500).json({
      message: 'Failed to cancel emergency request',
    });
  }
});

export default router;