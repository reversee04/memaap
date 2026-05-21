import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';
import 'package:hive/hive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/emergency_request_model.dart';
import '../services/api_client.dart';
import '../config/database_helper.dart';

/// Repository class that manages emergency requests via REST API
///
/// Provides CRUD operations, WebSocket streaming, and offline queuing
/// with Hive for Mobile Emergency Medical Assistance App.
class EmergencyRepository {
  static const String _emergencyBoxName = 'emergency_requests_queue';
  static const String _syncBoxName = 'emergency_sync_queue';

  static late Box<Map<dynamic, dynamic>> _emergencyBox;
  static late Box<Map<dynamic, dynamic>> _syncBox;
  static WebSocketChannel? _webSocketChannel;
  static StreamSubscription? _connectivitySubscription;
  static bool _isOnline = true;
  static Timer? _syncTimer;
  static Timer? _dashboardPollTimer;

  // Stream controller for request updates — initialized as broadcast
  static StreamController<EmergencyRequest>? _requestStreamController;

  /// Initializes the repository and Hive boxes
  static Future<void> initialize() async {
    try {
      // Initialize Hive boxes
      if (!Hive.isBoxOpen(_emergencyBoxName)) {
        _emergencyBox = await Hive.openBox(_emergencyBoxName);
      } else {
        _emergencyBox = Hive.box(_emergencyBoxName);
      }

      if (!Hive.isBoxOpen(_syncBoxName)) {
        _syncBox = await Hive.openBox(_syncBoxName);
      } else {
        _syncBox = Hive.box(_syncBoxName);
      }

      // Initialize connectivity monitoring
      _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
        _onConnectivityChanged,
      );

      // Check initial connectivity
      final connectivityResult = await Connectivity().checkConnectivity();
      _isOnline = connectivityResult != ConnectivityResult.none;

      // Start periodic sync
      _startPeriodicSync();
    } catch (e) {
      throw Exception('Failed to initialize EmergencyRepository: $e');
    }
  }

  /// Creates a new emergency request
  ///
  /// [request] - EmergencyRequest object to create
  ///
  /// Returns the created EmergencyRequest
  ///
  /// Throws [ApiException] if creation fails, queues offline if no network
  static Future<EmergencyRequest> createRequest(
    EmergencyRequest request,
  ) async {
    try {
      if (_isOnline) {
        // Try to create via API
        final response = await ApiClient.post(
          '/emergency/create',
          data: request.toJson(),
        );
        final createdRequest = EmergencyRequest.fromJson(response['emergency']);

        // Store in local database
        await _storeRequestLocally(createdRequest);

        return createdRequest;
      } else {
        // Queue for offline sync
        await _queueRequestForSync(request, 'create');

        // Mark as offline queued
        final offlineRequest = request.copyWith(
          isOfflineQueued: true,
          id: 'offline_${DateTime.now().millisecondsSinceEpoch}',
        );

        // Store in local database
        await _storeRequestLocally(offlineRequest);

        return offlineRequest;
      }
    } on ConflictException catch (e) {
      // Handle duplicate request conflict
      throw ApiException(
        'Duplicate emergency request: ${e.message}',
        409,
        e.data,
      );
    } catch (e) {
      if (e is ApiException && e is! NetworkException) rethrow;

      // Queue for offline sync on other errors
      await _queueRequestForSync(request, 'create');

      final offlineRequest = request.copyWith(
        isOfflineQueued: true,
        id: 'offline_${DateTime.now().millisecondsSinceEpoch}',
      );

      await _storeRequestLocally(offlineRequest);
      return offlineRequest;
    }
  }

  /// Gets an emergency request by ID
  ///
  /// [id] - Emergency request ID
  ///
  /// Returns the EmergencyRequest or null if not found
  static Future<EmergencyRequest?> getRequestById(String id) async {
    try {
      if (_isOnline) {
        // Try to get from API first
        final response = await ApiClient.get('/emergency/$id');
        final request = EmergencyRequest.fromJson(response['emergency']);

        // Update local cache
        await _storeRequestLocally(request);

        return request;
      } else {
        // Get from local database
        return await _getRequestFromDatabase(id);
      }
    } catch (e) {
      // Fallback to local database
      return await _getRequestFromDatabase(id);
    }
  }

  /// Gets all emergency requests for a specific user
  ///
  /// [userId] - User ID
  /// [status] - Optional status filter
  /// [limit] - Optional limit on number of requests
  ///
  /// Returns a list of EmergencyRequest objects
  static Future<List<EmergencyRequest>> getUserRequests(
    String userId, {
    EmergencyStatus? status,
    int? limit,
  }) async {
    try {
      if (_isOnline) {
        // Try to get from API first
        String endpoint = '/emergency/user/$userId';
        if (status != null) {
          endpoint += '?status=${status.name}';
        }
        if (limit != null) {
          endpoint += status != null ? '&limit=$limit' : '?limit=$limit';
        }

        final response = await ApiClient.get(endpoint);
        final requests = (response['emergencies'] as List)
            .map((json) => EmergencyRequest.fromJson(json))
            .toList();

        // Update local cache
        for (final request in requests) {
          await _storeRequestLocally(request);
        }

        return requests;
      } else {
        // Get from local database
        return await _getUserRequestsFromDatabase(userId, status, limit);
      }
    } catch (e) {
      // Fallback to local database
      return await _getUserRequestsFromDatabase(userId, status, limit);
    }
  }

  /// Gets all emergency requests from the local database
  static Future<List<EmergencyRequest>> getAllRequests() async {
    try {
      final db = await DatabaseHelper().database;
      final results = await db.query(
        DatabaseHelper.tableEmergencyRequests,
        orderBy: 'created_at DESC',
      );
      return results
          .map((row) => EmergencyRequest.fromDatabaseMap(row))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Stores a request in the local database directly (public wrapper)
  static Future<void> storeRequestLocally(EmergencyRequest request) async {
    await _storeRequestLocally(request);
  }

  /// Internal helper to store request in local database
  static Future<void> _storeRequestLocally(EmergencyRequest request) async {
    final db = await DatabaseHelper().database;
    await db.insert(
      DatabaseHelper.tableEmergencyRequests,
      request.toDatabaseMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Assigns a responder to an emergency request
  ///
  /// [id] - Emergency request ID
  /// [responderId] - Responder ID
  ///
  /// Returns the updated EmergencyRequest
  static Future<EmergencyRequest> assignResponder(
    String id,
    String responderId,
  ) async {
    try {
      if (_isOnline) {
        final response = await ApiClient.put('/emergency/$id/accept');

        final updatedRequest = EmergencyRequest.fromJson(response['emergency']);

        // Update local database
        await _updateRequestInDatabase(updatedRequest);

        return updatedRequest;
      } else {
        // Queue for offline sync
        final existingRequest = await _getRequestFromDatabase(id);
        if (existingRequest != null) {
          final updatedRequest = existingRequest.copyWith(
            responderId: responderId,
            responderName: 'John Responder', // Mock name
          );
          await _updateRequestInDatabase(updatedRequest);
          await _queueRequestForSync(updatedRequest, 'assign_responder');
          return updatedRequest;
        } else {
          throw Exception('Request not found: $id');
        }
      }
    } catch (e) {
      // Fallback
      final existingRequest = await _getRequestFromDatabase(id);
      if (existingRequest != null) {
        final updatedRequest = existingRequest.copyWith(
          responderId: responderId,
          responderName: 'John Responder',
        );
        await _updateRequestInDatabase(updatedRequest);
        return updatedRequest;
      } else {
        throw Exception('Request not found: $id');
      }
    }
  }

  /// Updates the status of an emergency request
  ///
  /// [id] - Emergency request ID
  /// [status] - New status
  ///
  /// Returns the updated EmergencyRequest
  static Future<EmergencyRequest> updateRequestStatus(
    String id,
    EmergencyStatus status,
  ) async {
    try {
      if (_isOnline) {
        final response = await ApiClient.put(
          '/emergency/$id/status',
          data: {'status': status.name},
        );

        final updatedRequest = EmergencyRequest.fromJson(response['emergency']);

        // Update local database
        await _updateRequestInDatabase(updatedRequest);

        return updatedRequest;
      } else {
        // Queue for offline sync
        final existingRequest = await _getRequestFromDatabase(id);
        if (existingRequest != null) {
          final updatedRequest = existingRequest.copyWith(status: status);
          await _updateRequestInDatabase(updatedRequest);

          await _queueRequestForSync(updatedRequest, 'update_status');

          return updatedRequest;
        } else {
          throw Exception('Request not found: $id');
        }
      }
    } catch (e) {
      // Queue for offline sync
      final existingRequest = await _getRequestFromDatabase(id);
      if (existingRequest != null) {
        final updatedRequest = existingRequest.copyWith(status: status);
        await _updateRequestInDatabase(updatedRequest);

        await _queueRequestForSync(updatedRequest, 'update_status');

        return updatedRequest;
      } else {
        throw Exception('Request not found: $id');
      }
    }
  }

  /// Cancels an emergency request
  ///
  /// [id] - Emergency request ID
  ///
  /// Returns the cancelled EmergencyRequest
  static Future<EmergencyRequest> cancelRequest(String id) async {
    try {
      if (_isOnline) {
        final response = await ApiClient.delete('/emergency/$id');
        final cancelledRequest = EmergencyRequest.fromJson(
          response['emergency'],
        );

        // Update local database
        await _updateRequestInDatabase(cancelledRequest);

        return cancelledRequest;
      } else {
        // Queue for offline sync
        final existingRequest = await _getRequestFromDatabase(id);
        if (existingRequest != null) {
          final cancelledRequest = existingRequest.copyWith(
            status: EmergencyStatus.cancelled,
          );

          await _updateRequestInDatabase(cancelledRequest);
          await _queueRequestForSync(cancelledRequest, 'cancel');

          return cancelledRequest;
        } else {
          throw Exception('Request not found: $id');
        }
      }
    } catch (e) {
      // Queue for offline sync
      final existingRequest = await _getRequestFromDatabase(id);
      if (existingRequest != null) {
        final cancelledRequest = existingRequest.copyWith(
          status: EmergencyStatus.cancelled,
        );

        await _updateRequestInDatabase(cancelledRequest);
        await _queueRequestForSync(cancelledRequest, 'cancel');

        return cancelledRequest;
      } else {
        throw Exception('Request not found: $id');
      }
    }
  }

  /// Creates a WebSocket connection to watch a specific request
  ///
  /// [id] - Emergency request ID to watch
  /// [onError] - Callback for errors
  ///
  /// Returns a Stream of request updates
  static Stream<EmergencyRequest> watchRequest(
    String id, {
    Function(dynamic)? onError,
  }) {
    try {
      // Always create a fresh broadcast controller
      _requestStreamController?.close();
      _requestStreamController = StreamController<EmergencyRequest>.broadcast();

      if (_webSocketChannel != null) {
        _webSocketChannel?.sink.close();
      }

      _webSocketChannel = ApiClient.createWebSocket(
        '/emergency/$id/watch',
        onMessage: (message) {
          try {
            final data = jsonDecode(message);
            final request = EmergencyRequest.fromJson(
              data['emergency'] ?? data,
            );

            // Update local database
            _updateRequestInDatabase(request);

            // Add to stream
            _requestStreamController?.add(request);
          } catch (e) {
            onError?.call(e);
          }
        },
        onError: onError,
      );

      return _requestStreamController!.stream;
    } catch (e) {
      onError?.call(e);
      // Return an empty broadcast stream on error
      _requestStreamController ??=
          StreamController<EmergencyRequest>.broadcast();
      return _requestStreamController!.stream;
    }
  }

  /// Stops watching the current request
  static Future<void> stopWatchingRequest() async {
    try {
      await _webSocketChannel?.sink.close();
      _webSocketChannel = null;
      await _requestStreamController?.close();
      _requestStreamController = null;
    } catch (e) {
      // Ignore errors during cleanup
    }
  }

  /// Updates the responder's current GPS coordinates in the database.
  ///
  /// Called by ResponderService every time a new location fix arrives.
  /// [requestId] - The active emergency request ID
  /// [lat] - Responder's current latitude
  /// [lng] - Responder's current longitude
  static Future<void> updateResponderLocation(
    String requestId,
    double lat,
    double lng,
  ) async {
    try {
      final db = await DatabaseHelper().database;
      await db.update(
        DatabaseHelper.tableEmergencyRequests,
        {
          'responder_lat': lat,
          'responder_lng': lng,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [requestId],
      );
    } catch (e) {}
  }

  /// Starts a periodic timer that polls all requests from SQLite.
  ///
  /// Used by the Responder Dashboard to detect new patient requests
  /// written offline / without a live WebSocket connection.
  ///
  /// [onNewRequests] - Callback receiving the latest list each tick
  static void startPollingForRequests(
    void Function(List<EmergencyRequest>) onNewRequests, {
    Duration interval = const Duration(seconds: 3),
  }) {
    _dashboardPollTimer?.cancel();
    _dashboardPollTimer = Timer.periodic(interval, (_) async {
      final requests = await getAllRequests();
      onNewRequests(requests);
    });
  }

  /// Stops the dashboard polling timer.
  static void stopPollingForRequests() {
    _dashboardPollTimer?.cancel();
    _dashboardPollTimer = null;
  }

  /// Syncs all queued offline requests
  ///
  /// Returns the number of requests synced
  static Future<int> syncQueuedRequests() async {
    if (!_isOnline) return 0;

    int syncedCount = 0;
    final queuedRequests = _syncBox.values.toList();

    for (final queuedData in queuedRequests) {
      try {
        final action = queuedData['action'] as String;
        final requestData = queuedData['data'] as Map<String, dynamic>;
        final request = EmergencyRequest.fromJson(requestData);

        switch (action) {
          case 'create':
            await ApiClient.post('/emergency/create', data: request.toJson());
            await _syncBox.delete(queuedData['key']);
            syncedCount++;
            break;

          case 'update_status':
            await ApiClient.put(
              '/emergency/${request.id}/status',
              data: {'status': request.status.name},
            );
            await _syncBox.delete(queuedData['key']);
            syncedCount++;
            break;

          case 'cancel':
            await ApiClient.delete('/emergency/${request.id}');
            await _syncBox.delete(queuedData['key']);
            syncedCount++;
            break;

          case 'assign_responder':
            await ApiClient.put('/emergency/${request.id}/accept');
            await _syncBox.delete(queuedData['key']);
            syncedCount++;
            break;
        }
      } catch (e) {
        // Keep in queue if sync fails
        continue;
      }
    }

    if (syncedCount > 0) {
      // Update synced timestamps
      final syncedRequests = _emergencyBox.values
          .where((r) => r['isOfflineQueued'] == true)
          .toList();

      for (final request in syncedRequests) {
        request['isOfflineQueued'] = false;
        request['syncedAt'] = DateTime.now().toIso8601String();
      }

      await _emergencyBox.putAll(
        Map.fromEntries(syncedRequests.map((r) => MapEntry(r['id'], r))),
      );
    }

    return syncedCount;
  }

  /// Queues a request for offline sync
  static Future<void> _queueRequestForSync(
    EmergencyRequest request,
    String action,
  ) async {
    final syncData = {
      'action': action,
      'data': request.toJson(),
      'timestamp': DateTime.now().toIso8601String(),
    };

    await _syncBox.add(syncData);
  }

  /// Stores a request in the local database
  // _storeRequestLocally implementation removed; using map insert version defined later.

  /// Gets a request from the local database
  static Future<EmergencyRequest?> _getRequestFromDatabase(String id) async {
    try {
      final db = await DatabaseHelper().database;

      final results = await db.query(
        DatabaseHelper.tableEmergencyRequests,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (results.isNotEmpty) {
        return EmergencyRequest.fromDatabaseMap(results.first);
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Gets user requests from the local database
  static Future<List<EmergencyRequest>> _getUserRequestsFromDatabase(
    String userId,
    EmergencyStatus? status,
    int? limit,
  ) async {
    try {
      final db = await DatabaseHelper().database;

      String whereClause = 'user_id = ?';
      List<dynamic> whereArgs = [userId];

      if (status != null) {
        whereClause += ' AND status = ?';
        whereArgs.add(status.name);
      }

      final results = await db.query(
        DatabaseHelper.tableEmergencyRequests,
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'created_at DESC',
        limit: limit,
      );

      return results
          .map((row) => EmergencyRequest.fromDatabaseMap(row))
          .toList();
    } catch (e) {
      return [];
    }
  }

  static Future<void> _updateRequestInDatabase(EmergencyRequest request) async {
    final db = await DatabaseHelper().database;
    // Ensure boolean is stored as integer
    final int isOfflineInt = request.isOfflineQueued ? 1 : 0;
    final map = request.toDatabaseMap();
    map['is_offline_queued'] = isOfflineInt;
    await db.update(
      DatabaseHelper.tableEmergencyRequests,
      map,
      where: 'id = ?',
      whereArgs: [request.id],
    );
  }

  /// Handles connectivity changes
  static void _onConnectivityChanged(List<ConnectivityResult> results) {
    final result = results.first;
    final wasOnline = _isOnline;
    _isOnline = result != ConnectivityResult.none;

    if (!wasOnline && _isOnline) {
      // Just came online, sync queued requests
      syncQueuedRequests();
    }
  }

  /// Starts periodic sync timer
  static void _startPeriodicSync() {
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_isOnline) {
        syncQueuedRequests();
      }
    });
  }

  /// Disposes of the repository
  static Future<void> dispose() async {
    try {
      await _connectivitySubscription?.cancel();
      _syncTimer?.cancel();
      await _webSocketChannel?.sink.close();
      await _requestStreamController?.close();
    } catch (e) {
      // Ignore errors during cleanup
    }
  }
}
