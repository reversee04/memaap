/**
 * index.ts — Express + Socket.IO entry point
 *
 * Mounts all API routes. The SQLite database is initialised as a side-effect
 * of importing config/database.ts (tables are created on first run).
 */

import express, { Request, Response } from 'express';
import cors from 'cors';
import { createServer } from 'http';
import { Server, Socket } from 'socket.io';
import * as dotenv from 'dotenv';

// Load env before anything else
dotenv.config();

// Importing database triggers table creation — must be before routes
import './config/database';

// Route handlers
import authRoutes      from './routes/auth.routes';
import userRoutes      from './routes/users.routes';
import emergencyRoutes from './routes/emergency.routes';
import hospitalRoutes  from './routes/hospitals.routes';
import callsRoutes     from './routes/calls.routes';
import { AuthService } from './services/auth.service';
import { CallSessionRepository } from './repositories/call-session.repository';

const app    = express();
const server = createServer(app);
const io     = new Server(server, { cors: { origin: '*' } });

// ── Middleware ────────────────────────────────────────────────────────────────

app.use(cors());
app.use(express.json());

// ── Routes ────────────────────────────────────────────────────────────────────

app.use('/api/auth',      authRoutes);
app.use('/api/users',     userRoutes);
app.use('/api/emergency', emergencyRoutes);
app.use('/api/hospitals', hospitalRoutes);
app.use('/api/calls',     callsRoutes);

