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

// Health check — Flutter's ApiClient uses this to confirm connectivity
app.get('/api/health', (_req: Request, res: Response) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// ── Socket.IO — real-time emergency updates ──────────────────────────────────

io.on('connection', (socket: Socket) => {
  console.log('[WS] Client connected:', socket.id);

  // Join global responder stream for all emergency broadcasts.
  socket.on('join_responders', () => {
    socket.join('responders_all');
    console.log(`[WS] ${socket.id} joined room: responders_all`);
  });

  // Join personal responder stream for assignment-specific events.
  socket.on('join_responder', (responderId: string) => {
    socket.join(`responder_${responderId}`);
    console.log(`[WS] ${socket.id} joined room: responder_${responderId}`);
  });

  // Responder or patient can join a room keyed by requestId to get live updates
  socket.on('join_request', (requestId: string) => {
    socket.join(`request_${requestId}`);
    console.log(`[WS] ${socket.id} joined room: request_${requestId}`);
  });

  socket.on('disconnect', () => {
    console.log('[WS] Client disconnected:', socket.id);
  });
});

// Export io so routes can emit events (e.g. broadcast status changes)
export { app, io };

// ── Start server ─────────────────────────────────────────────────────────────

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`[SERVER] Running on http://localhost:${PORT}`);
});
