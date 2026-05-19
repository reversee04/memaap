/**
 * hospitals.routes.ts
 *
 *  GET  /api/hospitals          — all available hospitals
 *  GET  /api/hospitals/nearby   — nearby hospitals (?lat=&lng=&radius=)
 *  GET  /api/hospitals/:id      — single hospital
 *  POST /api/hospitals          — add hospital (admin only)
 *  PUT  /api/hospitals/:id/availability — toggle availability (admin/responder)
 */

import { Router, Request, Response, NextFunction } from 'express';
import { AuthService } from '../services/auth.service';
import { HospitalRepository } from '../repositories/hospital.repository';

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

// ── GET /api/hospitals ───────────────────────────────────────────────────────

router.get('/', requireAuth, (_req: Request, res: Response) => {
  try {
    const hospitals = HospitalRepository.findAll();
    return res.json({ hospitals });
  } catch (err) {
    console.error('Get hospitals error:', err);
    return res.status(500).json({ message: 'Failed to fetch hospitals' });
  }
});

// ── GET /api/hospitals/nearby ────────────────────────────────────────────────

router.get('/nearby', requireAuth, (req: Request, res: Response) => {
  try {
    const lat = parseFloat(req.query.lat as string);
    const lng = parseFloat(req.query.lng as string);
    const radius = parseFloat((req.query.radius as string) || '10');

    if (isNaN(lat) || isNaN(lng)) {
      return res.status(400).json({ message: 'lat and lng query parameters are required' });
    }

    const hospitals = HospitalRepository.findNearby(lat, lng, radius);
    return res.json({ hospitals });
  } catch (err) {
    console.error('Get nearby hospitals error:', err);
    return res.status(500).json({ message: 'Failed to fetch nearby hospitals' });
  }
});

// ── GET /api/hospitals/:id ───────────────────────────────────────────────────

router.get('/:id', requireAuth, (req: Request, res: Response) => {
  try {
    const hospital = HospitalRepository.findById(req.params.id);
    if (!hospital) return res.status(404).json({ message: 'Hospital not found' });
    return res.json({ hospital });
  } catch (err) {
    console.error('Get hospital error:', err);
    return res.status(500).json({ message: 'Failed to fetch hospital' });
  }
});

// ── POST /api/hospitals ──────────────────────────────────────────────────────

router.post('/', requireAuth, (req: Request, res: Response) => {
  try {
    if (res.locals.user.role !== 'admin') {
      return res.status(403).json({ message: 'Admin access required' });
    }

    const { name, address, latitude, longitude, phone, email, website, emergencyServices } = req.body;
    if (!name || !address || !latitude || !longitude || !phone) {
      return res.status(400).json({ message: 'name, address, latitude, longitude, phone are required' });
    }

    const hospital = HospitalRepository.create({ name, address, latitude, longitude, phone, email, website, emergencyServices });
    return res.status(201).json({ hospital });
  } catch (err) {
    console.error('Create hospital error:', err);
    return res.status(500).json({ message: 'Failed to create hospital' });
  }
});

// ── PUT /api/hospitals/:id/availability ─────────────────────────────────────

router.put('/:id/availability', requireAuth, (req: Request, res: Response) => {
  try {
    const { role } = res.locals.user;
    if (role !== 'admin' && role !== 'responder') {
      return res.status(403).json({ message: 'Admin or responder access required' });
    }

    const { isAvailable } = req.body;
    if (typeof isAvailable !== 'boolean') {
      return res.status(400).json({ message: 'isAvailable (boolean) is required' });
    }

    HospitalRepository.updateAvailability(req.params.id, isAvailable);
    const hospital = HospitalRepository.findById(req.params.id);
    return res.json({ hospital });
  } catch (err) {
    console.error('Update availability error:', err);
    return res.status(500).json({ message: 'Failed to update hospital availability' });
  }
});

export default router;