// Health check — Flutter's ApiClient uses this to confirm connectivity
app.get('/api/health', (_req: Request, res: Response) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// ── Socket.IO — real-time emergency updates ──────────────────────────────────

io.use(async (socket: Socket, next) => {
  try {
    const authToken = socket.handshake.auth?.token as string | undefined;
    const queryToken = socket.handshake.query?.token as string | undefined;
    const token = authToken || queryToken;

    if (!token) {
      return next(new Error('Unauthorized: missing token'));
    }

    const payload = await AuthService.verifyToken(token);
    socket.data.user = payload;
    return next();
  } catch {
    return next(new Error('Unauthorized: invalid token'));
  }
});

io.on('connection', (socket: Socket) => {
  const user = socket.data.user as { userId: string; role: string };
  const userRoom = `user_${user.userId}`;

  socket.join(userRoom);
  console.log('[WS] Client connected:', socket.id);

  // Responder or patient can join a room keyed by requestId to get live updates
  socket.on('join_request', (requestId: string) => {
    socket.join(`request_${requestId}`);
    console.log(`[WS] ${socket.id} joined room: request_${requestId}`);
  });

  socket.on('disconnect', () => {
    console.log('[WS] Client disconnected:', socket.id);
  });

  socket.on('call:invite', (payload: { callSessionId: string; emergencyId: string }) => {
    const { callSessionId } = payload;

    if (!CallSessionRepository.isUserInCallSession(callSessionId, user.userId)) {
      socket.emit('call:error', { message: 'Not allowed to invite for this call session' });
      return;
    }

    const callSession = CallSessionRepository.findById(callSessionId);
    if (!callSession) {
      socket.emit('call:error', { message: 'Call session not found' });
      return;
    }

    const calleeUserId = callSession.callee_user_id;
    io.to(`user_${calleeUserId}`).emit('call:incoming', {
      callSessionId,
      emergencyId: callSession.emergency_id,
      callerUserId: callSession.caller_user_id,
      calleeUserId: callSession.callee_user_id,
      startedAt: callSession.started_at,
    });

    io.to(`user_${callSession.caller_user_id}`).emit('call:ringing', {
      callSessionId,
      emergencyId: callSession.emergency_id,
      status: 'ringing',
    });
  });

  socket.on('call:accept', (payload: { callSessionId: string }) => {
    const { callSessionId } = payload;

    if (!CallSessionRepository.isUserInCallSession(callSessionId, user.userId)) {
      socket.emit('call:error', { message: 'Not allowed to accept this call session' });
      return;
    }

    const callSession = CallSessionRepository.markAccepted(callSessionId);
    if (!callSession) {
      socket.emit('call:error', { message: 'Call session not found' });
      return;
    }

    io.to(`user_${callSession.caller_user_id}`).emit('call:accepted', {
      id: callSessionId,
      emergency_id: callSession.emergency_id,
      caller_user_id: callSession.caller_user_id,
      callee_user_id: callSession.callee_user_id,
      status: 'active',
      answered_at: callSession.answered_at,
    });
    io.to(`user_${callSession.callee_user_id}`).emit('call:accepted', {
      id: callSessionId,
      emergency_id: callSession.emergency_id,
      caller_user_id: callSession.caller_user_id,
      callee_user_id: callSession.callee_user_id,
      status: 'active',
      answered_at: callSession.answered_at,
    });
  });

  socket.on('call:reject', (payload: { callSessionId: string }) => {
    const { callSessionId } = payload;

    if (!CallSessionRepository.isUserInCallSession(callSessionId, user.userId)) {
      socket.emit('call:error', { message: 'Not allowed to reject this call session' });
      return;
    }

    const callSession = CallSessionRepository.markRejected(callSessionId);
    if (!callSession) {
      socket.emit('call:error', { message: 'Call session not found' });
      return;
    }

    io.to(`user_${callSession.caller_user_id}`).emit('call:rejected', {
      id: callSessionId,
      emergency_id: callSession.emergency_id,
      caller_user_id: callSession.caller_user_id,
      callee_user_id: callSession.callee_user_id,
      status: 'rejected',
      ended_at: callSession.ended_at,
      end_reason: callSession.end_reason,
    });
    io.to(`user_${callSession.callee_user_id}`).emit('call:rejected', {
      id: callSessionId,
      emergency_id: callSession.emergency_id,
      caller_user_id: callSession.caller_user_id,
      callee_user_id: callSession.callee_user_id,
      status: 'rejected',
      ended_at: callSession.ended_at,
      end_reason: callSession.end_reason,
    });
  });

  socket.on('call:end', (payload: { callSessionId: string; endReason?: string }) => {
    const { callSessionId, endReason } = payload;

    if (!CallSessionRepository.isUserInCallSession(callSessionId, user.userId)) {
      socket.emit('call:error', { message: 'Not allowed to end this call session' });
      return;
    }

    const callSession = CallSessionRepository.markEnded(callSessionId, (endReason as any) || 'hangup');
    if (!callSession) {
      socket.emit('call:error', { message: 'Call session not found' });
      return;
    }

    io.to(`user_${callSession.caller_user_id}`).emit('call:ended', {
      id: callSessionId,
      emergency_id: callSession.emergency_id,
      caller_user_id: callSession.caller_user_id,
      callee_user_id: callSession.callee_user_id,
      status: 'ended',
      ended_at: callSession.ended_at,
      endReason: callSession.end_reason || endReason || 'hangup',
    });
    io.to(`user_${callSession.callee_user_id}`).emit('call:ended', {
      id: callSessionId,
      emergency_id: callSession.emergency_id,
      caller_user_id: callSession.caller_user_id,
      callee_user_id: callSession.callee_user_id,
      status: 'ended',
      ended_at: callSession.ended_at,
      endReason: callSession.end_reason || endReason || 'hangup',
    });
  });

  socket.on('webrtc:offer', (payload: { callSessionId: string; sdp: any }) => {
    const { callSessionId, sdp } = payload;
    if (!CallSessionRepository.isUserInCallSession(callSessionId, user.userId)) {
      socket.emit('call:error', { message: 'Not allowed to send offer for this call session' });
      return;
    }
    const targetUserId = CallSessionRepository.getCounterpartyUserId(callSessionId, user.userId);
    if (!targetUserId) return;

    io.to(`user_${targetUserId}`).emit('webrtc:offer', { callSessionId, sdp });
  });

  socket.on('webrtc:answer', (payload: { callSessionId: string; sdp: any }) => {
    const { callSessionId, sdp } = payload;
    if (!CallSessionRepository.isUserInCallSession(callSessionId, user.userId)) {
      socket.emit('call:error', { message: 'Not allowed to send answer for this call session' });
      return;
    }
    const targetUserId = CallSessionRepository.getCounterpartyUserId(callSessionId, user.userId);
    if (!targetUserId) return;

    io.to(`user_${targetUserId}`).emit('webrtc:answer', { callSessionId, sdp });
  });

  socket.on('webrtc:ice-candidate', (payload: { callSessionId: string; candidate: any }) => {
    const { callSessionId, candidate } = payload;
    if (!CallSessionRepository.isUserInCallSession(callSessionId, user.userId)) {
      socket.emit('call:error', { message: 'Not allowed to send ICE candidate for this call session' });
      return;
    }
    const targetUserId = CallSessionRepository.getCounterpartyUserId(callSessionId, user.userId);
    if (!targetUserId) return;

    io.to(`user_${targetUserId}`).emit('webrtc:ice-candidate', { callSessionId, candidate });
  });
});

// Export io so routes can emit events (e.g. broadcast status changes)
export { app, io };

// ── Start server ─────────────────────────────────────────────────────────────

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`[SERVER] Running on http://localhost:${PORT}`);
});
