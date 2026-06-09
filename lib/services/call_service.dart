import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/app_config.dart';
import '../models/call_session_model.dart';
import 'api_client.dart';

class CallService {
  CallService._();
  static final CallService instance = CallService._();

  io.Socket? _socket;
  bool _isConfigured = false;

  final StreamController<CallSession> _incomingController =
      StreamController<CallSession>.broadcast();
  final StreamController<CallSession> _updateController =
      StreamController<CallSession>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  Stream<CallSession> get incomingCalls => _incomingController.stream;
  Stream<CallSession> get callUpdates => _updateController.stream;
  Stream<String> get errors => _errorController.stream;

  Future<void> initialize() async {
    if (_isConfigured) return;

    final token = ApiClient.authToken;
    if (token == null || token.isEmpty) {
      _errorController.add('Cannot initialize call service: missing auth token');
      return;
    }

    _connectSocket(token);
    _isConfigured = true;
  }

  Future<CallSession> startCall(String emergencyId) async {
    final response = await ApiClient.post('/calls/emergencies/$emergencyId/start');
    final session = CallSession.fromJson(response['callSession'] as Map<String, dynamic>);

    _ensureSocket();
    _socket?.emit('call:invite', {
      'callSessionId': session.id,
      'emergencyId': session.emergencyId,
    });

    _updateController.add(session);
    return session;
  }

  Future<CallSession?> getLatestForEmergency(String emergencyId) async {
    final response = await ApiClient.get('/calls/emergencies/$emergencyId/latest');
    final data = response['callSession'];
    if (data == null) return null;
    return CallSession.fromJson(data as Map<String, dynamic>);
  }

  Future<void> acceptCall(String callSessionId) async {
    final response = await ApiClient.post('/calls/$callSessionId/accept');
    final session = CallSession.fromJson(response['callSession'] as Map<String, dynamic>);

    _ensureSocket();
    _socket?.emit('call:accept', {'callSessionId': callSessionId});
    _updateController.add(session);
  }

  Future<void> rejectCall(String callSessionId) async {
    final response = await ApiClient.post('/calls/$callSessionId/reject');
    final session = CallSession.fromJson(response['callSession'] as Map<String, dynamic>);

    _ensureSocket();
    _socket?.emit('call:reject', {'callSessionId': callSessionId});
    _updateController.add(session);
  }

  Future<void> endCall(String callSessionId, {String endReason = 'hangup'}) async {
    final response = await ApiClient.post(
      '/calls/$callSessionId/end',
      data: {'end_reason': endReason},
    );
    final session = CallSession.fromJson(response['callSession'] as Map<String, dynamic>);

    _ensureSocket();
    _socket?.emit('call:end', {
      'callSessionId': callSessionId,
      'endReason': endReason,
    });
    _updateController.add(session);
  }

  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _isConfigured = false;
  }

  void _ensureSocket() {
    if (_socket?.connected == true) return;

    final token = ApiClient.authToken;
    if (token != null && token.isNotEmpty) {
      _connectSocket(token);
    }
  }

  void _connectSocket(String token) {
    final uri = Uri.parse(AppConfig.baseUrl);
    final socketBase = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';

    _socket?.disconnect();
    _socket?.dispose();

    _socket = io.io(
      socketBase,
      <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': true,
        'auth': {'token': token},
      },
    );

    _socket?.onConnect((_) {});

    _socket?.on('call:incoming', (dynamic data) {
      final session = _sessionFromEvent(data, fallbackStatus: 'ringing');
      if (session != null) {
        _incomingController.add(session);
      }
    });

    _socket?.on('call:ringing', (dynamic data) {
      final session = _sessionFromEvent(data, fallbackStatus: 'ringing');
      if (session != null) {
        _updateController.add(session);
      }
    });

    _socket?.on('call:accepted', (dynamic data) {
      final session = _sessionFromEvent(data, fallbackStatus: 'active');
      if (session != null) {
        _updateController.add(session);
      }
    });

    _socket?.on('call:rejected', (dynamic data) {
      final session = _sessionFromEvent(data, fallbackStatus: 'rejected');
      if (session != null) {
        _updateController.add(session);
      }
    });

    _socket?.on('call:ended', (dynamic data) {
      final session = _sessionFromEvent(data, fallbackStatus: 'ended');
      if (session != null) {
        _updateController.add(session);
      }
    });

    _socket?.on('call:error', (dynamic data) {
      if (data is Map<String, dynamic>) {
        final message = data['message']?.toString() ?? 'Call signaling error';
        _errorController.add(message);
      } else {
        _errorController.add('Call signaling error');
      }
    });

    _socket?.onDisconnect((_) {});
    _socket?.onConnectError((dynamic err) {
      _errorController.add('Call socket connect error: $err');
    });
  }

  CallSession? _sessionFromEvent(dynamic data, {required String fallbackStatus}) {
    final map = _toMap(data);
    if (map == null) return null;

    map['id'] = map['id'] ?? map['callSessionId'];
    map['status'] = map['status'] ?? fallbackStatus;

    if ((map['id']?.toString().isEmpty ?? true)) {
      return null;
    }

    return CallSession.fromJson(map);
  }

  Map<String, dynamic>? _toMap(dynamic data) {
    if (data is Map<String, dynamic>) {
      return Map<String, dynamic>.from(data);
    }

    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }

    return null;
  }
}
