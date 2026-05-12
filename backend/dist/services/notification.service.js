"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.NotificationService = exports.NotificationError = void 0;
const ws_1 = require("ws");
const pg_1 = require("pg");
const uuid_1 = require("uuid");
const dotenv = __importStar(require("dotenv"));
// Load environment variables
dotenv.config();
// In-memory WebSocket connection registry
const webSocketRegistry = new Map();
// Custom error classes
class NotificationError extends Error {
    statusCode;
    constructor(message, statusCode) {
        super(message);
        this.statusCode = statusCode;
        this.name = 'NotificationError';
    }
}
exports.NotificationError = NotificationError;
/**
 * Service class that handles push notifications via WebSocket
 *
 * Delivers notifications to connected devices with PostgreSQL fallback
 * for the Mobile Emergency Medical Assistance App backend.
 * Does NOT use Firebase.
 */
class NotificationService {
    static RETRY_ATTEMPTS = 3;
    static RETRY_DELAY = 1000; // 1 second
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
    static async sendPushNotification(userId, title, body, data) {
        try {
            console.log(`Sending push notification to user: ${userId}`);
            // Strategy 1: Check for active WebSocket connection
            const existingSocket = webSocketRegistry.get(userId);
            if (existingSocket && existingSocket.readyState === ws_1.WebSocket.OPEN) {
                console.log(`Delivering notification via WebSocket to user: ${userId}`);
                const notification = {
                    id: (0, uuid_1.v4)(),
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
        }
        catch (error) {
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
    static async broadcastNotification(userIds, title, body, data) {
        try {
            console.log(`Broadcasting notification to ${userIds.length} users`);
            const notification = {
                id: (0, uuid_1.v4)(),
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
                if (existingSocket && existingSocket.readyState === ws_1.WebSocket.OPEN) {
                    existingSocket.send(JSON.stringify({
                        type: 'notification',
                        payload: notification,
                    }));
                    deliveredCount++;
                }
                else {
                    // Store for offline users
                    await this.storeNotificationInDatabase(userId, title, body, data);
                    failedCount++;
                }
            }
            console.log(`Broadcast complete: ${deliveredCount} delivered, ${failedCount} stored for offline users`);
        }
        catch (error) {
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
    static registerWebSocket(userId, socket) {
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
    static unregisterWebSocket(userId) {
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
    static getActiveConnectionCount() {
        let activeCount = 0;
        for (const [userId, socket] of webSocketRegistry.entries()) {
            if (socket.readyState === ws_1.WebSocket.OPEN) {
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
    static getActiveUserIds() {
        const activeUserIds = [];
        for (const [userId, socket] of webSocketRegistry.entries()) {
            if (socket.readyState === ws_1.WebSocket.OPEN) {
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
    static async storeNotificationInDatabase(userId, title, body, data) {
        const pool = new pg_1.Pool({
            connectionString: process.env.DATABASE_URL,
            ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
        });
        const client = await pool.connect();
        try {
            const notificationId = (0, uuid_1.v4)();
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
        }
        catch (error) {
            console.error(`Failed to store notification in database:`, error);
            throw new NotificationError(`Failed to store notification: ${error.message}`);
        }
        finally {
            client.release();
        }
    }
    /**
     * Retrieves pending notifications for a user
     *
     * @param userId - User ID
     * @returns Promise resolving to array of notifications
     */
    static async getPendingNotifications(userId) {
        const pool = new pg_1.Pool({
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
        }
        catch (error) {
            console.error(`Failed to retrieve pending notifications:`, error);
            throw new NotificationError(`Failed to retrieve notifications: ${error.message}`);
        }
        finally {
            client.release();
        }
    }
    /**
     * Marks notifications as read
     *
     * @param userId - User ID
     * @param notificationIds - Array of notification IDs to mark as read
     */
    static async markNotificationsAsRead(userId, notificationIds) {
        const pool = new pg_1.Pool({
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
        }
        catch (error) {
            console.error(`Failed to mark notifications as read:`, error);
            throw new NotificationError(`Failed to mark notifications as read: ${error.message}`);
        }
        finally {
            client.release();
        }
    }
    /**
     * Cleans up old notifications from database
     *
     * @param daysOld - Number of days to keep notifications (default: 30)
     */
    static async cleanupOldNotifications(daysOld = 30) {
        const pool = new pg_1.Pool({
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
        }
        catch (error) {
            console.error(`Failed to cleanup old notifications:`, error);
            throw new NotificationError(`Failed to cleanup notifications: ${error.message}`);
        }
        finally {
            client.release();
        }
    }
    /**
     * Initializes the notification service
     */
    static initialize() {
        console.log('Notification service initialized');
        // Set up periodic cleanup
        setInterval(() => {
            this.cleanupOldNotifications();
        }, 24 * 60 * 60 * 1000); // Run daily
        console.log('Notification service cleanup scheduled');
    }
}
exports.NotificationService = NotificationService;
