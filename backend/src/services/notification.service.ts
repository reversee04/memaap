import { WebSocket, WebSocketServer } from 'ws';
import { Pool, PoolClient, PoolConfig } from 'pg';
import { v4 as uuidv4 } from 'uuid';
import * as dotenv from 'dotenv';

// Load environment variables
dotenv.config();

// In-memory WebSocket connection registry
const webSocketRegistry = new Map<string, WebSocket>();

// Custom error classes
export class NotificationError extends Error {
  constructor(message: string, public statusCode?: number) {
    super(message);
    this.name = 'NotificationError';
  }
}

// Notification interface
interface NotificationData {
  userId: string;
  title: string;
  body: string;
  data?: Record<string, any>;
  priority?: 'low' | 'normal' | 'high' | 'urgent';
}

/**
 * Service class that handles push notifications via WebSocket
 * 
 * Delivers notifications to connected devices with PostgreSQL fallback
 * for the Mobile Emergency Medical Assistance App backend.
 * Does NOT use Firebase.
 */
export class NotificationService {
  private static readonly RETRY_ATTEMPTS = 3;
  private static readonly RETRY_DELAY = 1000; // 1 second

  /**
   * Sends a push notification to a specific user
   * 
   * @param userId - Target user ID
   * @param title - Notification title
   * @param body - Notification body
   * @param data - Optional notification data payload
   * 
   * @returns Promise that resolves when notification is sent
   */
  static async sendPushNotification(
    userId: string,
    title: string,
    body: string,
    data?: Record<string, any>
  ): Promise<void> {
    try {
      console.log(`Sending push notification to user: ${userId}`);

      // Strategy 1: Check for active WebSocket connection
      const existingSocket = webSocketRegistry.get(userId);

      if (existingSocket && existingSocket.readyState === WebSocket.OPEN) {
        console.log(`Delivering notification via WebSocket to user: ${userId}`);

        const notification = {
          id: uuidv4(),
          userId,
          title,
          body,
          data,
          priority: data?.priority || 'normal',
          createdAt: new Date().toISOString(),
        };

        existingSocket.send(JSON.stringify({
          type: 'notification',
          payload: notification,
        }));

        console.log(`Notification delivered via WebSocket: ${notification.id}`);
        return;
      }

      // Strategy 2: Fallback to PostgreSQL storage
      console.log(`WebSocket not connected for user: ${userId}, storing in database`);

      await this.storeNotificationInDatabase(userId, title, body, data);
      console.log(`Notification stored in database for user: ${userId}`);

    } catch (error: any) {
      console.error(`Failed to send push notification to user ${userId}:`, error);
      throw new NotificationError(`Failed to send notification: ${error.message}`);
    }
  }

  /**
   * Broadcasts a push notification to multiple users
   * 
   * @param userIds - Array of target user IDs
   * @param title - Notification title
   * @param body - Notification body
   * @param data - Optional notification data payload
   * 
   * @returns Promise that resolves when broadcast is complete
   */
  static async broadcastNotification(
    userIds: string[],
    title: string,
    body: string,
    data?: Record<string, any>
  ): Promise<void> {
    try {
      console.log(`Broadcasting notification to ${userIds.length} users`);

      const notification = {
        id: uuidv4(),
        title,
        body,
        data,
        priority: data?.priority || 'normal',
        createdAt: new Date().toISOString(),
      };

      let deliveredCount = 0;
      let failedCount = 0;

      // Deliver to connected users via WebSocket
      for (const userId of userIds) {
        const existingSocket = webSocketRegistry.get(userId);

        if (existingSocket && existingSocket.readyState === WebSocket.OPEN) {
          existingSocket.send(JSON.stringify({
            type: 'notification',
            payload: notification,
          }));

          deliveredCount++;
        } else {
          // Store for offline users
          await this.storeNotificationInDatabase(userId, title, body, data);
          failedCount++;
        }
      }

      console.log(`Broadcast complete: ${deliveredCount} delivered, ${failedCount} stored for offline users`);

    } catch (error: any) {
      console.error(`Failed to broadcast notification:`, error);
      throw new NotificationError(`Failed to broadcast notification: ${error.message}`);
    }
  }

  /**
   * Registers a WebSocket connection for a user
   * 
   * @param userId - User ID
   * @param socket - WebSocket connection
   */
  static registerWebSocket(userId: string, socket: WebSocket): void {
    console.log(`Registering WebSocket for user: ${userId}`);

    // Remove any existing connection for this user
    const existingSocket = webSocketRegistry.get(userId);
    if (existingSocket) {
      existingSocket.close();
    }

    // Store new connection
    webSocketRegistry.set(userId, socket);

    // Set up connection event handlers
    socket.on('close', () => {
      console.log(`WebSocket closed for user: ${userId}`);
      webSocketRegistry.delete(userId);
    });

    socket.on('error', (error) => {
      console.error(`WebSocket error for user ${userId}:`, error);
      webSocketRegistry.delete(userId);
    });

    console.log(`WebSocket registered for user: ${userId}`);
  }

  /**
   * Unregisters a WebSocket connection for a user
   * 
   * @param userId - User ID
   */
  static unregisterWebSocket(userId: string): void {
    console.log(`Unregistering WebSocket for user: ${userId}`);

    const socket = webSocketRegistry.get(userId);
    if (socket) {
      socket.close();
      webSocketRegistry.delete(userId);
    }
  }

