enum CallSessionStatus {
  ringing,
  active,
  ended,
  missed,
  rejected,
  failed,
}

class CallSession {
  final String id;
  final String emergencyId;
  final String callerUserId;
  final String calleeUserId;
  final CallSessionStatus status;
  final DateTime? startedAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;
  final String? endReason;

  const CallSession({
    required this.id,
    required this.emergencyId,
    required this.callerUserId,
    required this.calleeUserId,
    required this.status,
    this.startedAt,
    this.answeredAt,
    this.endedAt,
    this.endReason,
  });

  factory CallSession.fromJson(Map<String, dynamic> json) {
    return CallSession(
      id: json['id']?.toString() ?? '',
      emergencyId: json['emergency_id']?.toString() ?? json['emergencyId']?.toString() ?? '',
      callerUserId: json['caller_user_id']?.toString() ?? json['callerUserId']?.toString() ?? '',
      calleeUserId: json['callee_user_id']?.toString() ?? json['calleeUserId']?.toString() ?? '',
      status: _parseStatus(json['status']?.toString() ?? 'ringing'),
      startedAt: _parseDate(json['started_at'] ?? json['startedAt']),
      answeredAt: _parseDate(json['answered_at'] ?? json['answeredAt']),
      endedAt: _parseDate(json['ended_at'] ?? json['endedAt']),
      endReason: json['end_reason']?.toString() ?? json['endReason']?.toString(),
    );
  }

  CallSession copyWith({
    CallSessionStatus? status,
    DateTime? answeredAt,
    DateTime? endedAt,
    String? endReason,
  }) {
    return CallSession(
      id: id,
      emergencyId: emergencyId,
      callerUserId: callerUserId,
      calleeUserId: calleeUserId,
      status: status ?? this.status,
      startedAt: startedAt,
      answeredAt: answeredAt ?? this.answeredAt,
      endedAt: endedAt ?? this.endedAt,
      endReason: endReason ?? this.endReason,
    );
  }

  static CallSessionStatus _parseStatus(String value) {
    switch (value) {
      case 'ringing':
        return CallSessionStatus.ringing;
      case 'active':
        return CallSessionStatus.active;
      case 'ended':
        return CallSessionStatus.ended;
      case 'missed':
        return CallSessionStatus.missed;
      case 'rejected':
        return CallSessionStatus.rejected;
      case 'failed':
        return CallSessionStatus.failed;
      default:
        return CallSessionStatus.ringing;
    }
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}
