import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/call_session_model.dart';
import '../services/call_service.dart';

enum CallUiState {
  idle,
  outgoingRinging,
  incomingRinging,
  connecting,
  active,
  ended,
  error,
}

class CallProvider extends ChangeNotifier {
  final CallService _service = CallService.instance;

  StreamSubscription<CallSession>? _incomingSub;
  StreamSubscription<CallSession>? _updateSub;
  StreamSubscription<String>? _errorSub;

  CallUiState _state = CallUiState.idle;
  CallUiState get state => _state;

  CallSession? _currentSession;
  CallSession? get currentSession => _currentSession;

  CallSession? _incomingSession;
  CallSession? get incomingSession => _incomingSession;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    await _service.initialize();

    _incomingSub = _service.incomingCalls.listen((session) {
      _incomingSession = session;
      _currentSession = session;
      _state = CallUiState.incomingRinging;
      notifyListeners();
    });

    _updateSub = _service.callUpdates.listen((session) {
      _currentSession = _mergeSession(_currentSession, session);
      _incomingSession = _mergeSession(_incomingSession, session);
      _state = _mapState(_currentSession);
      notifyListeners();
    });

    _errorSub = _service.errors.listen((message) {
      _errorMessage = message;
      _state = CallUiState.error;
      notifyListeners();
    });

    _initialized = true;
  }

  Future<void> startCall(String emergencyId) async {
    try {
      _errorMessage = null;
      _state = CallUiState.connecting;
      notifyListeners();

      final session = await _service.startCall(emergencyId);
      _currentSession = session;
      _state = CallUiState.outgoingRinging;
      notifyListeners();
    } catch (e) {
      _state = CallUiState.error;
      _errorMessage = 'Failed to start call: $e';
      notifyListeners();
    }
  }

  Future<void> acceptIncomingCall() async {
    final sessionId = _incomingSession?.id;
    if (sessionId == null || sessionId.isEmpty) return;

    try {
      _errorMessage = null;
      _state = CallUiState.connecting;
      notifyListeners();

      await _service.acceptCall(sessionId);
      _state = CallUiState.active;
      notifyListeners();
    } catch (e) {
      _state = CallUiState.error;
      _errorMessage = 'Failed to accept call: $e';
      notifyListeners();
    }
  }

  Future<void> rejectIncomingCall() async {
    final sessionId = _incomingSession?.id;
    if (sessionId == null || sessionId.isEmpty) return;

    try {
      await _service.rejectCall(sessionId);
      _state = CallUiState.ended;
      _incomingSession = null;
      _currentSession = null;
      notifyListeners();
    } catch (e) {
      _state = CallUiState.error;
      _errorMessage = 'Failed to reject call: $e';
      notifyListeners();
    }
  }

  Future<void> endCurrentCall() async {
    final sessionId = _currentSession?.id;
    if (sessionId == null || sessionId.isEmpty) return;

    try {
      await _service.endCall(sessionId);
      _state = CallUiState.ended;
      _incomingSession = null;
      _currentSession = null;
      notifyListeners();
    } catch (e) {
      _state = CallUiState.error;
      _errorMessage = 'Failed to end call: $e';
      notifyListeners();
    }
  }

  void clearIncoming() {
    _incomingSession = null;
    if (_currentSession == null) {
      _state = CallUiState.idle;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    _updateSub?.cancel();
    _errorSub?.cancel();
    super.dispose();
  }

  CallUiState _mapState(CallSession? session) {
    if (session == null) return CallUiState.idle;

    switch (session.status) {
      case CallSessionStatus.ringing:
        return CallUiState.outgoingRinging;
      case CallSessionStatus.active:
        return CallUiState.active;
      case CallSessionStatus.ended:
      case CallSessionStatus.missed:
      case CallSessionStatus.rejected:
      case CallSessionStatus.failed:
        return CallUiState.ended;
    }
  }

  CallSession? _mergeSession(CallSession? existing, CallSession update) {
    if (existing == null) return update;
    if (existing.id.isEmpty) return update;
    if (update.id.isEmpty) return existing;
    if (existing.id != update.id) return existing;

    return existing.copyWith(
      status: update.status,
      answeredAt: update.answeredAt,
      endedAt: update.endedAt,
      endReason: update.endReason,
    );
  }
}