  /**
   * Gets the number of active WebSocket connections
   * 
   * @returns Number of connected users
   */
  static getActiveConnectionCount(): number {
    let activeCount = 0;

    for (const [userId, socket] of webSocketRegistry.entries()) {
      if (socket.readyState === WebSocket.OPEN) {
        activeCount++;
      }
    }

    return activeCount;
  }

  /**
   * Gets all active user IDs
   * 
   * @returns Array of connected user IDs
   */
  static getActiveUserIds(): string[] {
    const activeUserIds: string[] = [];

    for (const [userId, socket] of webSocketRegistry.entries()) {
      if (socket.readyState === WebSocket.OPEN) {
        activeUserIds.push(userId);
      }
    }

    return activeUserIds;
  }

  /**
   * Stores a notification in PostgreSQL database for offline users
   * 
   * @param userId - Target user ID
   * @param title - Notification title
   * @param body - Notification body
   * @param data - Optional notification data
   */
  private static async storeNotificationInDatabase(
    userId: string,
    title: string,
    body: string,
    data?: Record<string, any>
  ): Promise<void> {
    const pool = new Pool({
      connectionString: process.env.DATABASE_URL,
      ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
    });

    const client = await pool.connect();

    try {
      const notificationId = uuidv4();

      const query = `
        INSERT INTO notifications (
          id, 
          user_id, 
          title, 
          body, 
          data, 
          is_read, 
          created_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7)
      `;

      await client.query(query, [
        notificationId,
        userId,
        title,
        body,
        data ? JSON.stringify(data) : null,
        false,
        new Date(),
      ]);

      console.log(`Notification stored in database: ${notificationId}`);

    } catch (error: any) {
      console.error(`Failed to store notification in database:`, error);
      throw new NotificationError(`Failed to store notification: ${error.message}`);
    } finally {
      client.release();
    }
  }

  /**
   * Retrieves pending notifications for a user
   * 
   * @param userId - User ID
   * @returns Promise resolving to array of notifications
   */
  static async getPendingNotifications(userId: string): Promise<any[]> {
    const pool = new Pool({
      connectionString: process.env.DATABASE_URL,
      ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
    });

    const client = await pool.connect();

    try {
      const query = `
        SELECT id, user_id, title, body, data, created_at, is_read
        FROM notifications 
        WHERE user_id = $1 AND is_read = false 
        ORDER BY created_at DESC 
        LIMIT 50
      `;

      const result = await client.query(query, [userId]);

      const notifications = result.rows.map(row => ({
        id: row.id,
        userId: row.user_id,
        title: row.title,
        body: row.body,
        data: row.data ? JSON.parse(row.data) : null,
        createdAt: row.created_at,
        isRead: row.is_read,
      }));

      console.log(`Retrieved ${notifications.length} pending notifications for user: ${userId}`);
      return notifications;

    } catch (error: any) {
      console.error(`Failed to retrieve pending notifications:`, error);
      throw new NotificationError(`Failed to retrieve notifications: ${error.message}`);
    } finally {
      client.release();
    }
  }

  /**
   * Marks notifications as read
   * 
   * @param userId - User ID
   * @param notificationIds - Array of notification IDs to mark as read
   */
  static async markNotificationsAsRead(userId: string, notificationIds: string[]): Promise<void> {
    const pool = new Pool({
      connectionString: process.env.DATABASE_URL,
      ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
    });

    const client = await pool.connect();

    try {
      const placeholders = notificationIds.map((_, index) => `$${index + 1}`).join(', ');
      const values = notificationIds.map(id => `'${id}'`).join(', ');

      const query = `
        UPDATE notifications 
        SET is_read = true 
        WHERE user_id = $1 AND id IN (${placeholders})
      `;

      await client.query(query, [userId, ...notificationIds]);

      console.log(`Marked ${notificationIds.length} notifications as read for user: ${userId}`);

    } catch (error: any) {
      console.error(`Failed to mark notifications as read:`, error);
      throw new NotificationError(`Failed to mark notifications as read: ${error.message}`);
    } finally {
      client.release();
    }
  }

  /**
   * Cleans up old notifications from database
   * 
   * @param daysOld - Number of days to keep notifications (default: 30)
   */
  static async cleanupOldNotifications(daysOld: number = 30): Promise<void> {
    const pool = new Pool({
      connectionString: process.env.DATABASE_URL,
      ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
    });

    const client = await pool.connect();

    try {
      const cutoffDate = new Date();
      cutoffDate.setDate(cutoffDate.getDate() - daysOld);

      const query = `
        DELETE FROM notifications 
        WHERE created_at < $1
      `;

      const result = await client.query(query, [cutoffDate.toISOString()]);

      console.log(`Cleaned up ${result.rowCount} old notifications`);

    } catch (error: any) {
      console.error(`Failed to cleanup old notifications:`, error);
      throw new NotificationError(`Failed to cleanup notifications: ${error.message}`);
    } finally {
      client.release();
    }
  }

  /**
   * Initializes the notification service
   */
  static initialize(): void {
    console.log('Notification service initialized');

    // Set up periodic cleanup
    setInterval(() => {
      this.cleanupOldNotifications();
    }, 24 * 60 * 60 * 1000); // Run daily

    console.log('Notification service cleanup scheduled');
  }
}
