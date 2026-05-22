import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/emergency_request_model.dart';
import '../repositories/emergency_repository.dart';
import '../services/api_client.dart';

/// Service class for tracking emergency requests
///
/// Provides HTTP polling for patient-facing emergency tracking.
/// for Mobile Emergency Medical Assistance App.
class EmergencyTrackingService {
  static const Duration _pollingInterval = Duration(seconds: 8);

  static StreamController<EmergencyRequest>? _streamController;
  static Timer? _pollingTimer;
  static EmergencyRequest? _lastKnownState;

  /// Tracks an emergency request via HTTP polling.
  ///
  /// [requestId] - Emergency request ID to track
  ///
  /// Returns Stream of EmergencyRequest updates
  static Stream<EmergencyRequest> trackEmergencyRequest(String requestId) {
    final trimmedRequestId = requestId.trim();

    _closeTrackingStream();
    _lastKnownState = null;

    _streamController = StreamController<EmergencyRequest>.broadcast();

    if (trimmedRequestId.isEmpty) {
      Future.microtask(() {
        _streamController?.addError('Missing emergency request id');
        _closeTrackingStream();
      });
      return _streamController!.stream;
    }

    // Emit last cached state immediately
    _emitLastCachedState(trimmedRequestId);

    _pollRequestStatus(trimmedRequestId);
    _pollingTimer = Timer.periodic(_pollingInterval, (_) {
      _pollRequestStatus(trimmedRequestId);
    });

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

          debugPrint(
            'Received update via HTTP/local poll: ${request.statusDisplayName}',
          );
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
    _pollingTimer = null;

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
      'isConnected': _pollingTimer != null,
      'isPolling': _pollingTimer != null,
      'lastKnownState': _lastKnownState?.toJson(),
    };
  }
}
