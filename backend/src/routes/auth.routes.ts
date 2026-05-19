import { Router, Request, Response } from 'express';
import { AuthService, AuthError, ValidationError } from '../services/auth.service';

const router = Router();

// ── POST /api/auth/register ──────────────────────────────────────────────────
router.post('/register', async (req: Request, res: Response) => {
  try {
    const { name, phone, email, password, role } = req.body;

    if (!name || !phone || !password || !role) {
      return res.status(400).json({ message: 'name, phone, password and role are required' });
    }

    const result = await AuthService.register(name, phone, email, password, role);

    return res.status(201).json({
      user: result.user,
      token: result.token,
      refreshToken: result.refreshToken,
    });
  } catch (err: any) {
    if (err instanceof ValidationError) {
      return res.status(400).json({ message: err.message });
    }
    if (err instanceof AuthError && err.statusCode === 409) {
      return res.status(409).json({ message: err.message });
    }
    console.error('Register error:', err);
    return res.status(500).json({ message: 'Internal server error' });
  }
});

// ── POST /api/auth/login ─────────────────────────────────────────────────────
router.post('/login', async (req: Request, res: Response) => {
  try {
    const { phone, password } = req.body;

    if (!phone || !password) {
      return res.status(400).json({ message: 'Phone and password are required' });
    }

    const result = await AuthService.login(phone, password);

    return res.status(200).json({
      user: result.user,
      token: result.token,
      refreshToken: result.refreshToken,
    });
  } catch (err: any) {
    if (err instanceof AuthError) {
      return res.status(err.statusCode ?? 401).json({ message: err.message });
    }
    if (err instanceof ValidationError) {
      return res.status(400).json({ message: err.message });
    }
    console.error('Login error:', err);
    return res.status(500).json({ message: 'Internal server error' });
  }
});

// ── POST /api/auth/refresh ───────────────────────────────────────────────────
router.post('/refresh', async (req: Request, res: Response) => {
  try {
    const { refreshToken } = req.body;
    if (!refreshToken) {
      return res.status(400).json({ message: 'refreshToken is required' });
    }

    const result = await AuthService.refreshToken(refreshToken);

    return res.status(200).json({
      user: result.user,
      token: result.token,
      refreshToken: result.refreshToken,
    });
  } catch (err: any) {
    if (err instanceof AuthError) {
      return res.status(err.statusCode ?? 401).json({ message: err.message });
    }
    console.error('Refresh error:', err);
    return res.status(500).json({ message: 'Internal server error' });
  }
});

// ── POST /api/auth/logout ────────────────────────────────────────────────────
router.post('/logout', async (req: Request, res: Response) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ message: 'Authorization token required' });
    }

    const token = authHeader.split(' ')[1];
    const { userId } = req.body;

    if (!userId) {
      return res.status(400).json({ message: 'userId is required' });
    }

    await AuthService.logout(userId, token);
    return res.status(200).json({ message: 'Logged out successfully' });
  } catch (err: any) {
    if (err instanceof AuthError) {
      return res.status(err.statusCode ?? 401).json({ message: err.message });
    }
    console.error('Logout error:', err);
    return res.status(500).json({ message: 'Internal server error' });
  }
});

// ── GET /api/auth/verify ─────────────────────────────────────────────────────
router.get('/verify', async (req: Request, res: Response) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ message: 'Authorization token required' });
    }

    const token = authHeader.split(' ')[1];
    const payload = await AuthService.verifyToken(token);

    return res.status(200).json({ valid: true, payload });
  } catch (err: any) {
    if (err instanceof AuthError) {
      return res.status(401).json({ message: err.message });
    }
    console.error('Verify error:', err);
    return res.status(500).json({ message: 'Internal server error' });
  }
});

export default router;
