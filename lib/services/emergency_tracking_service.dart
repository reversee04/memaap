import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/emergency_request_model.dart';
import '../repositories/emergency_repository.dart';
import '../services/api_client.dart';
import '../config/app_config.dart';

/// Service class for tracking emergency requests
/// 
/// Provides WebSocket streaming with HTTP polling fallback
/// for Mobile Emergency Medical Assistance App.
class EmergencyTrackingService {
  static const Duration _pollingInterval = Duration(seconds: 8);
  static const String _reconnectingSentinel = 'RECONNECTING';
  
  static StreamController<EmergencyRequest>? _streamController;
  static WebSocketChannel? _webSocketChannel;
  static Timer? _pollingTimer;
  static EmergencyRequest? _lastKnownState;
  static bool _isPolling = false;

  /// Tracks an emergency request via WebSocket with HTTP polling fallback
  /// 
  /// [requestId] - Emergency request ID to track
  /// 
  /// Returns Stream of EmergencyRequest updates
  static Stream<EmergencyRequest> trackEmergencyRequest(String requestId) {
    if (_streamController != null) {
      _streamController!.close();
    }

    _streamController = StreamController<EmergencyRequest>.broadcast();
    
    // Emit last cached state immediately
    _emitLastCachedState(requestId);
    
    // Start WebSocket connection
    _startWebSocketTracking(requestId);
    
    return _streamController!.stream;
  }

  /// Emits last cached state from SQLite
  static Future<void> _emitLastCachedState(String requestId) async {
    try {
      final cachedRequest = await EmergencyRepository.getRequestById(requestId);
      if (cachedRequest != null) {
        _lastKnownState = cachedRequest;
        _streamController?.add(cachedRequest);
      }
    } catch (e) {
      debugPrint('Failed to emit cached state: $e');
    }
  }

  /// Starts WebSocket tracking connection
  static Future<void> _startWebSocketTracking(String requestId) async {
    try {
      // Close existing connection
      await _webSocketChannel?.sink.close();
      
      // Build WebSocket URL
      final wsUrl = '${AppConfig.baseUrl.replaceFirst('http', 'ws')}/track/$requestId';
      
      _webSocketChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      
      _webSocketChannel!.stream.listen(
        (message) => _onWebSocketMessage(message),
        onError: (error) => _onWebSocketError(error),
        onDone: () => _onWebSocketDone(requestId),
      );

      debugPrint('WebSocket tracking started for request: $requestId');
      
    } catch (e) {
      debugPrint('WebSocket connection failed: $e');
      _fallbackToPolling(requestId);
    }
  }

  /// Handles WebSocket messages
  static void _onWebSocketMessage(dynamic message) {
    try {
      final data = jsonDecode(message);
      final request = EmergencyRequest.fromJson(data);
      
      _lastKnownState = request;
      _streamController?.add(request);
      
      debugPrint('Received update via WebSocket: ${request.statusDisplayName}');
      
      // Close stream if request is resolved or cancelled
      if (request.status == EmergencyStatus.completed ||
          request.status == EmergencyStatus.cancelled) {
        _closeTrackingStream();
      }
      
    } catch (e) {
      debugPrint('Failed to parse WebSocket message: $e');
    }
  }

  /// Handles WebSocket errors
  static void _onWebSocketError(dynamic error) {
    debugPrint('WebSocket error: $error');
    _fallbackToPolling(_lastKnownState?.id ?? '');
  }

  /// Handles WebSocket connection close
  static void _onWebSocketDone(String requestId) {
    debugPrint('WebSocket connection closed');
    _fallbackToPolling(requestId);
  }

  /// Falls back to HTTP polling
  static void _fallbackToPolling(String requestId) {
    if (_isPolling) return;
    
    debugPrint('Falling back to HTTP polling for request: $requestId');
    _isPolling = true;
    
    // Emit reconnecting sentinel
    _streamController?.addError(_reconnectingSentinel);
    
    // Start polling timer
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(_pollingInterval, (_) {
      _pollRequestStatus(requestId);
    });
    
    // Try to reconnect WebSocket after some time
    Timer(const Duration(seconds: 30), () {
      if (_isPolling) {
        debugPrint('Attempting to reconnect WebSocket');
        _startWebSocketTracking(requestId);
      }
    });
  }

  /// Polls request status via HTTP/SQLite
  static Future<void> _pollRequestStatus(String requestId) async {
    try {
      EmergencyRequest? request;
      try {
        final response = await ApiClient.get('/emergency/$requestId');
        request = EmergencyRequest.fromJson(response['emergency']);
      } catch (e) {
        // Fallback to local SQLite database in guest/offline/mock mode
        request = await EmergencyRepository.getRequestById(requestId);
      }
      
      if (request != null) {
        // Check if status has changed
        if (_lastKnownState == null || 
            _lastKnownState!.status != request.status ||
            _lastKnownState!.updatedAt != request.updatedAt) {
          
          _lastKnownState = request;
          _streamController?.add(request);
          
          debugPrint('Received update via local/poll: ${request.statusDisplayName}');
        }
        
        // Stop polling if request is resolved or cancelled
        if (request.status == EmergencyStatus.completed ||
            request.status == EmergencyStatus.cancelled) {
          _closeTrackingStream();
        }
      }
    } catch (e) {
      debugPrint('Polling failed: $e');
    }
  }

  /// Closes the tracking stream
  static void _closeTrackingStream() {
    debugPrint('Closing tracking stream');
    
    _pollingTimer?.cancel();
    _isPolling = false;
    
    // Close WebSocket
    _webSocketChannel?.sink.close();
    _webSocketChannel = null;
    
    // Close stream controller
    _streamController?.close();
    _streamController = null;
  }

  /// Stops tracking for a request
  static Future<void> stopTracking() async {
    _closeTrackingStream();
  }

  /// Gets current tracking status
  static Map<String, dynamic> getTrackingStatus() {
    return {
      'isConnected': _webSocketChannel != null,
      'isPolling': _isPolling,
      'lastKnownState': _lastKnownState?.toJson(),
    };
  }
}
