/**
 * emergency.routes.ts
 */

import { Router, Request, Response, NextFunction } from 'express';
import { AuthService } from '../services/auth.service';
import { EmergencyRequestRepository } from '../repositories/emergency-request.repository';
import { AssignmentService } from '../services/assignment.service';
import { io } from '../index';

const router = Router();

// Extend Express Locals typing
interface AuthenticatedUser {
  userId: string;
  role?: string;
}

type ResponderAvailability =
  | 'available'
  | 'busy'
  | 'offline'
  | 'on_break'
  | 'in_transit';

function isValidAvailability(value: string): value is ResponderAvailability {
  return ['available', 'busy', 'offline', 'on_break', 'in_transit'].includes(value);
}

function broadcastEmergencyEvent(event: string, emergency: any, extra: Record<string, any> = {}): void {
  io.to('responders_all').emit(event, {
    emergency,
    ...extra,
    timestamp: new Date().toISOString(),
  });

  io.to(`request_${emergency.id}`).emit(event, {
    emergency,
    ...extra,
    timestamp: new Date().toISOString(),
  });

  if (emergency.responder_id) {
    io.to(`responder_${emergency.responder_id}`).emit(event, {
      emergency,
      ...extra,
      timestamp: new Date().toISOString(),
    });
  }
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
    const { type, description, latitude, longitude, address, severity } = req.body;

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
      severity: severity || 'urgent',
    });

    const assignment = AssignmentService.assignClosestResponder(emergency.id);

    broadcastEmergencyEvent('emergency:new', assignment.emergency, {
      autoAssigned: assignment.assignedResponder != null,
      assignment: assignment.assignedResponder
        ? {
            responderId: assignment.assignedResponder.id,
            responderName: assignment.assignedResponder.name,
            responderPhone: assignment.assignedResponder.phone,
            distanceKm: assignment.distanceKm,
          }
        : null,
    });

    res.status(201).json({
      emergency: assignment.emergency,
      autoAssigned: assignment.assignedResponder != null,
      assignment: assignment.assignedResponder
        ? {
            responderId: assignment.assignedResponder.id,
            responderName: assignment.assignedResponder.name,
            responderPhone: assignment.assignedResponder.phone,
            distanceKm: assignment.distanceKm,
          }
        : null,
    });
  } catch (error) {
    console.error('Create emergency error:', error);

    res.status(500).json({
      message: 'Failed to create emergency request',
    });
  }
});

// ── PUT /api/emergency/responders/:responderId/availability ────────────────
router.put<{ responderId: string }>('/responders/:responderId/availability', requireAuth, (req: Request<{ responderId: string }>, res: Response): void => {
  try {
    const { userId, role } = res.locals.user as AuthenticatedUser;
    const { responderId } = req.params;
    const { availability, latitude, longitude } = req.body as {
      availability?: string;
      latitude?: number;
      longitude?: number;
    };

    if (!role || (role !== 'responder' && role !== 'admin')) {
      res.status(403).json({
        message: 'Only responders or admins can update responder availability',
      });
      return;
    }

    if (role === 'responder' && userId !== responderId) {
      res.status(403).json({
        message: 'Responders can only update their own availability',
      });
      return;
    }

    if (!availability || !isValidAvailability(availability)) {
      res.status(400).json({
        message: 'availability must be one of: available, busy, offline, on_break, in_transit',
      });
      return;
    }

    const responder = AssignmentService.setResponderAvailability(
      responderId,
      availability,
      latitude,
      longitude,
    );

    if (!responder) {
      res.status(404).json({
        message: 'Responder not found',
      });
      return;
    }

    res.json({ responder });
  } catch (error) {
    console.error('Update responder availability error:', error);

    res.status(500).json({
      message: 'Failed to update responder availability',
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

    AssignmentService.setResponderAvailability(userId, 'busy');

    broadcastEmergencyEvent('emergency:assigned', emergency, {
      assignedResponderId: userId,
    });

    res.json({ emergency });
  } catch (error) {
    console.error('Accept emergency error:', error);

    res.status(500).json({
      message: 'Failed to accept emergency request',
    });
  }
});

// ── PUT /api/emergency/:id/decline ──────────────────────────────────────────
router.put<{ id: string }>('/:id/decline', requireAuth, (req: Request<{ id: string }>, res: Response): void => {
  try {
    const { userId, role } = res.locals.user as AuthenticatedUser;

    if (!role || (role !== 'responder' && role !== 'admin')) {
      res.status(403).json({
        message: 'Only responders can decline requests',
      });
      return;
    }

    const request = EmergencyRequestRepository.findById(req.params.id);
    if (!request) {
      res.status(404).json({ message: 'Emergency request not found' });
      return;
    }

    if (role === 'responder' && request.responder_id !== userId) {
      res.status(403).json({ message: 'You are not assigned to this request' });
      return;
    }

    const declinedResponderId = request.responder_id as string | null;
    const unassigned = EmergencyRequestRepository.unassignResponder(req.params.id);

    if (!unassigned) {
      res.status(400).json({ message: 'Failed to unassign responder' });
      return;
    }

    if (declinedResponderId) {
      AssignmentService.setResponderAvailability(declinedResponderId, 'available');
    }

    const excluded = declinedResponderId ? [declinedResponderId] : [];
    const reassignment = AssignmentService.reassignAfterDecline(req.params.id, excluded);

    broadcastEmergencyEvent('emergency:reassigned', reassignment.emergency, {
      previousResponderId: declinedResponderId,
      reassigned: reassignment.assignedResponder != null,
    });

    res.json({
      emergency: reassignment.emergency,
      reassigned: reassignment.assignedResponder != null,
      assignment: reassignment.assignedResponder
        ? {
            responderId: reassignment.assignedResponder.id,
            responderName: reassignment.assignedResponder.name,
            responderPhone: reassignment.assignedResponder.phone,
            distanceKm: reassignment.distanceKm,
          }
        : null,
    });
  } catch (error) {
    console.error('Decline emergency error:', error);

    res.status(500).json({
      message: 'Failed to decline emergency request',
    });
  }
});

// ── PUT /api/emergency/:id/status ────────────────────────────────────────────
router.put<{ id: string }>('/:id/status', requireAuth, (req: Request<{ id: string }>, res: Response): void => {
  try {
    const { status } = req.body;
    const current = EmergencyRequestRepository.findById(req.params.id);

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

    if (!current) {
      res.status(404).json({
        message: 'Emergency request not found',
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

    const responderId = emergency.responder_id || current.responder_id;
    if (responderId) {
      if (status === 'in_progress') {
        AssignmentService.setResponderAvailability(responderId, 'in_transit');
      } else if (status === 'accepted') {
        AssignmentService.setResponderAvailability(responderId, 'busy');
      } else if (status === 'completed' || status === 'cancelled') {
        AssignmentService.setResponderAvailability(responderId, 'available');
      }
    }

    broadcastEmergencyEvent('emergency:status', emergency, {
      previousStatus: current.status,
      status,
    });

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

    broadcastEmergencyEvent('emergency:cancelled', emergency, {
      cancelledBy: (res.locals.user as AuthenticatedUser).userId,
    });

    res.json({ emergency });
  } catch (error) {
    console.error('Cancel emergency error:', error);

    res.status(500).json({
      message: 'Failed to cancel emergency request',
    });
  }
});

export default router;