import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/app_config.dart';

typedef RealtimeEmergencyEventHandler = void Function(
  String event,
  Map<String, dynamic> payload,
);

class RealtimeNotificationService {
  static io.Socket? _socket;
  static RealtimeEmergencyEventHandler? _handler;

  static bool get isConnected => _socket?.connected == true;

  static String _socketBaseUrl() {
    final base = AppConfig.baseUrl;
    final trimmed = base.endsWith('/api') ? base.substring(0, base.length - 4) : base;
    return trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
  }

  static void connectResponder({
    required String responderId,
    RealtimeEmergencyEventHandler? onEvent,
  }) {
    _handler = onEvent;

    final endpoint = _socketBaseUrl();

    _socket?.dispose();
    _socket = io.io(
      endpoint,
      <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': false,
        'reconnection': true,
        'reconnectionAttempts': 20,
        'reconnectionDelay': 1000,
      },
    );

    _socket!.onConnect((_) {
      if (kDebugMode) {
        debugPrint('[RealtimeNotificationService] Connected to Socket.IO');
      }

      _socket!.emit('join_responders');
      _socket!.emit('join_responder', responderId);
    });

    _socket!.onDisconnect((_) {
      if (kDebugMode) {
        debugPrint('[RealtimeNotificationService] Disconnected from Socket.IO');
      }
    });

    _registerEmergencyEvent('emergency:new');
    _registerEmergencyEvent('emergency:assigned');
    _registerEmergencyEvent('emergency:reassigned');
    _registerEmergencyEvent('emergency:status');
    _registerEmergencyEvent('emergency:cancelled');

    _socket!.connect();
  }

  static void _registerEmergencyEvent(String eventName) {
    _socket?.on(eventName, (payload) {
      final normalized = _normalizePayload(payload);
      _handler?.call(eventName, normalized);
    });
  }

  static Map<String, dynamic> _normalizePayload(dynamic payload) {
    if (payload is Map<String, dynamic>) return payload;

    if (payload is Map) {
      return payload.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }

    if (payload is String) {
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {
        return {'raw': payload};
      }
    }

    return {'raw': payload};
  }

  static void disconnect() {
    _socket?.dispose();
    _socket = null;
  }
}
