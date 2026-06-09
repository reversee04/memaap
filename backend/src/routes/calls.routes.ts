import { Router, Request, Response, NextFunction } from 'express';
import { AuthService } from '../services/auth.service';
import { CallSessionRepository, CallEndReason } from '../repositories/call-session.repository';

const router = Router();

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

router.post('/emergencies/:id/start', requireAuth, (req: Request, res: Response) => {
  try {
    const emergencyId = req.params.id;
    const callerUserId = res.locals.user.userId;

    if (!CallSessionRepository.canUserParticipateInEmergency(emergencyId, callerUserId)) {
      return res.status(403).json({ message: 'You are not allowed to call for this emergency' });
    }

    if (CallSessionRepository.hasActiveCallForEmergency(emergencyId)) {
      return res.status(409).json({ message: 'An active call already exists for this emergency' });
    }

    const calleeUserId = CallSessionRepository.resolveCalleeForEmergency(emergencyId, callerUserId);
    if (!calleeUserId) {
      return res.status(400).json({ message: 'Could not determine call recipient for this emergency' });
    }

    const callSession = CallSessionRepository.createSession(emergencyId, callerUserId, calleeUserId);
    return res.status(201).json({ callSession });
  } catch (err: any) {
    console.error('Start call error:', err);
    return res.status(500).json({ message: 'Failed to start call' });
  }
});

router.get('/emergencies/:id/latest', requireAuth, (req: Request, res: Response) => {
  try {
    const emergencyId = req.params.id;
    const userId = res.locals.user.userId;

    if (!CallSessionRepository.canUserParticipateInEmergency(emergencyId, userId)) {
      return res.status(403).json({ message: 'You are not allowed to view calls for this emergency' });
    }

    const callSession = CallSessionRepository.findLatestByEmergencyId(emergencyId);
    return res.json({ callSession: callSession || null });
  } catch (err: any) {
    console.error('Get latest call error:', err);
    return res.status(500).json({ message: 'Failed to fetch latest call' });
  }
});

router.post('/:callSessionId/accept', requireAuth, (req: Request, res: Response) => {
  try {
    const callSessionId = req.params.callSessionId;
    const userId = res.locals.user.userId;

    if (!CallSessionRepository.isUserInCallSession(callSessionId, userId)) {
      return res.status(403).json({ message: 'You are not a participant in this call session' });
    }

    const callSession = CallSessionRepository.markAccepted(callSessionId);
    if (!callSession) {
      return res.status(404).json({ message: 'Call session not found' });
    }

    return res.json({ callSession });
  } catch (err: any) {
    console.error('Accept call error:', err);
    return res.status(500).json({ message: 'Failed to accept call' });
  }
});

router.post('/:callSessionId/reject', requireAuth, (req: Request, res: Response) => {
  try {
    const callSessionId = req.params.callSessionId;
    const userId = res.locals.user.userId;

    if (!CallSessionRepository.isUserInCallSession(callSessionId, userId)) {
      return res.status(403).json({ message: 'You are not a participant in this call session' });
    }

    const callSession = CallSessionRepository.markRejected(callSessionId);
    if (!callSession) {
      return res.status(404).json({ message: 'Call session not found' });
    }

    return res.json({ callSession });
  } catch (err: any) {
    console.error('Reject call error:', err);
    return res.status(500).json({ message: 'Failed to reject call' });
  }
});

router.post('/:callSessionId/end', requireAuth, (req: Request, res: Response) => {
  try {
    const callSessionId = req.params.callSessionId;
    const userId = res.locals.user.userId;
    const reason = (req.body?.end_reason || 'hangup') as CallEndReason;

    if (!CallSessionRepository.isUserInCallSession(callSessionId, userId)) {
      return res.status(403).json({ message: 'You are not a participant in this call session' });
    }

    const callSession = CallSessionRepository.markEnded(callSessionId, reason);
    if (!callSession) {
      return res.status(404).json({ message: 'Call session not found' });
    }

    return res.json({ callSession });
  } catch (err: any) {
    console.error('End call error:', err);
    return res.status(500).json({ message: 'Failed to end call' });
  }
});

export default router;
