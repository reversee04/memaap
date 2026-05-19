import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart' as flutter_secure_storage;
import 'package:shared_preferences/shared_preferences.dart' as shared_preferences;
import '../models/notification_model.dart';
import '../models/user_model.dart';
import '../services/api_client.dart';
import '../config/app_config.dart';

/// Custom exceptions for notification operations
class NotificationException implements Exception {
  final String message;
  
  NotificationException(this.message);
  
  @override
  String toString() => 'NotificationException: $message';
}

/// Singleton class that manages device push token registration, WebSocket notifications,
/// and local notifications for Mobile Emergency Medical Assistance App.
/// 
/// Does NOT use Firebase - uses WebSocket and flutter_local_notifications.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  // Singleton properties
  static const String _deviceTokenKey = 'device_token';
  static const String _notificationChannelId = 'memaap_emergency';
  static const String _notificationChannelName = 'Memaap Emergency';
  static const String _notificationChannelDescription = 'Emergency medical assistance notifications';
  
  static String? _deviceToken;
  static String? _userId;
  static WebSocketChannel? _webSocketChannel;
  static StreamSubscription? _connectivitySubscription;
  static StreamController<NotificationModel>? _notificationStreamController;
  static Timer? _reconnectTimer;
  static int _reconnectAttempts = 0;
  static bool _isInitialized = false;
  static bool _isForeground = false;

  // Local notifications plugin
  static FlutterLocalNotificationsPlugin? _localNotifications;

  /// Gets the current device token
  static String? get deviceToken => _deviceToken;

  /// Gets the current user ID
  static String? get userId => _userId;

  /// Gets the notification stream
  static Stream<NotificationModel>? get notificationStream => 
      _notificationStreamController?.stream;

  /// Gets whether the service is initialized
  static bool get isInitialized => _isInitialized;

  /// Initializes the notification service
  /// 
  /// [userId] - Current user ID for WebSocket connection
  /// 
  /// Returns true if initialization was successful
  static Future<bool> initialize({String? userId}) async {
    try {
      if (_isInitialized) return true;

      _userId = userId;
      
      // Initialize local notifications
      await _initializeLocalNotifications();
      
      // Generate or retrieve device token
      await _generateOrRetrieveDeviceToken();
      
      // Register device token with backend
      if (_deviceToken != null) {
        await _registerDeviceToken();
      }
      
      // Initialize WebSocket connection
      if (userId != null) {
        await _initializeWebSocket(userId);
      }
      
      // Initialize connectivity monitoring
      _initializeConnectivityMonitoring();
      
      _isInitialized = true;
      return true;
    } catch (e) {
      throw NotificationException('Failed to initialize NotificationService: $e');
    }
  }

  /// Initializes local notifications plugin
  static Future<void> _initializeLocalNotifications() async {
    try {
      _localNotifications = FlutterLocalNotificationsPlugin();
      
      // Android initialization
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

      // iOS initialization
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _localNotifications!.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // Create notification channel (Android)
      if (Platform.isAndroid) {
        final androidPlugin = _localNotifications!
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        await androidPlugin?.createNotificationChannel(
          AndroidNotificationChannel(
            _notificationChannelId,
            _notificationChannelName,
            description: _notificationChannelDescription,
            importance: Importance.high,
            playSound: true,
            enableVibration: true,
          ),
        );
      }
    } catch (e) {
      throw NotificationException('Failed to initialize local notifications: $e');
    }
  }

  /// Generates or retrieves device token
  static Future<void> _generateOrRetrieveDeviceToken() async {
    try {
      // Try to get existing token from secure storage
      final prefs = await _getSecureStorage();
      _deviceToken = await prefs.read(key: _deviceTokenKey);
      
      if (_deviceToken == null || _deviceToken!.isEmpty) {
        // Generate new UUID as device token (mock implementation)
        final uuid = const Uuid().v4();
        _deviceToken = uuid.toString();
        
        // Store the token
        await prefs.write(key: _deviceTokenKey, value: _deviceToken!);
        
        debugPrint('Generated new device token: $_deviceToken');
      } else {
        debugPrint('Retrieved existing device token: $_deviceToken');
      }
    } catch (e) {
      throw NotificationException('Failed to generate/retrieve device token: $e');
    }
  }

  /// Registers device token with backend
  static Future<void> _registerDeviceToken() async {
    try {
      if (_deviceToken == null) {
        throw NotificationException('Device token not available');
      }

      final response = await ApiClient.post(
        '/devices/register',
        data: {
          'deviceToken': _deviceToken,
          'platform': Platform.operatingSystem,
          'appVersion': AppConfig.environment,
        },
      );

      debugPrint('Device token registered: ${response['success']}');
    } catch (e) {
      debugPrint('Failed to register device token: $e');
      // Continue without throwing - token can be registered later
    }
  }

  /// Initializes WebSocket connection for real-time notifications
  static Future<void> _initializeWebSocket(String userId) async {
    try {
      final wsUrl = '${AppConfig.baseUrl.replaceFirst('http', 'ws')}/notifications/$userId';
      
      _webSocketChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      
      _webSocketChannel!.stream.listen(
        _onWebSocketMessage,
        onError: _onWebSocketError,
        onDone: _onWebSocketDone,
      );

      debugPrint('WebSocket connected for user: $userId');
      _reconnectAttempts = 0;
      
      // Cancel any existing reconnect timer
      _reconnectTimer?.cancel();
    } catch (e) {
      debugPrint('Failed to initialize WebSocket: $e');
      // Schedule reconnect attempt
      _scheduleReconnect();
    }
  }

  /// Handles WebSocket messages
  static void _onWebSocketMessage(dynamic message) {
    try {
      final data = jsonDecode(message);
      final notification = NotificationModel.fromJson(data);
      
      // Add to stream
      _notificationStreamController?.add(notification);
      
      // Show local notification if app is in background
      if (!_isForeground) {
        showLocalNotification(
          title: notification.title,
          body: notification.body,
          payload: jsonEncode(notification.toJson()),
        );
      }
      
      debugPrint('Received notification: ${notification.typeDisplayName}');
    } catch (e) {
      debugPrint('Failed to parse WebSocket message: $e');
    }
  }

  /// Handles WebSocket errors
  static void _onWebSocketError(dynamic error) {
    debugPrint('WebSocket error: $error');
    _scheduleReconnect();
  }

  /// Handles WebSocket connection close
  static void _onWebSocketDone() {
    debugPrint('WebSocket connection closed');
    _scheduleReconnect();
  }

  /// Schedules WebSocket reconnection with exponential backoff
  static void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    
    if (_reconnectAttempts >= 5) {
      debugPrint('Max reconnect attempts reached');
      return;
    }
    
    final delay = Duration(seconds: (2 << _reconnectAttempts).clamp(1, 30));
    _reconnectAttempts++;
    
    _reconnectTimer = Timer(delay, () {
      if (_userId != null) {
        _initializeWebSocket(_userId!);
      }
    });
    
    debugPrint('Scheduling reconnect attempt $_reconnectAttempts in ${delay.inSeconds}s');
  }

  /// Initializes connectivity monitoring
  static void _initializeConnectivityMonitoring() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none && _webSocketChannel == null) {
        if (_userId != null) {
          _initializeWebSocket(_userId!);
        }
      }
    });
  }

  /// Shows a local notification
  /// 
  /// [title] - Notification title
  /// [body] - Notification body
  /// [payload] - Optional payload data
  static Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      if (_localNotifications == null) return;

      final notificationDetails = NotificationDetails(
        android: AndroidNotificationDetails(
          _notificationChannelId,
          _notificationChannelName,
          channelDescription: _notificationChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
          enableVibration: true,
          playSound: true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
        ),
      );

      await _localNotifications!.show(
        DateTime.now().millisecondsSinceEpoch.remainder(1000),
        title,
        body,
        notificationDetails,
        payload: payload,
      );
    } catch (e) {
      debugPrint('Failed to show local notification: $e');
    }
  }

  /// Handles notification tap events
  static void _onNotificationTapped(NotificationResponse notificationResponse) {
    try {
      final payload = notificationResponse.payload;
      if (payload != null && payload.isNotEmpty) {
        final notificationData = jsonDecode(payload);
        final notification = NotificationModel.fromJson(notificationData);
        onNotificationTapped(jsonEncode(notification.toJson()));
      }
    } catch (e) {
      debugPrint('Failed to handle notification tap: $e');
    }
  }

  /// Handles notification received events
  static void _onNotificationReceived(NotificationResponse notificationResponse) {
    try {
      // Update foreground state
      _isForeground = true;
      
      // Cancel any existing reconnect timer when app comes to foreground
      _reconnectTimer?.cancel();
    } catch (e) {
      debugPrint('Failed to handle notification received: $e');
    }
  }

  /// Handles notification tap with navigation
  /// 
  /// [payload] - JSON string payload from notification
  static void onNotificationTapped(String? payload) {
    try {
      if (payload == null || payload.isEmpty) return;
      
      final notificationData = jsonDecode(payload);
      final notification = NotificationModel.fromJson(notificationData);
      
      // Navigate based on notification type
      switch (notification.type) {
        case NotificationType.emergencyUpdate:
          _handleEmergencyUpdateNotification(notification);
          break;
        case NotificationType.chat:
          _handleChatNotification(notification);
          break;
        case NotificationType.system:
          _handleSystemNotification(notification);
          break;
        case NotificationType.responderUpdate:
          _handleResponderUpdateNotification(notification);
          break;
        case NotificationType.hospitalUpdate:
          _handleHospitalUpdateNotification(notification);
          break;
      }
    } catch (e) {
      debugPrint('Failed to handle notification tap: $e');
    }
  }

  /// Handles emergency update notifications
  static void _handleEmergencyUpdateNotification(NotificationModel notification) {
    // Navigate to emergency tracking screen
    // This would use your navigation system
    // context.go('/emergency-tracking', extra: {'requestId': notification.data?['requestId']});
    debugPrint('Navigate to emergency tracking for request: ${notification.data?['requestId']}');
  }

  /// Handles chat notifications
  static void _handleChatNotification(NotificationModel notification) {
    // Navigate to chat screen
    // context.go('/chat', extra: {'conversationId': notification.data?['conversationId']});
    debugPrint('Navigate to chat for conversation: ${notification.data?['conversationId']}');
  }

  /// Handles system notifications
  static void _handleSystemNotification(NotificationModel notification) {
    // Show system notification dialog or banner
    debugPrint('System notification: ${notification.title}');
  }

  /// Handles responder update notifications
  static void _handleResponderUpdateNotification(NotificationModel notification) {
    // Navigate to responder tracking screen
    // context.go('/responder-tracking', extra: {'responderId': notification.data?['responderId']});
    debugPrint('Navigate to responder tracking: ${notification.data?['responderId']}');
  }

  /// Handles hospital update notifications
  static void _handleHospitalUpdateNotification(NotificationModel notification) {
    // Navigate to hospital details screen
    // context.go('/hospital-details', extra: {'hospitalId': notification.data?['hospitalId']});
    debugPrint('Navigate to hospital details: ${notification.data?['hospitalId']}');
  }

  /// Gets the current device token
  static Future<String?> getDeviceToken() async {
    try {
      if (_deviceToken != null) return _deviceToken;
      
      final prefs = await _getSecureStorage();
      return await prefs.read(key: _deviceTokenKey);
    } catch (e) {
      debugPrint('Failed to get device token: $e');
      return null;
    }
  }

  /// Disconnects the WebSocket connection
  static Future<void> disconnect() async {
    try {
      _reconnectTimer?.cancel();
      _connectivitySubscription?.cancel();
      await _webSocketChannel?.sink.close();
      _webSocketChannel = null;
      _isInitialized = false;
      
      debugPrint('Notification service disconnected');
    } catch (e) {
      debugPrint('Error disconnecting notification service: $e');
    }
  }

  /// Gets secure storage instance
  static Future<MockSharedPreferences> _getSecureStorage() async {
    return _getSharedPreferences();
  }

  /// Gets shared preferences as fallback
  static Future<MockSharedPreferences> _getSharedPreferences() async {
    return MockSharedPreferences();
  }

  /// Updates the user ID for WebSocket connection
  static void updateUserId(String userId) {
    _userId = userId;
    
    // Reconnect WebSocket with new user ID
    if (_isInitialized) {
      _initializeWebSocket(userId);
    }
  }
}

/// Mock SharedPreferences implementation for demonstration
/// Replace with actual SharedPreferences in production
class MockSharedPreferences {
  final Map<String, String> _storage = {};
  
  Future<String?> read({required String key}) async {
    return _storage[key];
  }
  
  Future<void> write({required String key, required String value}) async {
    _storage[key] = value;
  }
  
  Future<void> remove({required String key}) async {
    _storage.remove(key);
  }
  
  Future<void> clear() async {
    _storage.clear();
  }
}
